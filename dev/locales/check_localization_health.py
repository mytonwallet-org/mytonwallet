#!/usr/bin/env python3
"""Check YAML catalogs and literal localization calls; report every finding before exiting."""

import argparse
import bisect
import difflib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "mobile/ios/Air/scripts/strings"))
import import_localizations as importer


@dataclass(frozen=True)
class Issue:
    path: Path
    line: int
    code: str
    message: str

    def render(self, root):
        return f"{self.path.relative_to(root)}:{self.line}: [{self.code}] {self.message}"


def read_catalog(path, issues):
    """Read nodes as well as values so duplicate keys and plural forms retain locations."""
    try:
        node = yaml.compose(path.read_text(encoding="utf-8"), Loader=yaml.SafeLoader)
    except (OSError, UnicodeError, yaml.YAMLError) as error:
        mark = getattr(error, "problem_mark", None)
        message = f"Save this catalog as UTF-8: {error}" if isinstance(error, UnicodeError) else str(error)
        issues.append(Issue(path, mark.line + 1 if mark else 1, "yaml", message))
        return None
    if not isinstance(node, yaml.MappingNode) or not node.value:
        issues.append(Issue(path, 1, "yaml", "Expected a nonempty mapping of localization keys to strings or plural forms."))
        return None

    entries = {}
    for key_node, value_node in node.value:
        if key_node.tag != "tag:yaml.org,2002:str":
            issues.append(Issue(path, key_node.start_mark.line + 1, "key", "Localization keys must be strings; quote this key."))
            continue
        key = key_node.value
        line = key_node.start_mark.line + 1
        if key in entries:
            issues.append(Issue(path, line, "duplicate", f"{key!r} is defined twice (first at line {entries[key][0]}). Remove the duplicate."))
        forms = []
        plural = isinstance(value_node, yaml.MappingNode)
        if plural:
            seen = set()
            for form_node, text_node in value_node.value:
                if form_node.tag != "tag:yaml.org,2002:str":
                    issues.append(Issue(path, form_node.start_mark.line + 1, "plural", f"{key!r}: plural form names must be strings such as otherValue."))
                    continue
                form = form_node.value
                if form in seen:
                    issues.append(Issue(path, form_node.start_mark.line + 1, "duplicate", f"{key!r}.{form} is defined twice. Remove the duplicate form."))
                seen.add(form)
                if form not in importer.PLURAL_KEYS:
                    issues.append(Issue(path, form_node.start_mark.line + 1, "plural", f"{key!r}: unknown plural form {form!r}. Use one of {', '.join(importer.PLURAL_KEYS)}."))
                forms.append((form, text_node))
            if not forms:
                issues.append(Issue(path, line, "plural", f"{key!r}: provide at least one plural form."))
        else:
            forms.append((None, value_node))
        texts = []
        for form, text_node in forms:
            text_line = text_node.start_mark.line + 1
            label = f"{key!r}" + (f".{form}" if form else "")
            if text_node.tag != "tag:yaml.org,2002:str":
                issues.append(Issue(path, text_line, "value", f"{label}: expected a string. Quote numbers/booleans and replace null with a translation."))
                continue
            texts.append((form, text_node.value, text_line))
        entries[key] = (line, plural, texts)
        for text, text_line, label in [(key, line, "key")] + [(text, ln, form or "value") for form, text, ln in texts]:
            legacy = list(dict.fromkeys(importer.LEGACY_PLACEHOLDER_RE.findall(text)))
            if legacy:
                issues.append(Issue(path, text_line, "positional", f"{key!r} ({label}): replace {', '.join(repr(p) for p in legacy)} with named placeholders such as %amount%; match the names in en.yaml."))
    return entries


# This is a lexical regex scan, not a compiler. Comments and strings are consumed as
# whole tokens, keeping examples in comments/strings out of the call-site report.
TOKEN_RE = re.compile(
    r'(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)'
    r'|(?P<string>"""[\s\S]*?"""|"(?:\\[\s\S]|[^"\\])*"|\'(?:\\[\s\S]|[^\'\\])*\'|`(?:\\[\s\S]|[^`\\])*`)'
    r'|(?P<word>[A-Za-z_$][\w$]*)|(?P<other>\+\+|--|[^\s])'
)
REGEX_LITERAL_RE = re.compile(r'(?P<regex>/(?![/*])(?:\\[^\r\n]|\[(?:\\[^\r\n]|[^\]\\\r\n])*\]|[^/\\\[\r\n])+/[a-z]*)')
REGEX_PREFIXES = {"=", "(", "[", "{", ",", ":", ";", "?", "!", "&", "|", "+", "-", "*", "%", "^", "~"}
REGEX_PREFIX_WORDS = {"return", "throw", "case", "delete", "void", "typeof", "in", "instanceof", "yield", "await", "else", "do"}
CALLS = {
    "web": {"lang": 0, "getTranslation": 0},
    "ios": {"lang": 0, "langMd": 0, "localized": 0, "NSLocalizedString": 0, "LocalizedStringResource": 0, "localizedString": 0, "String": 0},
    "android": {
        "getString": 0, "getStringOrNull": 0, "getFormattedString": 0,
        "getStringWithKeyValues": 0, "getSpannableStringWithKeyValues": 0,
        "getPluralOrFormat": 0, "getPlural": 1, "getPluralWord": 1,
    },
}
ESCAPE_RE = re.compile(r"\\(?:u\{([0-9A-Fa-f]+)\}|u([0-9A-Fa-f]{4})|x([0-9A-Fa-f]{2})|([\s\S]))")


def literal_value(token, platform):
    if token.lastgroup != "string" or token[0].startswith('"""'):
        return None
    body = token[0][1:-1]
    # Remove escaped pairs before checking for interpolation, so Kotlin \$key is literal.
    unescaped = re.sub(r"\\[\s\S]", "", body)
    if platform == "android" and re.search(r"\$(?:\{|[\w])", unescaped):
        return None
    if platform == "web" and token[0][0] == "`" and "${" in unescaped:
        return None
    if platform == "ios" and re.search(r"(?<!\\)(?:\\\\)*\\\(", body):
        return None

    def decode(match):
        if match[1] or match[2] or match[3]:
            return chr(int(match[1] or match[2] or match[3], 16))
        return {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "\n": ""}.get(match[4], match[4])

    return ESCAPE_RE.sub(decode, body)


def source_tokens(text, platform):
    tokens, control_parens = [], []
    cursor, after_control = 0, False
    while cursor < len(text):
        token = TOKEN_RE.match(text, cursor)
        if token is None:
            cursor += 1
            continue
        if token.lastgroup == "comment":
            cursor = token.end()
            continue
        previous = tokens[-1][0] if tokens else None
        before_previous = tokens[-2][0] if len(tokens) > 1 else None
        if platform == "web" and token[0] == "/":
            # Slash is also division or a JSX delimiter. Recognize regexes only at
            # expression starts so `value / lang("Key") / divisor` keeps its call.
            can_start_regex = (
                previous is None or previous in REGEX_PREFIXES or after_control
                or (previous in REGEX_PREFIX_WORDS and before_previous != ".")
                or (previous == ">" and before_previous == "=")
            )
            if can_start_regex:
                token = REGEX_LITERAL_RE.match(text, cursor) or token
        cursor = token.end()
        after_control = False
        if token[0] == "(":
            control_parens.append(previous in {"if", "while", "for", "with", "switch", "catch"})
        elif token[0] == ")" and control_parens:
            after_control = control_parens.pop()
        tokens.append(token)
    return tokens


def literal_calls(text, platform):
    tokens = source_tokens(text, platform)
    newlines = [match.start() for match in re.finditer("\n", text)]
    for index, token in enumerate(tokens[:-1]):
        name = token[0]
        if token.lastgroup != "word" or name not in CALLS[platform] or tokens[index + 1][0] != "(":
            continue
        # Android's unrelated Context.getString(R.string.*) has no literal first argument.
        # Limit qualified calls to LocaleController to avoid other string APIs.
        if platform == "android" and index >= 2 and tokens[index - 1][0] == "." and tokens[index - 2][0] != "LocaleController":
            continue
        args, current, depth = [], [], 0
        for part in tokens[index + 2:]:
            value = part[0]
            if value in (")", ",") and depth == 0:
                args.append(current)
                current = []
                if value == ")":
                    break
            else:
                current.append(part)
                if value in ("(", "[", "{"):
                    depth += 1
                elif value in (")", "]", "}"):
                    depth -= 1
        key_index = CALLS[platform][name]
        argument = args[key_index] if len(args) > key_index else []
        if platform == "android":
            argument = next((arg[2:] for arg in args if len(arg) >= 2 and arg[0][0] == "key" and arg[1][0] == "="), argument)
        if platform == "ios" and name == "localizedString":
            argument = argument[2:] if len(argument) >= 2 and argument[0][0] == "forKey" and argument[1][0] == ":" else []
        if platform == "ios" and name == "String":
            argument = argument[2:] if len(argument) >= 2 and argument[0][0] == "localized" and argument[1][0] == ":" else []
        if len(argument) == 1:
            key = literal_value(argument[0], platform)
            if key is not None:
                yield key, bisect.bisect_left(newlines, argument[0].start()) + 1


def source_paths(root):
    # Include uncommitted new files, honor gitignore, and avoid generated SDKs/catalogs.
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "src", "mobile/ios", "mobile/android"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    for name in sorted(set(result.stdout.split("\0")) - {""}):
        path = Path(name)
        # These English-only apps replace langProvider's catalog with an empty JSON mock.
        if path.is_relative_to("src/multisend") or path.is_relative_to("src/portfolio"):
            continue
        if any(part in {"Pods", "build", ".build", "node_modules", "Tests", "tests", "test", "__tests__", "androidTest"} for part in path.parts):
            continue
        if re.search(r"\.(test|spec)\.", path.name):
            continue
        platform = {".swift": "ios", ".kt": "android", ".java": "android", ".ts": "web", ".tsx": "web", ".js": "web", ".jsx": "web"}.get(path.suffix)
        if platform and (root / path).is_file():
            yield root / path, platform


def check_catalogs(root, directory, issues):
    catalogs = {}
    paths = sorted(directory.glob("*.yaml")) + sorted(directory.glob("*.yml"))
    for path in paths:
        catalog = read_catalog(path, issues)
        if catalog is not None:
            catalogs[path] = catalog
    base_path = directory / "en.yaml"
    base_label = base_path.relative_to(root)
    base = catalogs.get(base_path)
    if base is None:
        if base_path not in paths:
            issues.append(Issue(base_path, 1, "source", "Add the English source catalog; key parity and call-site checks require it."))
    else:
        for path, catalog in catalogs.items():
            for key in sorted(base.keys() - catalog.keys()):
                issues.append(Issue(path, 1, "missing-key", f"Add {key!r}; defined at {base_label}:{base[key][0]}."))
            for key in sorted(catalog.keys() - base.keys()):
                issues.append(Issue(path, catalog[key][0], "extra-key", f"{key!r} is absent from en.yaml. Correct the key or add it to every catalog."))
            for key in sorted(catalog.keys() & base.keys()):
                _, _, texts = catalog[key]
                names = {name for _, text, _ in base[key][2] for name in importer.NAMED_PLACEHOLDER_RE.findall(text)}
                for form, text, text_line in texts:
                    unknown = set(importer.NAMED_PLACEHOLDER_RE.findall(text)) - names
                    if unknown:
                        issues.append(Issue(path, text_line, "placeholder", f"{key!r}" + (f".{form}" if form else "") + f": unknown placeholders {', '.join(sorted(unknown))}. Allowed by en.yaml: {', '.join(sorted(names)) or '(none)'}."))
    return base, len(paths)


def check(root, sources=None, excluded_paths=()):
    issues = []
    # MFA and Push replace the shared langProvider's catalog at build time.
    directories = [root / "src/i18n"] + [root / f"src/{app}/i18n" for app in ("mfa", "push") if (root / f"src/{app}").is_dir()]
    catalogs = {directory: check_catalogs(root, directory, issues) for directory in directories}
    for path, platform in source_paths(root) if sources is None else sources:
        if any(path.relative_to(root).is_relative_to(excluded) for excluded in excluded_paths):
            continue
        directory = next((directory for directory in directories[1:] if path.is_relative_to(directory.parent)), directories[0])
        base, locale_count = catalogs[directory]
        if base is None:
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            issues.append(Issue(path, 1, "source", f"Cannot read source; ensure the file is readable UTF-8: {error}"))
            continue
        for key, line in literal_calls(source, platform):
            if key not in base:
                suggestions = difflib.get_close_matches(key, base, n=1, cutoff=0.8)
                hint = f" Did you mean {suggestions[0]!r}?" if suggestions else ""
                issues.append(Issue(path, line, "unlocalized-call", f"{key!r} is missing from {directory.relative_to(root)}/en.yaml. Correct the call or add this key and translations to all {locale_count} catalogs.{hint}"))
    return sorted(issues, key=lambda issue: (str(issue.path), issue.line, issue.code, issue.message))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="Repository checkout to check")
    parser.add_argument("--exclude-path", type=Path, action="append", default=[], help="Skip call sites under this repository-relative path; catalogs are still checked")
    args = parser.parse_args()
    root = args.root.resolve()
    if any(path.is_absolute() or ".." in path.parts or path == Path(".") for path in args.exclude_path):
        parser.error("--exclude-path must name a repository-relative file or directory")
    if args.exclude_path:
        print("Call-site exclusions: " + ", ".join(map(str, args.exclude_path)))
    issues = check(root, excluded_paths=args.exclude_path)
    for issue in issues:
        print(issue.render(root))
    print(f"Localization health: {len(issues)} issue(s)." if issues else "Localization health: all YAML catalogs and scanned literal calls pass.")
    return bool(issues)


if __name__ == "__main__":
    sys.exit(main())

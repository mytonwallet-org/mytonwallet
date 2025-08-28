#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
from pathlib import Path

# Matches:
#   WStrings.Language.Active.localized
#   WStrings.Language_Active.localized
#   WStrings.Foo.Bar.Baz.localized
#
# Captures the dotted tail ".Language.Active" (or ".Language_Active")
WSTRINGS_PATTERN = re.compile(
    r'\bWStrings((?:\.[A-Za-z_]\w*)*)\.localized\b'
)

def swift_escape(s: str) -> str:
    """Escape a Python string into a Swift string literal."""
    s = s.replace('\\', '\\\\')
    s = s.replace('"', '\\"')
    s = s.replace('\r\n', '\n')  # normalize
    s = s.replace('\r', '\n')
    s = s.replace('\n', '\\n')
    return s

def compute_key_from_segments(dot_tail: str) -> str:
    """
    dot_tail example: ".Language.Active" or ".Language_Active"
    We split on '.' and join non-empty parts with '_'
    """
    if not dot_tail:
        return ""
    parts = [p for p in dot_tail.split('.') if p]  # remove leading empty
    return "_".join(parts)

def make_replacer(mapping: dict):
    def _repl(m: re.Match):
        dot_tail = m.group(1)  # like ".Language.Active"
        dict_key = compute_key_from_segments(dot_tail)
        value = mapping.get(dict_key, dict_key)
        return f'lang("{swift_escape(value)}")'
    return _repl

def process_file(path: Path, mapping: dict) -> bool:
    """Return True if file changed."""
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        # Fall back to other encodings if necessary
        for enc in ("utf-16", "utf-16-le", "utf-8-sig"):
            try:
                text = path.read_text(encoding=enc)
                break
            except Exception:
                continue
        else:
            print(f"Skipping unreadable file: {path}", file=sys.stderr)
            return False

    replacer = make_replacer(mapping)
    new_text, n = WSTRINGS_PATTERN.subn(replacer, text)
    if n > 0 and new_text != text:
        path.write_text(new_text, encoding="utf-8")
        return True
    return False

def iter_swift_files(root: Path):
    for p in root.rglob("*.swift"):
        if p.is_file():
            yield p

def main():
    ap = argparse.ArgumentParser(
        description="Replace WStrings.*.localized with lang(\"value\") using a provided JSON dictionary."
    )
    ap.add_argument("src_root", help="Root directory to scan for .swift files")
    ap.add_argument("json_dict", help="Path to JSON dictionary (keys like Language_Active)")
    ap.add_argument("--dry-run", action="store_true", help="Report changes but do not modify files")
    args = ap.parse_args()

    root = Path(args.src_root)
    if not root.exists():
        print(f"Source root not found: {root}", file=sys.stderr)
        sys.exit(1)

    try:
        mapping = json.loads(Path(args.json_dict).read_text(encoding="utf-8"))
    except Exception as e:
        print(f"Failed to read JSON mapping: {e}", file=sys.stderr)
        sys.exit(1)

    # Ensure string values
    mapping = {str(k): str(v) for k, v in mapping.items()}

    total = 0
    changed = 0

    for swift_file in iter_swift_files(root):
        total += 1
        try:
            text = swift_file.read_text(encoding="utf-8")
        except Exception:
            # handle in process_file
            text = None

        if args.dry_run:
            matches = list(WSTRINGS_PATTERN.finditer(text if text is not None else swift_file.read_text(encoding="utf-8")))
            if matches:
                print(f"[would change] {swift_file} ({len(matches)} occurrences)")
        else:
            if process_file(swift_file, mapping):
                changed += 1
                print(f"[changed] {swift_file}")

    if args.dry_run:
        print("Dry run complete.")
    else:
        print(f"Done. Scanned {total} .swift files, modified {changed}.")

if __name__ == "__main__":
    main()
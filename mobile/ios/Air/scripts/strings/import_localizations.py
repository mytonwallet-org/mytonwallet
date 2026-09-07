#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import os
import re
import unicodedata
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

import yaml  # pip install pyyaml

PLURAL_KEYS = {
    "zeroValue": "zero",
    "oneValue": "one",
    "twoValue": "two",
    "fewValue": "few",
    "manyValue": "many",
    "otherValue": "other",
}

SCRIPT_DIR = Path(__file__).resolve().parent


class ParameterKind(Enum):
    STRING = ("String", "@")
    INTEGER = ("Int", "lld")
    DOUBLE = ("Double", "f")

    @property
    def swift_type(self) -> str:
        return self.value[0]

    @property
    def format_specifier(self) -> str:
        return self.value[1]


@dataclass(frozen=True)
class Parameter:
    name: str
    swift_name: str
    index: int
    kind: ParameterKind


@dataclass(frozen=True)
class EntryDefinition:
    key: str
    swift_name: str
    parameters: tuple[Parameter, ...]
    is_plural: bool
    default_value: str


NAMED_PLACEHOLDER_RE = re.compile(r"%([a-zA-Z_][a-zA-Z0-9_]*)%")
LEGACY_PLACEHOLDER_RE = re.compile(
    r"%(?:(?:[1-9][0-9]*\$)[-+ #0]*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?"
    r"(?:hh|h|ll|l|j|z|t|L)?[@diuoxXfFeEgGaAcsp]|(?:@|lld|ld|d|s|f))"
    r"(?![a-zA-Z0-9_])"
)

SWIFT_KEYWORDS = {
    "Any",
    "Protocol",
    "Self",
    "Type",
    "actor",
    "as",
    "associatedtype",
    "associativity",
    "async",
    "await",
    "borrowing",
    "break",
    "case",
    "catch",
    "class",
    "consume",
    "consuming",
    "continue",
    "convenience",
    "copy",
    "default",
    "defer",
    "deinit",
    "didSet",
    "distributed",
    "do",
    "dynamic",
    "else",
    "enum",
    "extension",
    "fallthrough",
    "false",
    "fileprivate",
    "final",
    "for",
    "func",
    "get",
    "guard",
    "if",
    "import",
    "in",
    "indirect",
    "infix",
    "init",
    "inout",
    "internal",
    "is",
    "isolated",
    "lazy",
    "left",
    "let",
    "macro",
    "mutating",
    "nil",
    "nonisolated",
    "nonmutating",
    "open",
    "operator",
    "optional",
    "override",
    "package",
    "postfix",
    "precedence",
    "precedencegroup",
    "prefix",
    "private",
    "protocol",
    "public",
    "repeat",
    "required",
    "rethrows",
    "return",
    "right",
    "safe",
    "self",
    "set",
    "some",
    "static",
    "struct",
    "subscript",
    "super",
    "switch",
    "throws",
    "true",
    "try",
    "typealias",
    "unowned",
    "unsafe",
    "var",
    "weak",
    "where",
    "while",
    "willSet",
}

INTEGER_PARAMETER_NAMES = {
    "completed",
    "count",
    "counts",
    "current",
    "hours",
    "length",
    "minutes",
    "number",
    "seconds",
    "total",
}

PLACEHOLDER_TYPE_OVERRIDES: dict[str, dict[str, ParameterKind]] = {
    "$auth_import_mnemonic_description": {
        "counts": ParameterKind.STRING,
    },
    "$domains_expire": {
        "days": ParameterKind.STRING,
    },
    "push_domain_expires_in_days_number": {
        "domain": ParameterKind.STRING,
    },
    "push_domain_expired_days_ago_number": {
        "domain": ParameterKind.STRING,
    },
}

MAIN_APP_LOCALIZATION_KEYS = {
    "Account",
    "Accounts",
    "Add crypto with ${applicationName}",
    "Amount",
    "Comment",
    "Network",
    "Networks",
    "Open send in ${applicationName}",
    "Open receive in ${applicationName}",
    "Open scanner in ${applicationName}",
    "Open ${target} in ${applicationName}",
    "Open the QR scanner.",
    "Open the receive screen.",
    "Open the send screen.",
    "Open the token screen.",
    "Open Token",
    "Receive",
    "Receive Funds",
    "Receive with ${applicationName}",
    "Send",
    "Send crypto with ${applicationName}",
    "Send Token",
    "Send token with ${applicationName}",
    "Show ${target} in ${applicationName}",
    "Scan a code with ${applicationName}",
    "Scan QR",
    "Scan QR Code",
    "Scan QR with ${applicationName}",
    "Token",
    "Wallet",
}


def resolve_relative_to_script(path: str) -> Path:
    path_obj = Path(path)
    if path_obj.is_absolute():
        return path_obj
    return (SCRIPT_DIR / path_obj).resolve()


def load_yaml(path: str | Path):
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data or {}


def load_json(path: str | Path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data or {}


def load_file(path: str | Path):
    path_obj = Path(path)
    suffix = path_obj.suffix.lower()
    if suffix in (".yaml", ".yml"):
        return load_yaml(path_obj)
    if suffix == ".json":
        return load_json(path_obj)
    raise ValueError(f"Unsupported file extension: {path_obj.suffix}. Only .json, .yaml, and .yml are supported.")

def detect_locales(inputs, source_locale="en"):
    locales = []
    for p in inputs:
        name = os.path.splitext(os.path.basename(p))[0]
        if name.lower() == source_locale.lower():
            locales.insert(0, name)
        else:
            locales.append(name)
    return locales

def trim_trailing_newlines(s: str) -> str:
    return s.rstrip("\r\n")

def normalize_value(v):
    if v is None:
        return ""
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return trim_trailing_newlines(v)
    return trim_trailing_newlines(json.dumps(v, ensure_ascii=False))


def lower_camel_case(value: str) -> str:
    components = [component for component in value.split("_") if component]
    if not components:
        raise ValueError(f"Cannot generate a Swift identifier from '{value}'.")
    result = components[0][:1].lower() + components[0][1:] + "".join(
        component[:1].upper() + component[1:] for component in components[1:]
    )
    return f"{result}_" if result in SWIFT_KEYWORDS else result


def swift_symbol_name(key: str) -> str:
    source = key[1:] if key.startswith("$") else key

    def placeholder_words(match: re.Match[str]) -> str:
        name = match.group(1).replace("_", " ")
        name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", name)
        return f" {name} "

    source = NAMED_PLACEHOLDER_RE.sub(
        placeholder_words,
        source,
    )
    source = unicodedata.normalize("NFKD", source).encode("ascii", "ignore").decode("ascii")
    words = re.findall(r"[a-zA-Z0-9]+", source)
    if not words:
        raise ValueError(f"Cannot generate a Swift symbol from localization key '{key}'.")

    symbol = words[0].lower() + "".join(
        word[:1].upper() + word[1:].lower()
        for word in words[1:]
    )
    if symbol[0].isdigit():
        symbol = f"_{symbol}"
    if symbol in SWIFT_KEYWORDS:
        symbol = f"{symbol}_"
    return symbol


def strings_in_value(value) -> list[str]:
    if isinstance(value, str):
        return [normalize_value(value)]
    if is_plural_block(value):
        result = []
        for yaml_key in PLURAL_KEYS:
            if yaml_key in value and value[yaml_key] is not None:
                result.append(normalize_value(value[yaml_key]))
        return result
    return []


def ordered_parameter_names(value) -> list[str]:
    result = []
    for text in strings_in_value(value):
        for match in NAMED_PLACEHOLDER_RE.finditer(text):
            name = match.group(1)
            if name not in result:
                result.append(name)
    return result


def infer_parameter_kind(key: str, name: str, is_plural: bool) -> ParameterKind:
    override = PLACEHOLDER_TYPE_OVERRIDES.get(key, {}).get(name)
    if override is not None:
        return override
    if key.startswith("$agent_semantic_") and name == "amount":
        return ParameterKind.INTEGER
    if is_plural or name in INTEGER_PARAMETER_NAMES:
        return ParameterKind.INTEGER
    return ParameterKind.STRING


def select_default_value(key: str, value, parameter_names: list[str]) -> str:
    if isinstance(value, str):
        return normalize_value(value)

    candidates = []
    if isinstance(value, dict):
        for yaml_key in ("otherValue", "oneValue", "zeroValue", "twoValue", "fewValue", "manyValue"):
            if yaml_key in value and value[yaml_key] is not None:
                candidates.append(normalize_value(value[yaml_key]))

    required_names = set(parameter_names)
    for candidate in candidates:
        if required_names.issubset(set(NAMED_PLACEHOLDER_RE.findall(candidate))):
            return candidate

    if required_names:
        raise ValueError(
            f"Source localization '{key}' has no plural form containing all parameters: "
            f"{', '.join(parameter_names)}."
        )
    return candidates[0] if candidates else ""


def validate_parameter_indices(definition: EntryDefinition):
    interpolations = NAMED_PLACEHOLDER_RE.findall(definition.default_value)
    for parameter in definition.parameters:
        if not 1 <= parameter.index <= len(interpolations) or interpolations[parameter.index - 1] != parameter.name:
            raise ValueError(
                f"Localization '{definition.key}' parameter '{parameter.name}' at position {parameter.index} "
                "does not match the Swift default value's interpolation order."
            )


def build_entry_definitions(source_map: dict) -> dict[str, EntryDefinition]:
    definitions = {}
    generated_names = {}

    for key, value in source_map.items():
        localized_strings = strings_in_value(value)
        for text in localized_strings:
            match = LEGACY_PLACEHOLDER_RE.search(text)
            if match:
                raise ValueError(
                    f"Localization '{key}' contains legacy format specifier '{match.group(0)}'. "
                    "Use a named placeholder such as %value%."
                )

        parameter_names = ordered_parameter_names(value)
        if not parameter_names:
            continue
        swift_name = swift_symbol_name(str(key))
        previous_key = generated_names.get(swift_name)
        if previous_key is not None:
            raise ValueError(
                f"Localization keys '{previous_key}' and '{key}' both generate Swift symbol '{swift_name}'."
            )
        generated_names[swift_name] = key

        default_value = select_default_value(str(key), value, parameter_names)
        # Swift supplies arguments in interpolation order, including repeated occurrences.
        # Public parameter order can differ when an earlier plural form omits a parameter.
        argument_indices = {}
        for index, name in enumerate(NAMED_PLACEHOLDER_RE.findall(default_value), start=1):
            argument_indices.setdefault(name, index)

        is_plural = is_plural_block(value)
        parameters = tuple(
            Parameter(
                name=name,
                swift_name=lower_camel_case(name),
                index=argument_indices[name],
                kind=infer_parameter_kind(str(key), name, is_plural),
            )
            for name in parameter_names
        )
        swift_parameter_names = [parameter.swift_name for parameter in parameters]
        if len(set(swift_parameter_names)) != len(swift_parameter_names):
            raise ValueError(f"Localization '{key}' contains colliding Swift parameter names.")

        definition = EntryDefinition(
            key=str(key),
            swift_name=swift_name,
            parameters=parameters,
            is_plural=is_plural,
            default_value=default_value,
        )
        validate_parameter_indices(definition)
        definitions[str(key)] = definition

    return definitions


def replace_named_placeholders(key: str, text: str, definition: EntryDefinition | None) -> str:
    parameters = {parameter.name: parameter for parameter in definition.parameters} if definition else {}

    def repl(match):
        name = match.group(1)
        parameter = parameters.get(name)
        if parameter is None:
            raise ValueError(f"Localization '{key}' contains unknown parameter '{name}'.")
        return f"%{parameter.index}$({parameter.name}){parameter.kind.format_specifier}"

    original_match = LEGACY_PLACEHOLDER_RE.search(text)
    if original_match:
        raise ValueError(
            f"Localization '{key}' contains legacy format specifier '{original_match.group(0)}'."
        )

    if NAMED_PLACEHOLDER_RE.search(text) is None:
        return text

    # xcstrings values use printf formatting once interpolations are present, so every
    # percent sign outside a named placeholder must be escaped as a literal percent.
    result = []
    cursor = 0
    for match in NAMED_PLACEHOLDER_RE.finditer(text):
        result.append(text[cursor:match.start()].replace("%", "%%"))
        result.append(repl(match))
        cursor = match.end()
    result.append(text[cursor:].replace("%", "%%"))
    return "".join(result)

def is_plural_block(v) -> bool:
    return isinstance(v, dict) and any(k in v for k in PLURAL_KEYS.keys())

def build_nonplural_unit(key: str, text: str, definition: EntryDefinition | None):
    s = normalize_value(text)
    replaced = replace_named_placeholders(key, s, definition)
    return {
        "stringUnit": {
            "state": "translated",
            "value": replaced,
        }
    }

def build_plural_unit(key: str, forms: dict, definition: EntryDefinition | None):
    variations = {}
    plural_keys_order = ["zeroValue","oneValue","twoValue","fewValue","manyValue","otherValue"]
    for yaml_key in plural_keys_order:
        if yaml_key in forms and forms[yaml_key] is not None:
            v = normalize_value(forms[yaml_key])
            replaced = replace_named_placeholders(key, v, definition)
            cat = PLURAL_KEYS[yaml_key]
            variations[cat] = {
                "stringUnit": {
                    "state": "translated",
                    "value": replaced
                }
            }

    if not variations:
        return {"stringUnit": {"state": "translated", "value": ""}}

    return {
        "stringUnit": {
            "state": "translated",
            "value": ""
        },
        "variations": {
            "plural": variations
        }
    }

def merge_localization_bucket(dst_bucket, lang, unit):
    dst_bucket.setdefault("localizations", {})
    dst_bucket["localizations"][lang] = unit
    dst_bucket["extractionState"] = "manual"
    dst_bucket["generatesSymbol"] = False

def normalize_locale_name(filename: str) -> str:
    """Normalize locale name from a localization filename."""
    name = os.path.splitext(filename)[0]
    if name.startswith('air_'):
        name = name[4:]  # Remove 'air_' prefix
    return name


def build_strings_map(
    per_locale: dict,
    source_locale: str,
    locales: list[str],
    definitions: dict[str, EntryDefinition],
    key_predicate=None,
) -> dict:
    source_locale_lower = source_locale.lower()
    src_map = per_locale.get(source_locale_lower, {})
    strings = {}

    ordered_locales = [source_locale_lower] + sorted(
        [l for l in locales if l != source_locale_lower],
        key=lambda x: str(x).lower()
    )

    for key in (src_map or {}).keys():
        if key_predicate is not None and not key_predicate(key):
            continue

        bucket = {}
        for loc in ordered_locales:
            loc_map = per_locale.get(loc, {})
            if key not in loc_map:
                continue
            v = loc_map[key]
            definition = definitions.get(str(key))
            try:
                unit = (
                    build_plural_unit(str(key), v, definition)
                    if is_plural_block(v)
                    else build_nonplural_unit(str(key), v, definition)
                )
            except ValueError as error:
                raise ValueError(f"Locale '{loc}', localization '{key}': {error}") from error
            merge_localization_bucket(bucket, loc, unit)

        if "localizations" in bucket:
            strings[key] = bucket

    return dict(sorted(strings.items(), key=lambda x: str(x[0])))


def with_extraction_state(strings: dict, extraction_state: str) -> dict:
    updated_strings = copy.deepcopy(strings)
    for bucket in updated_strings.values():
        bucket["extractionState"] = extraction_state
    return updated_strings


def write_catalog(output_path: Path, source_locale: str, strings: dict):
    catalog = {
        "sourceLanguage": source_locale,
        "version": "1.0",
        "strings": strings,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)


def swift_escape(value: str) -> str:
    return (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def swift_localization_value(default_value: str, definition: EntryDefinition) -> str:
    parameters = {parameter.name: parameter for parameter in definition.parameters}
    result = []
    cursor = 0
    for match in NAMED_PLACEHOLDER_RE.finditer(default_value):
        result.append(swift_escape(default_value[cursor:match.start()]))
        parameter = parameters[match.group(1)]
        if parameter.kind == ParameterKind.STRING:
            result.append(f"\\({parameter.swift_name})")
        else:
            result.append(
                f'\\({parameter.swift_name}, specifier: "%{parameter.kind.format_specifier}")'
            )
        cursor = match.end()
    result.append(swift_escape(default_value[cursor:]))
    return "".join(result)


def write_swift_interface(output_path: Path, definitions: dict[str, EntryDefinition]):
    lines = [
        "// This file is generated by import_localizations.py. Do not edit manually.",
        "",
        "import Foundation",
        "",
        "public enum L10n {",
    ]

    for definition in definitions.values():
        parameters = ", ".join(
            f"{parameter.swift_name}: {parameter.kind.swift_type}"
            for parameter in definition.parameters
        )
        default_value = swift_localization_value(definition.default_value, definition)
        lines.extend([
            f"    public static func {definition.swift_name}({parameters}) -> String {{",
            "        String(localized: LocalizedStringResource(",
            f'            "{swift_escape(definition.key)}",',
            f'            defaultValue: "{default_value}",',
            '            table: "Localizable",',
            "            bundle: .atURL(AirBundle.bundleURL)",
            "        ))",
            "    }",
            "",
        ])

    lines.append("}")
    lines.append("")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")

def main():
    ap = argparse.ArgumentParser(description="Build .xcstrings from JSON or YAML locale files.")
    ap.add_argument("--input-dir", default="../../../../../src/i18n", help="Directory with *.json, *.yaml, or *.yml files")
    ap.add_argument("--source-locale", default="en", help="Source language code")
    ap.add_argument("--output", default="../../SubModules/WalletResources/Resources/Strings/Localizable.xcstrings", help="Output .xcstrings path")
    ap.add_argument("--swift-output", default="../../SubModules/WalletContext/Localization/GeneratedLocalizations.swift", help="Output path for the typed Swift localization interface")
    ap.add_argument("--push-output", default="../../../App/App/Resources/Localizable.xcstrings", help="Output .xcstrings path for main app bundle keys")
    ap.add_argument("--widget-output", default="../../../App/AirWidget/Localizable.xcstrings", help="Output .xcstrings path for the widget extension bundle")
    ap.add_argument("--push-prefix", default="push_", help="Localization key prefix for push catalog")
    args = ap.parse_args()

    input_dir = resolve_relative_to_script(args.input_dir)
    output_path = resolve_relative_to_script(args.output)
    swift_output_path = resolve_relative_to_script(args.swift_output)
    push_output_path = resolve_relative_to_script(args.push_output)
    widget_output_path = resolve_relative_to_script(args.widget_output)

    if not input_dir.exists():
        raise SystemExit(f"Input directory '{input_dir}' does not exist.")

    # Look for both JSON and YAML files
    json_files = list(input_dir.glob("*.json"))
    yaml_files = list(input_dir.glob("*.yaml"))
    yml_files = list(input_dir.glob("*.yml"))

    all_files = json_files + yaml_files + yml_files
    
    if not all_files:
        raise SystemExit("No JSON or YAML files found.")
    
    # Group files by normalized locale name (e.g., 'en' from 'en.yaml' and 'en.json')
    locale_files: dict[str, list[Path]] = {}
    for file_path in all_files:
        filename = file_path.name
        normalized_locale = normalize_locale_name(filename)
        if normalized_locale in locale_files:
            locale_files[normalized_locale].append(file_path)
        else:
            locale_files[normalized_locale] = [file_path]
    
    # Check if source locale has any files
    source_locale_files = []
    for locale_name, files in locale_files.items():
        if locale_name.lower() == args.source_locale.lower():
            source_locale_files = files
            break
    
    if not source_locale_files:
        raise SystemExit(f"No files found for source locale '{args.source_locale}'")
    
    # YAML is the source of truth. JSON files are accepted only when no YAML file exists for a locale.
    per_locale = {}
    selected_source_files = []
    for locale_name, files in locale_files.items():
        merged_data = {}
        yaml_sources = [file_path for file_path in files if file_path.suffix.lower() in (".yaml", ".yml")]
        selected_files = yaml_sources or files
        if locale_name.lower() == args.source_locale.lower():
            selected_source_files = selected_files
        for file_path in sorted(selected_files):  # Sort files for deterministic merging
            try:
                file_data = load_file(file_path)
                merged_data.update(file_data)
                print(f"Loaded {len(file_data)} keys from {file_path.name} for locale '{locale_name}'")
            except Exception as e:
                print(f"Warning: Failed to load {file_path}: {e}")
                continue
        per_locale[locale_name] = merged_data
    
    # Get the source locale data (merged from all its files)
    src_map = per_locale.get(args.source_locale.lower(), {})
    if not src_map:
        raise SystemExit(f"No data loaded for source locale '{args.source_locale}'")

    try:
        definitions = build_entry_definitions(src_map)
    except ValueError as error:
        raise SystemExit(f"Invalid source localizations: {error}") from error
    
    # Get all unique locales
    locales = list(per_locale.keys())
    # Ensure source locale is first
    if args.source_locale.lower() in locales:
        locales.remove(args.source_locale.lower())
        locales.insert(0, args.source_locale.lower())

    try:
        strings = build_strings_map(
            per_locale=per_locale,
            source_locale=args.source_locale,
            locales=locales,
            definitions=definitions,
        )
    except ValueError as error:
        raise SystemExit(f"Invalid localizations: {error}") from error
    widget_strings = with_extraction_state(strings, "extracted")
    write_catalog(output_path=output_path, source_locale=args.source_locale, strings=strings)
    write_catalog(output_path=widget_output_path, source_locale=args.source_locale, strings=widget_strings)
    write_swift_interface(output_path=swift_output_path, definitions=definitions)

    try:
        main_app_strings = build_strings_map(
            per_locale=per_locale,
            source_locale=args.source_locale,
            locales=locales,
            definitions=definitions,
            key_predicate=lambda key: str(key).startswith(args.push_prefix) or key in MAIN_APP_LOCALIZATION_KEYS,
        )
    except ValueError as error:
        raise SystemExit(f"Invalid localizations: {error}") from error
    write_catalog(output_path=push_output_path, source_locale=args.source_locale, strings=main_app_strings)

    print(f"Wrote {output_path} with {len(strings)} entries across {len(locales)} locales.")
    print(f"Wrote {widget_output_path} with {len(strings)} entries across {len(locales)} locales.")
    print(f"Wrote {swift_output_path} with {len(definitions)} typed localization functions.")
    print(f"Wrote {push_output_path} with {len(main_app_strings)} main app entries across {len(locales)} locales.")
    print(f"Source locale '{args.source_locale}' had {len(selected_source_files)} selected input files.")
    print()

if __name__ == "__main__":
    main()

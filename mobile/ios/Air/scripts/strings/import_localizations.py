#!/usr/bin/env python3
import argparse
import json
import os
import re
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

def replace_named_placeholders(key: str, text: str, mapping: dict | None, type_spec: str) -> tuple[str, dict]:
    if mapping is None:
        mapping = {}
    def repl(m):
        name = m.group(1)
        if name not in mapping:
            mapping[name] = len(mapping) + 1
        index = mapping[name]

        # Hotfixes for specific type specifications
        applied_type_spec = str(type_spec)
        if 'expires_in' in key:
            applied_type_spec = "lld"
        elif '$domains_expire' in key and name == 'days':
            applied_type_spec = "@"
        return f"%{index}${applied_type_spec}"
    replaced = re.sub(r"%([a-zA-Z0-9_]+)%", repl, text)
    return replaced, mapping

def is_plural_block(v) -> bool:
    return isinstance(v, dict) and any(k in v for k in PLURAL_KEYS.keys())

def build_nonplural_unit(key: str, text: str):
    s = normalize_value(text)
    replaced, _ = replace_named_placeholders(key, s, mapping=None, type_spec="@")
    return {
        "stringUnit": {
            "state": "translated",
            "value": replaced,
        }
    }

def build_plural_unit(key: str, forms: dict):
    variations = {}
    mapping = {}
    plural_keys_order = ["zeroValue","oneValue","twoValue","fewValue","manyValue","otherValue"]
    for yaml_key in plural_keys_order:
        if yaml_key in forms and forms[yaml_key] is not None:
            v = normalize_value(forms[yaml_key])
            replaced, mapping = replace_named_placeholders(key, v, mapping=mapping, type_spec="lld")
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

def normalize_locale_name(filename: str) -> str:
    """Normalize locale name by removing common prefixes like 'air_'"""
    name = os.path.splitext(filename)[0]
    if name.startswith('air_'):
        name = name[4:]  # Remove 'air_' prefix
    return name


def build_strings_map(per_locale: dict, source_locale: str, locales: list[str], key_predicate=None) -> dict:
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
            unit = build_plural_unit(key, v) if is_plural_block(v) else build_nonplural_unit(key, v)
            merge_localization_bucket(bucket, loc, unit)

        if "localizations" in bucket:
            strings[key] = bucket

    return dict(sorted(strings.items(), key=lambda x: str(x[0])))


def write_catalog(output_path: Path, source_locale: str, strings: dict):
    catalog = {
        "sourceLanguage": source_locale,
        "version": "1.0",
        "strings": strings,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

def main():
    ap = argparse.ArgumentParser(description="Build .xcstrings from JSON or YAML locale files.")
    ap.add_argument("--input-dir", default="../../../../../src/i18n", help="Directory with *.json, *.yaml, or *.yml files")
    ap.add_argument("--source-locale", default="en", help="Source language code")
    ap.add_argument("--output", default="../../SubModules/WalletContext/Resources/Strings/Localizable.xcstrings", help="Output .xcstrings path")
    ap.add_argument("--push-output", default="../../../App/App/Resources/Localizable.xcstrings", help="Output .xcstrings path for push* keys in main app bundle")
    ap.add_argument("--push-prefix", default="push_", help="Localization key prefix for push catalog")
    args = ap.parse_args()

    input_dir = resolve_relative_to_script(args.input_dir)
    output_path = resolve_relative_to_script(args.output)
    push_output_path = resolve_relative_to_script(args.push_output)

    if not input_dir.exists():
        raise SystemExit(f"Input directory '{input_dir}' does not exist.")

    # Look for both JSON and YAML files
    json_files = list(input_dir.glob("*.json"))
    yaml_files = list(input_dir.glob("*.yaml"))
    yml_files = list(input_dir.glob("*.yml"))

    # Also look in the air subdirectory
    air_dir = input_dir / "air"
    if air_dir.exists():
        air_json_files = list(air_dir.glob("*.json"))
        air_yaml_files = list(air_dir.glob("*.yaml"))
        air_yml_files = list(air_dir.glob("*.yml"))
        json_files.extend(air_json_files)
        yaml_files.extend(air_yaml_files)
        yml_files.extend(air_yml_files)

    all_files = json_files + yaml_files + yml_files
    
    if not all_files:
        raise SystemExit("No JSON or YAML files found.")
    
    # Group files by normalized locale name (e.g., 'en' from 'en.yaml' and 'air_en.json')
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
    
    # Load and merge all files for each locale
    per_locale = {}
    for locale_name, files in locale_files.items():
        merged_data = {}
        for file_path in sorted(files):  # Sort files for deterministic merging
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
    
    # Get all unique locales
    locales = list(per_locale.keys())
    # Ensure source locale is first
    if args.source_locale.lower() in locales:
        locales.remove(args.source_locale.lower())
        locales.insert(0, args.source_locale.lower())

    strings = build_strings_map(
        per_locale=per_locale,
        source_locale=args.source_locale,
        locales=locales,
    )
    write_catalog(output_path=output_path, source_locale=args.source_locale, strings=strings)

    push_strings = build_strings_map(
        per_locale=per_locale,
        source_locale=args.source_locale,
        locales=locales,
        key_predicate=lambda key: str(key).startswith(args.push_prefix),
    )
    write_catalog(output_path=push_output_path, source_locale=args.source_locale, strings=push_strings)

    print(f"Wrote {output_path} with {len(strings)} entries across {len(locales)} locales.")
    print(f"Wrote {push_output_path} with {len(push_strings)} push entries across {len(locales)} locales.")
    print(f"Source locale '{args.source_locale}' had {len(source_locale_files)} input files.")
    print()

if __name__ == "__main__":
    main()

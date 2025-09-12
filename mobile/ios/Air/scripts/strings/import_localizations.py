#!/usr/bin/env python3
import argparse
import json
import os
from glob import glob

import yaml  # pip install pyyaml

import re

PLURAL_KEYS = {
    "zeroValue": "zero",
    "oneValue": "one",
    "twoValue": "two",
    "fewValue": "few",
    "manyValue": "many",
    "otherValue": "other",
}

def load_yaml(path: str):
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data or {}

def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data or {}

def load_file(path: str):
    if path.endswith(".yaml") or path.endswith(".yml"):
        return load_yaml(path)
    elif path.endswith(".json"):
        return load_json(path)
    else:
        raise ValueError(f"Unsupported file extension: {os.path.splitext(path)[1]}. Only .json, .yaml, and .yml are supported.")

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

    if "other" not in variations:
        flat = " ".join(f"[{k}] {vv['stringUnit']['value']}" for k, vv in variations.items())
        return {"stringUnit": {"state": "translated", "value": flat}}

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

def main():
    ap = argparse.ArgumentParser(description="Build .xcstrings from JSON or YAML locale files.")
    ap.add_argument("--input-dir", default="../../../src/i18n", help="Directory with *.json, *.yaml, or *.yml files")
    ap.add_argument("--source-locale", default="en", help="Source language code")
    ap.add_argument("--output", default="./SubModules/WalletContext/Resources/Strings/Localizable.xcstrings", help="Output .xcstrings path")
    args = ap.parse_args()

    # Look for both JSON and YAML files
    json_files = glob(os.path.join(args.input_dir, "*.json"))
    yaml_files = glob(os.path.join(args.input_dir, "*.yaml"))
    yml_files = glob(os.path.join(args.input_dir, "*.yml"))

    # Also look in the air subdirectory
    air_dir = os.path.join(args.input_dir, "air")
    if os.path.exists(air_dir):
        air_json_files = glob(os.path.join(air_dir, "*.json"))
        air_yaml_files = glob(os.path.join(air_dir, "*.yaml"))
        air_yml_files = glob(os.path.join(air_dir, "*.yml"))
        json_files.extend(air_json_files)
        yaml_files.extend(air_yaml_files)
        yml_files.extend(air_yml_files)

    all_files = json_files + yaml_files + yml_files
    
    if not all_files:
        raise SystemExit("No JSON or YAML files found.")
    
    # Group files by normalized locale name (e.g., 'en' from 'en.yaml' and 'air_en.json')
    locale_files = {}
    for file_path in all_files:
        filename = os.path.basename(file_path)
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
                print(f"Loaded {len(file_data)} keys from {os.path.basename(file_path)} for locale '{locale_name}'")
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

    strings = {}

    for key, src_val in (src_map or {}).items():
        bucket = {}
        # Ensure source locale is first, then other language entries in deterministic alphabetical order for stable diffs
        for loc in [args.source_locale.lower()] + sorted([l for l in locales if l != args.source_locale.lower()], key=lambda x: str(x).lower()):
            loc_map = per_locale.get(loc, {})
            if key not in loc_map:
                continue
            v = loc_map[key]
            unit = build_plural_unit(key, v) if is_plural_block(v) else build_nonplural_unit(key, v)
            merge_localization_bucket(bucket, loc, unit)

        if "localizations" in bucket:
            strings[key] = bucket

    catalog = {
        "sourceLanguage": args.source_locale,
        "version": "1.0",
        "strings": dict(sorted(strings.items(), key=lambda x: str(x[0]))),
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    print(f"Wrote {args.output} with {len(strings)} entries across {len(locales)} locales.")
    print(f"Source locale '{args.source_locale}' had {len(source_locale_files)} input files.")

if __name__ == "__main__":
    main()

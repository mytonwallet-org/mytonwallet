#!/usr/bin/env python3
"""
Localization Completeness Checker

This script detects missing keys from other localizations compared to the base English localization,
and finds extraneous keys that exist in other localizations but not in the base.

IMPORTANT: This script only checks for actual keys, not plural form variations (otherValue, manyValue, etc.)
since plural forms are language-dependent and may differ between languages.

Usage:
    python check_localization_completeness.py --base en.yaml --compare ru.yaml
    python check_localization_completeness.py --base /path/to/base.yaml --compare /path/to/compare.yaml --verbose

The script will:
1. Load the base (English) localization file
2. Load the comparison localization file
3. Compare them to find missing keys in the comparison file (ignoring plural variations)
4. Find extraneous keys in the comparison file (ignoring plural variations)
5. Print a summary report

Exit codes:
    0 - No issues found (localization is complete)
    1 - Issues found (missing or extraneous keys)

Examples:
    # Check Russian localization against English base
    python check_localization_completeness.py --base /path/to/en.yaml --compare /path/to/ru.yaml

    # Check with verbose output
    python check_localization_completeness.py --base /path/to/en.yaml --compare /path/to/ru.yaml --verbose

Output format:
    MISSING KEYS IN ru.yaml:
    - missing_key_1
    - missing_key_2

    EXTRANEOUS KEYS IN ru.yaml:
    - extra_key_1
    - extra_key_2

Note: Plural form variations (otherValue, manyValue, fewValue, etc.) are not counted as separate keys
since they are language-dependent and expected to vary between languages.
"""

import argparse
import os
import yaml
from typing import Dict, Set, Any


def load_yaml_file(file_path: str) -> Dict[str, Any]:
    """Load YAML file and return its contents as a dictionary."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
            return data if data is not None else {}
    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.")
        return {}
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file '{file_path}': {e}")
        return {}


def flatten_keys(data: Dict[str, Any], prefix: str = "") -> Set[str]:
    """
    Recursively flatten nested dictionary keys into a set of dot-separated keys.
    For plural forms, only includes the parent key, not individual plural variations.
    """
    keys = set()

    for key, value in data.items():
        full_key = f"{prefix}.{key}" if prefix else key

        if isinstance(value, dict):
            # Check if this is a plural block (contains plural form keys)
            plural_keys = {"zeroValue", "oneValue", "twoValue", "fewValue", "manyValue", "otherValue"}
            if any(pk in value for pk in plural_keys):
                # This is a plural block - only add the parent key, don't recurse into plural forms
                keys.add(full_key)
            else:
                # This is a regular nested dictionary - recurse normally
                keys.add(full_key)
                nested_keys = flatten_keys(value, full_key)
                keys.update(nested_keys)
        else:
            keys.add(full_key)

    return keys


def get_missing_keys(base_keys: Set[str], compare_keys: Set[str]) -> Set[str]:
    """Find keys that exist in base but are missing from comparison localization."""
    return base_keys - compare_keys


def get_extraneous_keys(base_keys: Set[str], compare_keys: Set[str]) -> Set[str]:
    """Find keys that exist in comparison localization but not in base."""
    return compare_keys - base_keys


def print_results(missing_keys: Set[str], extraneous_keys: Set[str], compare_file: str):
    """Print the results in a formatted way."""
    print(f"\n=== LOCALIZATION COMPLETENESS CHECK ===")
    print(f"Comparing with base: {compare_file}")
    print()

    if missing_keys:
        print(f"❌ MISSING KEYS IN {os.path.basename(compare_file)}:")
        for key in sorted(missing_keys):
            print(f"  - {key}")
        print(f"\nTotal missing keys: {len(missing_keys)}")
    else:
        print(f"✅ NO MISSING KEYS found in {os.path.basename(compare_file)}")

    print()

    if extraneous_keys:
        print(f"⚠️  EXTRANEOUS KEYS IN {os.path.basename(compare_file)}:")
        for key in sorted(extraneous_keys):
            print(f"  - {key}")
        print(f"\nTotal extraneous keys: {len(extraneous_keys)}")
    else:
        print(f"✅ NO EXTRANEOUS KEYS found in {os.path.basename(compare_file)}")

    print()

    if not missing_keys and not extraneous_keys:
        print("🎉 Localization is complete and clean!")


def main():
    parser = argparse.ArgumentParser(
        description="Check localization completeness by comparing with base English localization"
    )
    parser.add_argument(
        "--base",
        required=True,
        help="Path to the base (English) localization file"
    )
    parser.add_argument(
        "--compare",
        required=True,
        help="Path to the localization file to compare against the base"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed information about the comparison"
    )

    args = parser.parse_args()

    # Load the localization files
    print(f"Loading base file: {args.base}")
    base_data = load_yaml_file(args.base)

    print(f"Loading comparison file: {args.compare}")
    compare_data = load_yaml_file(args.compare)

    if not base_data:
        print("Error: Base localization file is empty or could not be loaded.")
        return 1

    if not compare_data:
        print("Error: Comparison localization file is empty or could not be loaded.")
        return 1

    # Flatten keys for comparison
    base_keys = flatten_keys(base_data)
    compare_keys = flatten_keys(compare_data)

    if args.verbose:
        print(f"\nBase file contains {len(base_keys)} keys")
        print(f"Comparison file contains {len(compare_keys)} keys")
        print(f"Common keys: {len(base_keys & compare_keys)}")

    # Find missing and extraneous keys
    missing_keys = get_missing_keys(base_keys, compare_keys)
    extraneous_keys = get_extraneous_keys(base_keys, compare_keys)

    # Print results
    print_results(missing_keys, extraneous_keys, args.compare)

    # Return non-zero exit code if there are issues
    if missing_keys or extraneous_keys:
        return 1

    return 0


if __name__ == "__main__":
    exit(main())

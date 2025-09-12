#!/usr/bin/env python3
"""
Swift Localization Key Scanner

This script scans all Swift files in the iOS subfolder for localization keys used in code
and finds which keys are NOT present in the localization YAML files.

It searches for patterns like: lang("key_name"
Note: No closing parenthesis as per iOS usage pattern.

Usage:
    python find_unused_localization_keys.py --ios-path ../../../..
    python find_unused_localization_keys.py --ios-path ../../../.. --verbose

The script will:
1. Scan all Swift files in the iOS folder
2. Extract localization keys from lang(" patterns with source file tracking
3. Check against src/i18n/en.yaml and src/i18n/air/en.yaml
4. Report keys used in code but missing from localization files
5. Show source file names in parentheses for each missing key

Output format:
    - 'Try again' (LedgerAddAccountView.swift, LedgerSignView.swift)
    - 'Add Stake' (AddStakeVC.swift, EarnHeaderCell.swift)

Exit codes:
    0 - All keys found in localization files
    1 - Some keys missing from localization files
"""

import argparse
import os
import re
import yaml
from typing import Dict, Set, List, Any


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


def find_swift_files(ios_path: str) -> List[str]:
    """Find all Swift files in the iOS directory."""
    swift_files = []
    for root, dirs, files in os.walk(ios_path):
        for file in files:
            if file.endswith('.swift'):
                swift_files.append(os.path.join(root, file))
    return swift_files


def extract_localization_keys_from_file(file_path: str) -> Set[str]:
    """Extract localization keys from a Swift file using regex pattern lang("key"."""
    keys = set()
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Pattern to match lang("key_name" - note no closing paren
        # This captures the key inside the quotes
        pattern = r'lang\("([^"]+)"'
        matches = re.findall(pattern, content)

        for match in matches:
            keys.add(match)

    except Exception as e:
        print(f"Warning: Could not read file {file_path}: {e}")

    return keys


def extract_all_keys_from_swift(ios_path: str) -> Dict[str, Set[str]]:
    """Extract all localization keys from all Swift files, tracking which file each key came from."""
    all_keys = {}
    swift_files = find_swift_files(ios_path)

    print(f"Scanning {len(swift_files)} Swift files...")

    for file_path in swift_files:
        keys = extract_localization_keys_from_file(file_path)
        file_name = os.path.basename(file_path)

        for key in keys:
            if key in all_keys:
                all_keys[key].add(file_name)
            else:
                all_keys[key] = {file_name}

    return all_keys


def main():
    parser = argparse.ArgumentParser(
        description="Find localization keys used in Swift code but missing from YAML files"
    )
    parser.add_argument(
        "--ios-path",
        default="../../../..",
        help="Path to the iOS directory (default: ../../../..)"
    )
    parser.add_argument(
        "--main-i18n",
        default="src/i18n/en.yaml",
        help="Path to main i18n YAML file (default: src/i18n/en.yaml)"
    )
    parser.add_argument(
        "--air-i18n",
        default="src/i18n/air/en.yaml",
        help="Path to air i18n YAML file (default: src/i18n/air/en.yaml)"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed information"
    )

    args = parser.parse_args()

    # Convert relative paths to absolute paths
    ios_path = os.path.abspath(args.ios_path)
    main_i18n_path = os.path.join(ios_path, args.main_i18n)
    air_i18n_path = os.path.join(ios_path, args.air_i18n)

    if not os.path.exists(ios_path):
        print(f"Error: iOS path '{ios_path}' does not exist.")
        return 1

    print("🔍 Swift Localization Key Scanner")
    print("=================================")
    print()

    # Extract keys from Swift files
    print("📱 Extracting localization keys from Swift files...")
    swift_keys_dict = extract_all_keys_from_swift(ios_path)

    if not swift_keys_dict:
        print("❌ No localization keys found in Swift files.")
        return 0

    print(f"Found {len(swift_keys_dict)} unique localization keys in Swift code.")

    # Convert to set for easier comparison
    swift_keys = set(swift_keys_dict.keys())

    # Load localization files
    print("\n📂 Loading localization files...")
    main_i18n_data = load_yaml_file(main_i18n_path)
    air_i18n_data = load_yaml_file(air_i18n_path)

    if not main_i18n_data and not air_i18n_data:
        print("❌ No localization files found.")
        return 1

    # Flatten keys from localization files
    main_i18n_keys = flatten_keys(main_i18n_data) if main_i18n_data else set()
    air_i18n_keys = flatten_keys(air_i18n_data) if air_i18n_data else set()
    all_localized_keys = main_i18n_keys.union(air_i18n_keys)

    if args.verbose:
        print(f"\nMain i18n file ({main_i18n_path}): {len(main_i18n_keys)} keys")
        print(f"Air i18n file ({air_i18n_path}): {len(air_i18n_keys)} keys")
        print(f"Total unique localized keys: {len(all_localized_keys)}")
        print(f"Swift keys: {len(swift_keys)}")

        # Show some examples of keys with their files
        print(f"\n📋 Sample keys found in Swift files:")
        sample_keys = list(swift_keys_dict.keys())[:5]
        for key in sample_keys:
            files = sorted(list(swift_keys_dict[key]))
            print(f"  - '{key}' ({', '.join(files)})")

    # Find missing keys
    missing_keys = swift_keys - all_localized_keys

    print("\n=== LOCALIZATION KEY ANALYSIS ===")
    print()

    if missing_keys:
        print(f"❌ MISSING KEYS IN LOCALIZATION FILES:")
        print(f"   Found {len(missing_keys)} keys used in Swift code but missing from YAML files")
        print()

        for key in sorted(missing_keys):
            if key in swift_keys_dict:
                files = sorted(list(swift_keys_dict[key]))
                print(f"  - '{key}' ({', '.join(files)})")
            else:
                print(f"  - '{key}' (unknown file)")

        print(f"\nTotal missing keys: {len(missing_keys)}")

        # Show some examples of usage
        print(f"\n🔍 Usage examples...")
        print("(showing first 5 examples):")

        examples_shown = 0
        for swift_file in find_swift_files(ios_path):
            if examples_shown >= 5:
                break

            try:
                with open(swift_file, 'r', encoding='utf-8') as f:
                    lines = f.readlines()

                for line_num, line in enumerate(lines, 1):
                    for missing_key in missing_keys:
                        if f'lang("{missing_key}"' in line:
                            print(f"  📄 {os.path.basename(swift_file)}:{line_num}")
                            print(f"     {line.strip()}")
                            examples_shown += 1
                            if examples_shown >= 5:
                                break
                    if examples_shown >= 5:
                        break
            except:
                continue

        return 1
    else:
        print("✅ ALL LOCALIZATION KEYS FOUND")
        print("All keys used in Swift code are present in the localization files.")
        return 0


if __name__ == "__main__":
    exit(main())

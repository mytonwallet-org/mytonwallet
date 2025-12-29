#!/usr/bin/env python3
"""Remove Russian localization keys that are missing in the English source file."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, List

import yaml


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGLISH_PATH = "@en.yaml"
DEFAULT_RUSSIAN_PATH = "@ru.yaml"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Delete keys from a Russian localization YAML file when they are absent in the English source."
    )
    parser.add_argument(
        "--english",
        default=DEFAULT_ENGLISH_PATH,
        help="Path to the English YAML file (prefix with '@' to resolve from src/i18n).",
    )
    parser.add_argument(
        "--russian",
        default=DEFAULT_RUSSIAN_PATH,
        help="Path to the Russian YAML file (prefix with '@' to resolve from src/i18n).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the keys that would be removed without modifying the Russian file.",
    )
    parser.add_argument(
        "--print-keys",
        action="store_true",
        help="Print flattened keys detected in both English and Russian files.",
    )
    return parser.parse_args()


def resolve_localization_path(raw_path: str) -> Path:
    if raw_path.startswith("@"):
        relative = raw_path[1:]
        resolved = PROJECT_ROOT / "src/i18n" / relative
    else:
        candidate = Path(raw_path)
        resolved = candidate if candidate.is_absolute() else PROJECT_ROOT / candidate
    return resolved.resolve()


def flatten_keys(node: Any, prefix: str) -> List[str]:
    keys: List[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            next_prefix = f"{prefix}.{key}" if prefix else str(key)
            keys.extend(flatten_keys(value, next_prefix))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            next_prefix = f"{prefix}[{index}]"
            keys.extend(flatten_keys(item, next_prefix))
    elif prefix:
        keys.append(prefix)
    return keys


def prune_missing_entries(ru_node: Any, en_node: Any, prefix: str, removed: List[str]) -> bool:
    if isinstance(ru_node, dict):
        if not isinstance(en_node, dict):
            removed.extend(flatten_keys(ru_node, prefix))
            return True

        for key in list(ru_node.keys()):
            next_prefix = f"{prefix}.{key}" if prefix else str(key)
            if key not in en_node:
                value = ru_node[key]
                removed.extend(flatten_keys(value, next_prefix))
                del ru_node[key]
                continue

            value = ru_node[key]
            should_delete_child = prune_missing_entries(value, en_node[key], next_prefix, removed)
            if should_delete_child:
                removed.extend(flatten_keys(value, next_prefix))
                del ru_node[key]

        return len(ru_node) == 0

    if isinstance(ru_node, list):
        if not isinstance(en_node, list):
            removed.extend(flatten_keys(ru_node, prefix))
            return True

        # Remove trailing items that have no counterpart in the English list.
        for index in range(len(ru_node) - 1, len(en_node) - 1, -1):
            value = ru_node[index]
            removed.extend(flatten_keys(value, f"{prefix}[{index}]"))
            del ru_node[index]

        for index in range(len(ru_node) - 1, -1, -1):
            en_index_value = en_node[index] if index < len(en_node) else None
            value = ru_node[index]
            next_prefix = f"{prefix}[{index}]"
            should_delete_child = prune_missing_entries(value, en_index_value, next_prefix, removed)
            if should_delete_child:
                removed.extend(flatten_keys(value, next_prefix))
                del ru_node[index]

        return len(ru_node) == 0

    if en_node is None or isinstance(en_node, (dict, list)):
        return True

    return False


def load_yaml_data(path: Path) -> Any:
    content = path.read_text(encoding="utf-8")
    data = yaml.safe_load(content) or {}
    return data


def write_yaml_data(path: Path, data: Any) -> None:
    serialized = yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
    path.write_text(serialized, encoding="utf-8")


def main() -> None:
    args = parse_args()

    english_path = resolve_localization_path(args.english)
    russian_path = resolve_localization_path(args.russian)

    if not english_path.exists():
        raise FileNotFoundError(f"English YAML not found: {english_path}")
    if not russian_path.exists():
        raise FileNotFoundError(f"Russian YAML not found: {russian_path}")

    english_data = load_yaml_data(english_path)
    russian_data = load_yaml_data(russian_path)

    if not isinstance(english_data, dict):
        raise ValueError(f"Expected dictionary at root of {english_path}")
    if not isinstance(russian_data, dict):
        raise ValueError(f"Expected dictionary at root of {russian_path}")

    english_keys = sorted(set(flatten_keys(english_data, "")))
    russian_keys = sorted(set(flatten_keys(russian_data, "")))

    if args.print_keys or args.dry_run:
        print(f"English keys detected ({len(english_keys)}):")
        for key in english_keys:
            print(f"  - {key}")
        print(f"Russian keys detected ({len(russian_keys)}):")
        for key in russian_keys:
            print(f"  - {key}")

    removed: List[str] = []
    prune_missing_entries(russian_data, english_data, "", removed)

    unique_keys = sorted(set(removed))
    if args.dry_run:
        if unique_keys:
            print("Keys to remove:")
            for key in unique_keys:
                print(f"  - {key}")
        else:
            print("No keys to remove.")
        return

    if not unique_keys:
        print("Nothing to remove. Russian localization already matches English keys.")
        return

    write_yaml_data(russian_path, russian_data)
    print(f"Removed {len(unique_keys)} key(s) from {russian_path}:")
    for key in unique_keys:
        print(f"  - {key}")


if __name__ == "__main__":
    main()


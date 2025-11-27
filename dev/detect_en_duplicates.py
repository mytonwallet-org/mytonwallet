#!/usr/bin/env python3
"""Detect duplicate localization keys and optionally compare key sets between localization files."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List

import yaml
from yaml.nodes import MappingNode, Node, ScalarNode, SequenceNode


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGLISH_PATH = "@en.yaml"


@dataclass
class DuplicateEntry:
    key: str
    lines: List[int]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find keys that are declared multiple times in a localization YAML file."
    )
    parser.add_argument(
        "--file",
        default=DEFAULT_ENGLISH_PATH,
        help="Path to the YAML file to inspect (prefix with '@' to resolve from src/i18n).",
    )
    parser.add_argument(
        "--compare",
        help="Optional path to another YAML file to compare against (prefix with '@').",
    )
    parser.add_argument(
        "--compare-values",
        action="store_true",
        help="When comparing two files, also compare flattened values to find matches.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output duplicates as JSON for machine-readable consumption.",
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


def normalize_key(key_node: Node) -> str:
    if isinstance(key_node, ScalarNode):
        return str(key_node.value)
    return str(key_node)


def collect_duplicates(node: Node, parent_path: str, duplicates: List[DuplicateEntry]) -> None:
    if isinstance(node, MappingNode):
        occurrences: dict[str, List[int]] = {}
        for key_node, value_node in node.value:
            key = normalize_key(key_node)
            full_key = f"{parent_path}.{key}" if parent_path else key
            line = key_node.start_mark.line + 1 if key_node.start_mark else -1
            occurrences.setdefault(key, []).append(line)
            collect_duplicates(value_node, full_key, duplicates)

        for key, lines in occurrences.items():
            if len(lines) > 1:
                full_key = f"{parent_path}.{key}" if parent_path else key
                duplicates.append(DuplicateEntry(key=full_key, lines=lines))

    elif isinstance(node, SequenceNode):
        for index, child in enumerate(node.value):
            next_path = f"{parent_path}[{index}]" if parent_path else f"[{index}]"
            collect_duplicates(child, next_path, duplicates)


def collect_keys(node: Node, parent_path: str, keys: List[str]) -> None:
    if isinstance(node, MappingNode):
        for key_node, value_node in node.value:
            key = normalize_key(key_node)
            next_path = f"{parent_path}.{key}" if parent_path else key
            collect_keys(value_node, next_path, keys)
    elif isinstance(node, SequenceNode):
        for index, child in enumerate(node.value):
            next_path = f"{parent_path}[{index}]" if parent_path else f"[{index}]"
            collect_keys(child, next_path, keys)
    else:
        if parent_path:
            keys.append(parent_path)


def collect_unique_keys(root: Node | None) -> List[str]:
    if root is None:
        return []
    result: List[str] = []
    collect_keys(root, "", result)
    return sorted(set(result))


def flatten_data(data: Any, prefix: str = "") -> List[tuple[str, str]]:
    flattened: List[tuple[str, str]] = []
    if isinstance(data, dict):
        for key, value in data.items():
            next_prefix = f"{prefix}.{key}" if prefix else str(key)
            flattened.extend(flatten_data(value, next_prefix))
    elif isinstance(data, list):
        for index, item in enumerate(data):
            next_prefix = f"{prefix}[{index}]" if prefix else f"[{index}]"
            flattened.extend(flatten_data(item, next_prefix))
    else:
        if prefix:
            flattened.append((prefix, stringify_value(data)))
    return flattened


def stringify_value(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value).strip()


def group_values(pairs: List[tuple[str, str]]) -> dict[str, List[str]]:
    mapping: dict[str, List[str]] = {}
    for path, value in pairs:
        mapping.setdefault(value, []).append(path)
    for path_list in mapping.values():
        path_list.sort()
    return mapping


def format_value(value: str) -> str:
    displayed = value.replace("\n", "\\n")
    return displayed if displayed else "«empty»"


def detect_duplicates(yaml_path: Path) -> List[DuplicateEntry]:
    content = yaml_path.read_text(encoding="utf-8")
    root = yaml.compose(content, Loader=yaml.SafeLoader)
    if root is None:
        return []

    duplicates: List[DuplicateEntry] = []
    collect_duplicates(root, "", duplicates)
    duplicates.sort(key=lambda entry: entry.key)
    return duplicates


def print_duplicates(duplicates: List[DuplicateEntry], as_json: bool) -> None:
    if as_json:
        payload = [
            {"key": entry.key, "lines": entry.lines}
            for entry in duplicates
        ]
        print(json.dumps(payload, indent=2))
        return

    if not duplicates:
        print("No duplicate keys found.")
        return

    print(f"Found {len(duplicates)} duplicate key(s):")
    for entry in duplicates:
        formatted_lines = ", ".join(str(line) for line in entry.lines if line > 0)
        if not formatted_lines:
            formatted_lines = "unknown"
        print(f"  - {entry.key} (lines: {formatted_lines})")


def main() -> None:
    args = parse_args()
    target_path = resolve_localization_path(args.file)

    if not target_path.exists():
        raise FileNotFoundError(f"YAML file not found: {target_path}")

    if args.json and args.compare:
        raise ValueError("JSON output is not supported when comparing two files.")
    if args.compare_values and not args.compare:
        raise ValueError("--compare-values requires --compare.")

    duplicates = detect_duplicates(target_path)
    print_duplicates(duplicates, args.json)

    primary_content = target_path.read_text(encoding="utf-8")
    primary_root = yaml.compose(primary_content, Loader=yaml.SafeLoader)
    primary_data = yaml.safe_load(primary_content) or {}
    primary_keys = collect_unique_keys(primary_root)

    if args.compare:
        compare_path = resolve_localization_path(args.compare)
        if not compare_path.exists():
            raise FileNotFoundError(f"Comparison YAML file not found: {compare_path}")

        secondary_content = compare_path.read_text(encoding="utf-8")
        secondary_root = yaml.compose(secondary_content, Loader=yaml.SafeLoader)
        secondary_data = yaml.safe_load(secondary_content) or {}

        secondary_keys = collect_unique_keys(secondary_root)
        common_keys = sorted(set(primary_keys) & set(secondary_keys))

        print(f"\nKeys in {target_path} ({len(primary_keys)}):")
        for key in primary_keys:
            print(f"  - {key}")

        print(f"\nKeys in {compare_path} ({len(secondary_keys)}):")
        for key in secondary_keys:
            print(f"  - {key}")

        print(f"\nCommon keys ({len(common_keys)}):")
        for key in common_keys:
            print(f"  - {key}")

        if args.compare_values:
            primary_pairs = flatten_data(primary_data)
            secondary_pairs = flatten_data(secondary_data)

            primary_values = group_values(primary_pairs)
            secondary_values = group_values(secondary_pairs)
            common_values = sorted(set(primary_values) & set(secondary_values))

            print(f"\nValues in {target_path} ({len(primary_values)} unique):")
            for value, paths in sorted(primary_values.items(), key=lambda item: item[0]):
                print(f"  - {format_value(value)}")
                for path in paths:
                    print(f"      * {path}")

            print(f"\nValues in {compare_path} ({len(secondary_values)} unique):")
            for value, paths in sorted(secondary_values.items(), key=lambda item: item[0]):
                print(f"  - {format_value(value)}")
                for path in paths:
                    print(f"      * {path}")

            print(f"\nCommon values ({len(common_values)}):")
            for value in common_values:
                print(f"  - {format_value(value)}")
                print(f"    in {target_path}:")
                for path in primary_values[value]:
                    print(f"      * {path}")
                print(f"    in {compare_path}:")
                for path in secondary_values[value]:
                    print(f"      * {path}")

    sys.exit(1 if duplicates else 0)


if __name__ == "__main__":
    main()


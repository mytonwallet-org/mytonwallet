#!/usr/bin/env python3
"""Generate a usage table for Air localizations across iOS and Android codebases."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import yaml


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_YAML_PATH = PROJECT_ROOT / "src/i18n/air/en.yaml"
IOS_ROOT = PROJECT_ROOT / "mobile/ios"
ANDROID_ROOT = PROJECT_ROOT / "mobile/android"
DEFAULT_OUTPUT_PATH = PROJECT_ROOT / "dev" / "find_air_localizations_table.md"


@dataclass
class UsageMatch:
    path: Path
    line: int

    def format(self) -> str:
        return f"{self.path}:{self.line}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a table showing where Air localization keys are used in iOS and Android."
    )
    parser.add_argument(
        "--yaml",
        dest="yaml_path",
        default=str(DEFAULT_YAML_PATH),
        help="Path to the Air English localization YAML file.",
    )
    parser.add_argument(
        "--output",
        dest="output_path",
        default=str(DEFAULT_OUTPUT_PATH),
        help="Where to write the resulting Markdown table.",
    )
    parser.add_argument(
        "--ios-root",
        dest="ios_root",
        default=str(IOS_ROOT),
        help="Root directory to scan for iOS Swift files.",
    )
    parser.add_argument(
        "--android-root",
        dest="android_root",
        default=str(ANDROID_ROOT),
        help="Root directory to scan for Android Kotlin files.",
    )
    return parser.parse_args()


def flatten_localizations(data: Dict, prefix: str = "") -> List[Tuple[str, str]]:
    """Flatten nested localization dictionaries into dot-separated keys."""
    items: List[Tuple[str, str]] = []
    for key, value in data.items():
        next_prefix = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(value, dict):
            items.extend(flatten_localizations(value, next_prefix))
        elif isinstance(value, list):
            for index, item in enumerate(value):
                list_prefix = f"{next_prefix}[{index}]"
                if isinstance(item, dict):
                    items.extend(flatten_localizations(item, list_prefix))
                else:
                    items.append((list_prefix, stringify_value(item)))
        else:
            items.append((next_prefix, stringify_value(value)))
    return items


def stringify_value(value) -> str:
    return str(value).strip()


def find_matches(root: Path, pattern: re.Pattern, extension: str, label: str) -> List[UsageMatch]:
    matches: List[UsageMatch] = []
    files = sorted(root.rglob(f"*{extension}"))
    print(f"[{label}] Scanning {len(files)} *{extension} files with pattern {pattern.pattern!r}")
    for file_path in files:
        # print(f"[{label}] Reading {file_path}")
        try:
            content = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            content = file_path.read_text(encoding="utf-8", errors="ignore")
        file_matches = 0
        for match in pattern.finditer(content):
            line = content.count("\n", 0, match.start()) + 1
            matches.append(UsageMatch(path=file_path.relative_to(PROJECT_ROOT), line=line))
            file_matches += 1
        if file_matches > 0:
            print(f"[{label}] Found {file_matches} matches in {file_path}")
    return matches


def escape_markdown(value: str) -> str:
    escaped = value.replace("|", "\\|").replace("\n", "<br>")
    return escaped or "—"


def format_matches(matches: Iterable[UsageMatch]) -> str:
    formatted = "<br>".join(match.format() for match in matches)
    return formatted or "—"


def build_ios_pattern(key: str) -> re.Pattern:
    escaped_key = re.escape(key)
    return re.compile(rf'lang\("{escaped_key}"', re.MULTILINE)


def build_android_pattern(key: str) -> re.Pattern:
    escaped_key = re.escape(key)
    return re.compile(rf'LocaleController[\s\S]{{0,200}}?"{escaped_key}"', re.MULTILINE)


def load_localizations(yaml_path: Path) -> List[Tuple[str, str]]:
    data = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Expected a dictionary at the top level of {yaml_path}")
    return flatten_localizations(data)


def create_table(rows: List[Tuple[str, str, str, str]]) -> str:
    header = "| Localization Key | English Value | iOS Usage | Android Usage |\n"
    separator = "| --- | --- | --- | --- |\n"
    body_lines = [
        f"| {escape_markdown(key)} | {escape_markdown(value)} | {escape_markdown(ios)} | {escape_markdown(android)} |"
        for key, value, ios, android in rows
    ]
    return header + separator + "\n".join(body_lines) + "\n"


def main() -> None:
    args = parse_args()

    yaml_path = Path(args.yaml_path)
    ios_root = Path(args.ios_root)
    android_root = Path(args.android_root)
    output_path = Path(args.output_path)

    localizations = load_localizations(yaml_path)
    print(f"Loaded {len(localizations)} localization keys from {yaml_path}")
    print(f"iOS root: {ios_root}")
    print(f"Android root: {android_root}")

    table_rows: List[Tuple[str, str, str, str]] = []
    for key, value in localizations:
        print(f"Processing key: {key}")
        ios_matches = find_matches(ios_root, build_ios_pattern(key), ".swift", "iOS")
        android_matches = find_matches(android_root, build_android_pattern(key), ".kt", "Android")

        table_rows.append(
            (
                key,
                value,
                format_matches(ios_matches),
                format_matches(android_matches),
            )
        )

    table_content = create_table(table_rows)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(table_content, encoding="utf-8")
    print(f"Wrote localization usage table to {output_path}")


if __name__ == "__main__":
    main()


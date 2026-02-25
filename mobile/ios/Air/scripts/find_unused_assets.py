#!/usr/bin/env python3
"""
Find unused asset names from an .xcassets catalog.

Default usage:
    python3 mobile/ios/Air/scripts/find_unused_assets.py

Custom paths:
    python3 mobile/ios/Air/scripts/find_unused_assets.py \
        --assets mobile/ios/Air/SubModules/WalletContext/Resources/Assets.xcassets \
        --scan-root mobile/ios/Air/SubModules \
        --scan-root mobile/ios/Air/App
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Iterable


DEFAULT_ASSET_TYPES = ("imageset", "colorset", "symbolset", "dataset")
DEFAULT_FILE_EXTENSIONS = (
    "swift",
    "m",
    "mm",
    "h",
    "xib",
    "storyboard",
    "plist",
    "json",
    "yaml",
    "yml",
    "strings",
    "stringsdict",
    "md",
)
DEFAULT_EXCLUDED_DIRS = {
    ".git",
    ".build",
    "build",
    "DerivedData",
    "Pods",
    "Carthage",
    "node_modules",
    ".swiftpm",
}


def normalize_exts(raw_exts: Iterable[str]) -> set[str]:
    return {f".{ext.lstrip('.').lower()}" for ext in raw_exts if ext.strip()}


def normalize_asset_types(raw_types: Iterable[str]) -> set[str]:
    return {f".{kind.lstrip('.').lower()}" for kind in raw_types if kind.strip()}


def collect_asset_names(assets_path: Path, asset_types: set[str]) -> dict[str, Path]:
    assets: dict[str, Path] = {}
    for root, dirs, _ in os.walk(assets_path):
        for dirname in dirs:
            dir_path = Path(root) / dirname
            suffix = dir_path.suffix.lower()
            if suffix in asset_types:
                asset_name = dir_path.stem
                if asset_name in assets:
                    previous = assets[asset_name]
                    raise ValueError(
                        f"Duplicate asset name '{asset_name}' found in both "
                        f"'{previous}' and '{dir_path}'"
                    )
                assets[asset_name] = dir_path
    return assets


def iter_scan_files(
    scan_roots: list[Path],
    allowed_extensions: set[str],
    excluded_dir_names: set[str],
) -> Iterable[Path]:
    for root in scan_roots:
        for current_root, dirs, files in os.walk(root):
            dirs[:] = [
                d for d in dirs
                if d not in excluded_dir_names and not d.endswith(".xcassets")
            ]

            for filename in files:
                file_path = Path(current_root) / filename
                if file_path.suffix.lower() in allowed_extensions:
                    yield file_path


STRING_LITERAL_RE = re.compile(
    r'"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\''
)
FORMAT_SPECIFIER_RE = re.compile(
    r"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(?:hh|h|ll|l|L|z|j|t)?[@dDuUxXoOfFeEgGcCsSpaA]"
)
CODE_FILE_EXTENSIONS = {".swift", ".m", ".mm"}


def extract_string_literals(content: str) -> set[str]:
    values: set[str] = set()
    for match in STRING_LITERAL_RE.finditer(content):
        value = match.group(1) if match.group(1) is not None else match.group(2)
        if value:
            values.add(value)
    return values


def interpolation_template_to_regex(template: str) -> tuple[re.Pattern[str], int] | None:
    if "\\(" not in template:
        return None

    parts: list[str] = []
    i = 0
    length = len(template)
    static_chars = 0

    while i < length:
        if i + 1 < length and template[i] == "\\" and template[i + 1] == "(":
            parts.append(".*")
            i += 2
            depth = 1
            while i < length and depth > 0:
                char = template[i]
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                i += 1
            continue

        parts.append(re.escape(template[i]))
        static_chars += 1
        i += 1

    if ".*" not in parts or static_chars < 2:
        return None
    return re.compile("^" + "".join(parts) + "$"), static_chars


def format_template_to_regex(template: str) -> tuple[re.Pattern[str], int] | None:
    if "%" not in template:
        return None

    matches = list(FORMAT_SPECIFIER_RE.finditer(template))
    if not matches:
        return None

    parts: list[str] = []
    cursor = 0
    static_chars = 0
    for match in matches:
        start, end = match.span()
        static_fragment = template[cursor:start]
        parts.append(re.escape(static_fragment))
        static_chars += len(static_fragment)
        parts.append(".*")
        cursor = end
    static_fragment = template[cursor:]
    parts.append(re.escape(static_fragment))
    static_chars += len(static_fragment)

    if static_chars < 2:
        return None

    return re.compile("^" + "".join(parts) + "$"), static_chars


def maybe_dynamic_pattern(template: str) -> re.Pattern[str] | None:
    interpolation_result = interpolation_template_to_regex(template)
    if interpolation_result is not None:
        return interpolation_result[0]

    format_result = format_template_to_regex(template)
    if format_result is not None:
        return format_result[0]
    return None


def find_asset_usage(
    assets: dict[str, Path],
    scan_files: Iterable[Path],
) -> tuple[dict[str, set[Path]], dict[str, set[Path]], int]:
    exact_usage: dict[str, set[Path]] = {name: set() for name in assets}
    possible_usage: dict[str, set[Path]] = {name: set() for name in assets}
    scanned_files = 0
    asset_names = set(assets.keys())
    ordered_asset_names = sorted(asset_names)

    for file_path in scan_files:
        scanned_files += 1
        try:
            content = file_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        literals = extract_string_literals(content)
        for literal in literals:
            if literal in asset_names:
                exact_usage[literal].add(file_path)
                continue

            if file_path.suffix.lower() not in CODE_FILE_EXTENSIONS:
                continue

            pattern = maybe_dynamic_pattern(literal)
            if pattern is None:
                continue

            for asset_name in ordered_asset_names:
                if pattern.match(asset_name):
                    possible_usage[asset_name].add(file_path)

    return exact_usage, possible_usage, scanned_files


def build_parser() -> argparse.ArgumentParser:
    script_dir = Path(__file__).resolve().parent
    air_root = script_dir.parent
    default_assets = air_root / "SubModules/WalletContext/Resources/Assets.xcassets"

    parser = argparse.ArgumentParser(description="Find unused names in an .xcassets catalog.")
    parser.add_argument(
        "--assets",
        type=Path,
        default=default_assets,
        help=f"Path to the .xcassets catalog (default: {default_assets})",
    )
    parser.add_argument(
        "--scan-root",
        action="append",
        type=Path,
        default=None,
        help="Directory to scan for references. Repeat to scan multiple roots. "
             "Default: mobile/ios/Air.",
    )
    parser.add_argument(
        "--asset-type",
        action="append",
        default=list(DEFAULT_ASSET_TYPES),
        help="Asset set directory type to include (imageset, colorset, symbolset, dataset). "
             "Repeatable.",
    )
    parser.add_argument(
        "--ext",
        action="append",
        default=list(DEFAULT_FILE_EXTENSIONS),
        help="File extension to scan (without dot). Repeatable.",
    )
    parser.add_argument(
        "--exclude-dir",
        action="append",
        default=[],
        help="Directory name to exclude from scanning. Repeatable.",
    )
    parser.add_argument(
        "--show-used",
        action="store_true",
        help="Also print used assets and where they were found.",
    )
    parser.add_argument(
        "--with-paths",
        action="store_true",
        help="Print asset catalog paths next to unused asset names.",
    )
    parser.add_argument(
        "--fail-on-unused",
        action="store_true",
        help="Exit with code 1 when unused assets are found.",
    )
    parser.add_argument(
        "--strict-literals",
        action="store_true",
        help="Disable dynamic template matching and use exact string literals only.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    assets_path = args.assets.resolve()
    if not assets_path.exists() or not assets_path.is_dir():
        print(f"Error: assets catalog not found: {assets_path}", file=sys.stderr)
        return 2

    default_scan_root = Path(__file__).resolve().parent.parent
    scan_roots = args.scan_root or [default_scan_root]
    scan_roots = [path.resolve() for path in scan_roots]
    missing_roots = [path for path in scan_roots if not path.exists() or not path.is_dir()]
    if missing_roots:
        for missing in missing_roots:
            print(f"Error: scan root not found: {missing}", file=sys.stderr)
        return 2

    asset_types = normalize_asset_types(args.asset_type)
    extensions = normalize_exts(args.ext)
    excluded_dirs = set(DEFAULT_EXCLUDED_DIRS) | set(args.exclude_dir)

    try:
        assets = collect_asset_names(assets_path, asset_types)
    except ValueError as err:
        print(f"Error: {err}", file=sys.stderr)
        return 2

    if not assets:
        print("No assets found for selected types.")
        return 0

    exact_usage, possible_usage, scanned_files = find_asset_usage(
        assets=assets,
        scan_files=iter_scan_files(scan_roots, extensions, excluded_dirs),
    )

    used_assets = sorted([name for name, refs in exact_usage.items() if refs])

    if args.strict_literals:
        maybe_used_assets: list[str] = []
        unused_assets = sorted([name for name, refs in exact_usage.items() if not refs])
    else:
        maybe_used_assets = sorted([
            name for name, refs in possible_usage.items()
            if not exact_usage[name] and refs
        ])
        unused_assets = sorted([
            name for name in assets
            if not exact_usage[name] and not possible_usage[name]
        ])

    print("Asset Usage Report")
    print("==================")
    print(f"Catalog:      {assets_path}")
    print(f"Scan roots:   {', '.join(str(root) for root in scan_roots)}")
    print(f"Asset types:  {', '.join(sorted(t.lstrip('.') for t in asset_types))}")
    print(f"Extensions:   {', '.join(sorted(ext.lstrip('.') for ext in extensions))}")
    print(f"Scanned files:{scanned_files}")
    print(f"Total assets: {len(assets)}")
    print(f"Used assets:  {len(used_assets)}")
    if args.strict_literals:
        print("Maybe-used:   0 (disabled via --strict-literals)")
    else:
        print(f"Maybe-used:   {len(maybe_used_assets)}")
    print(f"Unused assets:{len(unused_assets)}")

    if maybe_used_assets:
        print("\nMaybe-used assets (dynamic template match):")
        for name in maybe_used_assets:
            print(f"- {name}")

    if unused_assets:
        print("\nUnused assets:")
        for name in unused_assets:
            if args.with_paths:
                print(f"- {name} ({assets[name]})")
            else:
                print(f"- {name}")

    if args.show_used:
        print("\nUsed assets:")
        for name in used_assets:
            refs = sorted(str(path) for path in exact_usage[name])
            print(f"- {name} [{len(refs)} refs]")
            for ref in refs:
                print(f"  {ref}")

        if maybe_used_assets and not args.strict_literals:
            print("\nMaybe-used assets (dynamic template match):")
            for name in maybe_used_assets:
                refs = sorted(str(path) for path in possible_usage[name])
                print(f"- {name} [{len(refs)} potential refs]")
                for ref in refs:
                    print(f"  {ref}")

    if args.fail_on_unused and unused_assets:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

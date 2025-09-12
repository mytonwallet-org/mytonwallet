#!/usr/bin/env python3
"""
Script to convert JSON localization files to YAML format.

This script converts JSON localization files (like en.json) to YAML format (like en.yaml)
preserving multiline strings, special characters, and complex structures like pluralization.

Usage:
    python json_to_yaml.py <input.json> [output.yaml]

Examples:
    # Convert en.json to en.yaml (auto-generated output name)
    python json_to_yaml.py en.json

    # Convert with explicit output file
    python json_to_yaml.py src/i18n/en.json output.yaml

Features:
    - Handles multiline strings using YAML block scalars
    - Preserves special characters in keys (like $)
    - Supports complex nested structures (pluralization, etc.)
    - Auto-detects when to use multiline format
    - Proper YAML escaping for special characters
"""

import json
import sys
import os
from typing import Any, Dict, Union


def is_multiline(text: str) -> bool:
    """Check if text contains newlines or is very long"""
    return '\n' in text


def escape_yaml_string(text: str) -> str:
    """Escape special characters in YAML strings"""
    # Escape quotes if they exist at start/end
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1].replace('"', '\\"')
    if text.startswith("'") and text.endswith("'"):
        return text[1:-1].replace("'", "\\'")

    # Escape colons at the beginning or anywhere in the string
    if text.startswith(':') or ':' in text:
        return f'"{text}"'

    return text


def format_yaml_value(key: str, value: Any, indent: str = "") -> str:
    """Format a single key-value pair in YAML format"""
    if isinstance(value, dict):
        # Handle complex structures like pluralization
        lines = [f"{indent}{key}:"]
        for sub_key, sub_value in value.items():
            if isinstance(sub_value, str) and is_multiline(sub_value):
                # Multiline string
                escaped = escape_yaml_string(sub_value).rstrip('\n')
                lines.append(f"{indent}  {sub_key}: |")
                for line in escaped.split('\n'):
                    lines.append(f"{indent}    {line}")
            else:
                lines.append(f"{indent}  {sub_key}: {escape_yaml_string(sub_value)}")
        return '\n'.join(lines)

    elif isinstance(value, str):
        if is_multiline(value):
            # Multiline string - use YAML block scalar
            escaped = escape_yaml_string(value).rstrip('\n')
            lines = [f"{indent}{key}: |"]
            for line in escaped.split('\n'):
                lines.append(f"{indent}  {line}")
            return '\n'.join(lines)
        else:
            # Simple string
            return f"{indent}{key}: {escape_yaml_string(value)}"

    else:
        # Other types (numbers, booleans, etc.)
        return f"{indent}{key}: {value}"


def json_to_yaml(data: Dict[str, Any]) -> str:
    """Convert JSON data to YAML format"""
    lines = []

    for key, value in data.items():
        yaml_line = format_yaml_value(key, value)
        lines.append(yaml_line)

    return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python json_to_yaml.py <input.json> [output.yaml]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    # If no output file specified, derive from input file
    if not output_file:
        base_name = os.path.splitext(os.path.basename(input_file))[0]
        if base_name.endswith('_en'):
            base_name = base_name[:-3]  # Remove _en suffix
        output_file = f"{base_name}.yaml"

    try:
        # Read JSON file
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # Convert to YAML
        yaml_content = json_to_yaml(data)

        # Write YAML file
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(yaml_content)

        print(f"Successfully converted {input_file} to {output_file}")

    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{input_file}': {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

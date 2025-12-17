#!/usr/bin/env python3
"""Render the Air localization Markdown table as HTML."""

from __future__ import annotations

import argparse
import html
from pathlib import Path
from typing import List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert the Air localization Markdown table into an HTML file."
    )
    parser.add_argument(
        "--input",
        required=True,
        help="Path to the Markdown file to convert.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to write the generated HTML file.",
    )
    return parser.parse_args()


def split_markdown_row(row: str) -> List[str]:
    """Split a Markdown table row into cells, honoring escaped pipes."""
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|"):
        row = row[:-1]

    cells: List[str] = []
    buffer: List[str] = []
    escaped = False

    for char in row:
        if escaped:
            buffer.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == "|":
            cells.append("".join(buffer).strip())
            buffer = []
        else:
            buffer.append(char)

    cells.append("".join(buffer).strip())
    return cells


def markdown_table_to_html(markdown: str) -> str:
    lines = [line for line in (line.strip() for line in markdown.splitlines()) if line]
    if len(lines) < 3:
        raise ValueError("Markdown table must include header, separator, and at least one row.")

    headers = split_markdown_row(lines[0])
    separator = lines[1]
    if not separator.startswith("| ---"):
        raise ValueError("Markdown table separator is missing or malformed.")

    rows = [split_markdown_row(line) for line in lines[2:]]

    html_parts: List[str] = []
    html_parts.append("<table>")

    html_parts.append("  <thead>")
    html_parts.append("    <tr>")
    for header in headers:
        cell = html.escape(header)
        cell = cell.replace("&lt;br&gt;", "<br>")
        html_parts.append(f"      <th>{cell}</th>")
    html_parts.append("    </tr>")
    html_parts.append("  </thead>")

    html_parts.append("  <tbody>")
    for row in rows:
        html_parts.append("    <tr>")
        for cell_value in row:
            cell = html.escape(cell_value)
            cell = cell.replace("&lt;br&gt;", "<br>")
            html_parts.append(f"      <td>{cell or '&mdash;'}</td>")
        html_parts.append("    </tr>")
    html_parts.append("  </tbody>")

    html_parts.append("</table>")

    return "\n".join(html_parts)


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    markdown_content = input_path.read_text(encoding="utf-8")
    table_html = markdown_table_to_html(markdown_content)

    document = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Air Localization Usage</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      padding: 24px;
      background: #f7f7f9;
      color: #111;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: #fff;
      box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
    }}
    th, td {{
      border: 1px solid #dcdfe6;
      padding: 8px 12px;
      vertical-align: top;
      text-align: left;
      font-size: 14px;
    }}
    th {{
      background: #eef1f7;
      font-weight: 600;
    }}
    tbody tr:nth-child(even) {{
      background: #fafafa;
    }}
    code {{
      font-family: "SFMono-Regular", "JetBrains Mono", "Fira Code", monospace;
    }}
  </style>
</head>
<body>
  <h1>Air Localization Usage</h1>
  {table_html}
</body>
</html>
"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(document, encoding="utf-8")
    print(f"Wrote HTML table to {output_path}")


if __name__ == "__main__":
    main()


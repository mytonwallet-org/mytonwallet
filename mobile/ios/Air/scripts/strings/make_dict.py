#!/usr/bin/env python3
import argparse
import json
import re
import sys

COMMENT_BLOCK_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
COMMENT_LINE_RE  = re.compile(r"//.*?$", re.MULTILINE)

# Matches: "Key" = "Value";
PAIR_RE = re.compile(
    r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;',
    re.DOTALL
)

def strip_comments(s: str) -> str:
    s = COMMENT_BLOCK_RE.sub("", s)
    s = COMMENT_LINE_RE.sub("", s)
    return s

def unescape(s: str) -> str:
    # .strings uses C-style escapes. Decode common ones safely.
    # We avoid codecs like 'unicode_escape' to prevent over-decoding.
    escapes = {
        r'\"': '"',
        r"\\": "\\",
        r"\n": "\n",
        r"\r": "\r",
        r"\t": "\t",
        r"\f": "\f",
        r"\b": "\b",
    }
    # Replace simple escapes first
    for k, v in escapes.items():
        s = s.replace(k, v)
    # Handle \uXXXX sequences
    def _u(m):
        try:
            return chr(int(m.group(1), 16))
        except Exception:
            return m.group(0)
    s = re.sub(r"\\u([0-9A-Fa-f]{4})", _u, s)
    return s

def parse_strings(text: str) -> dict:
    text = strip_comments(text)
    result = {}
    for m in PAIR_RE.finditer(text):
        raw_key, raw_val = m.group(1), m.group(2)
        key = unescape(raw_key)
        val = unescape(raw_val)
        key_json = key.replace(".", "_")
        result[key_json] = val
    return result

def read_text(path: str) -> str:
    # .strings are often UTF-16LE with BOM; fall back to UTF-8.
    encodings = ["utf-16", "utf-16-le", "utf-8-sig", "utf-8"]
    last_err = None
    for enc in encodings:
        try:
            with open(path, "r", encoding=enc) as f:
                return f.read()
        except Exception as e:
            last_err = e
    raise last_err

def main():
    ap = argparse.ArgumentParser(description="Convert .strings to JSON dict with dots -> underscores in keys.")
    ap.add_argument("input", help="Path to Localizable.strings")
    ap.add_argument("-o", "--output", help="Path to output JSON (default: stdout)")
    args = ap.parse_args()

    text = read_text(args.input)
    data = parse_strings(text)

    out = json.dumps(data, ensure_ascii=False, indent=2)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(out)
    else:
        sys.stdout.write(out + "\n")

if __name__ == "__main__":
    main()
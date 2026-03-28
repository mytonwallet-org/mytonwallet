#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

python3 -m http.server 8787 --directory "$ROOT_DIR/good" &
GOOD_PID=$!

python3 -m http.server 8788 --directory "$ROOT_DIR/evil" &
EVIL_PID=$!

cleanup() {
  kill "$GOOD_PID" "$EVIL_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo "Good dApp: http://localhost:8787"
echo "Evil dApp: http://localhost:8788"
echo "Press Ctrl+C to stop both servers"

wait

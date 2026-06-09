#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PATCH_FILE="${SCRIPT_DIR}/patches/explore-poc-injection.patch"

if git -C "$ROOT_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
  echo "Explore POC patch is already applied."
  exit 0
fi

git -C "$ROOT_DIR" apply "$PATCH_FILE"
echo "Explore POC patch applied."

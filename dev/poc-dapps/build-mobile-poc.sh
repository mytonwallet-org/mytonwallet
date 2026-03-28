#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <good_url> <evil_url> [development|staging]" >&2
  exit 1
fi

GOOD_URL="$1"
EVIL_URL="$2"
TARGET_ENV="${3:-development}"

if [[ "$TARGET_ENV" != "development" && "$TARGET_ENV" != "staging" ]]; then
  echo "Third argument must be 'development' or 'staging'." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

"${SCRIPT_DIR}/enable-local-poc.sh"

(
  cd "$ROOT_DIR"
  APP_ENV="$TARGET_ENV" \
  EXPLORE_POC_DAPPS=1 \
  EXPLORE_POC_DAPP_GOOD_URL="$GOOD_URL" \
  EXPLORE_POC_DAPP_EVIL_URL="$EVIL_URL" \
  npm run mobile:build
)

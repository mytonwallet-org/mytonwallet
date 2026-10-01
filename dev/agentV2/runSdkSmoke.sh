#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIC_URL="${AGENT_V2_CLASSIC_URL:-http://127.0.0.1:4321}"
CLASSIC_PORT="${AGENT_V2_CLASSIC_PORT:-${CLASSIC_URL##*:}}"
LOG_DIR="${TMPDIR:-/tmp}/agent-v2-frontend-smoke"
CLASSIC_LOG="$LOG_DIR/classic.log"
CLASSIC_PID=""

cleanup() {
  if [[ -n "$CLASSIC_PID" ]]; then
    kill "$CLASSIC_PID" 2>/dev/null || true
    wait "$CLASSIC_PID" 2>/dev/null || true
  fi
}

wait_ready() {
  local attempts=120
  while (( attempts > 0 )); do
    if curl --fail --silent --show-error "$CLASSIC_URL" >/dev/null 2>&1; then
      return
    fi
    if ! kill -0 "$CLASSIC_PID" 2>/dev/null; then
      echo "Classic exited before becoming ready. Log: $CLASSIC_LOG" >&2
      exit 1
    fi
    attempts=$((attempts - 1))
    sleep 0.5
  done
  echo "Classic did not become ready at $CLASSIC_URL. Log: $CLASSIC_LOG" >&2
  exit 1
}

cd "$ROOT_DIR"
node dev/agentV2/runLocalSdkSmoke.cjs

if [[ "${AGENT_V2_SKIP_BROWSER_SMOKE:-0}" == "1" ]]; then
  exit 0
fi

if curl --fail --silent --show-error "$CLASSIC_URL" >/dev/null 2>&1; then
  echo "Classic smoke requires an unused $CLASSIC_URL" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
trap cleanup EXIT INT TERM

AGENT_OVERRIDE=v2 \
  AGENT_V2_QUOTA_STATUS_ENABLED=1 \
  AGENT_API_URL="${AGENT_V2_LOCAL_BASE_URL_A:-http://127.0.0.1:3001}/api" \
  APP_ENV=development \
  ./node_modules/.bin/vite --port "$CLASSIC_PORT" >"$CLASSIC_LOG" 2>&1 &
CLASSIC_PID="$!"

wait_ready
node dev/agentV2/browserSmoke.mjs

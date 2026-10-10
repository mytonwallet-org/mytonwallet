#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENT_BASE_URL="${AGENT_V2_LOCAL_BASE_URL_A:-http://127.0.0.1:3001}"
AGENT_BASE_URL="${AGENT_BASE_URL%/}"
READY_URL="$AGENT_BASE_URL/ready"
FRONTEND_PORT=4321
FRONTEND_STOP_ATTEMPTS=50

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to check the local my-agent service" >&2
  exit 1
fi

if ! command -v lsof >/dev/null 2>&1; then
  echo "lsof is required to manage the local frontend server" >&2
  exit 1
fi

stop_existing_frontend() {
  local listener_pids=""
  listener_pids="$(lsof -tiTCP:"$FRONTEND_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -z "$listener_pids" ]]; then
    return
  fi

  local listener_pid=""
  while IFS= read -r listener_pid; do
    local command=""
    local working_directory=""
    command="$(ps -p "$listener_pid" -o command= 2>/dev/null || true)"
    working_directory="$(lsof -a -p "$listener_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
    if [[ "$working_directory" != "$ROOT_DIR" || "$command" != *vite* ]]; then
      echo "Frontend port $FRONTEND_PORT is used by another process: PID $listener_pid ($command)" >&2
      exit 1
    fi
  done <<< "$listener_pids"

  echo "Stopping the existing frontend server on port $FRONTEND_PORT..."
  while IFS= read -r listener_pid; do
    kill -TERM "$listener_pid" 2>/dev/null || true
  done <<< "$listener_pids"

  local attempts="$FRONTEND_STOP_ATTEMPTS"
  while (( attempts > 0 )); do
    if [[ -z "$(lsof -tiTCP:"$FRONTEND_PORT" -sTCP:LISTEN 2>/dev/null || true)" ]]; then
      return
    fi
    attempts=$((attempts - 1))
    sleep 0.1
  done

  echo "The existing frontend server did not release port $FRONTEND_PORT" >&2
  exit 1
}

if ! READINESS="$(
  curl \
    --fail \
    --silent \
    --show-error \
    --max-time 3 \
    "$READY_URL"
)"; then
  echo "Local my-agent is not ready at $READY_URL" >&2
  echo "Start it from the my-agent repository with: npm run dev:v2:codex" >&2
  exit 1
fi

if ! node -e '
  try {
    const snapshot = JSON.parse(process.argv[1]);
    if (snapshot?.schemaVersion !== 1 || snapshot?.ready !== true) process.exit(1);
  } catch {
    process.exit(1);
  }
' "$READINESS"; then
  echo "Local my-agent returned an invalid readiness response from $READY_URL" >&2
  echo "Start a compatible backend with: npm run dev:v2:codex" >&2
  exit 1
fi

echo "Local my-agent is ready: $AGENT_BASE_URL"
stop_existing_frontend

cd "$ROOT_DIR"
AGENT_V2_QUOTA_STATUS_ENABLED=1 \
  AGENT_API_URL="$AGENT_BASE_URL/api" \
  exec npm run dev

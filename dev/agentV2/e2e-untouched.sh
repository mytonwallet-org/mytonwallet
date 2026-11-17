#!/bin/bash

# Usage: e2e-untouched.sh <pr|master> <base> <head>
# Exits 0 only when no changed path reaches Agent E2E in that mode; an unknown mode, an unreadable range or an empty diff exits 1
# `pr` covers the Agent itself, the suite and the build; `master` adds the shared code the Agent screens execute

mode=${1:-}
base=${2:-}
head=${3:-}

case "$mode" in
  pr|master) ;;
  *) exit 1 ;;
esac

base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || exit 1
head_sha=$(git rev-parse --verify --quiet "$head^{commit}") || exit 1

# A move out of an E2E input still reports the original path as a deletion.
changed=$(git -c core.quotePath=false diff --name-only --no-renames "$base_sha" "$head_sha") || exit 1
[ -n "$changed" ] || exit 1

# Split in memory so a failed temporary file cannot turn an empty loop into a skip.
set -f
IFS=$'\n'
for path in $changed; do
  case "$path" in
    # Git quotes a path with unusual characters, which no pattern below can then match
    \"*) exit 1 ;;
    tests/playwright/agent-v2/*|playwright.agent-v2.config.ts|dev/agentV2/*|.github/workflows/agent-v2-e2e.yml) exit 1 ;;
    src/*.test.ts|src/*.test.tsx|*.md) continue ;;
    src/*[Aa]gent*) exit 1 ;;
    package.json|package-lock.json|tsconfig.json|vite.config.ts|.browserslistrc|postcss.config.js) exit 1 ;;
    plugins/*|patches/*|public/*|deploy/copy_to_dist.sh|dev/loadEnv.ts|dev/buildStamp.ts|dev/locales/*) exit 1 ;;
    src/index.html|src/index.tsx|src/config.ts|src/util/fetchLogging.ts) exit 1 ;;
  esac
  [ "$mode" = master ] || continue

  case "$path" in
    src/components/App.tsx|src/components/ui/*|src/components/common/*|src/components/main/*|src/components/receive/*) exit 1 ;;
    src/components/settings/Settings.tsx|src/components/settings/SettingsAppearance.tsx|src/components/settings/SettingsHeader.tsx|src/components/settings/Settings.module.scss) exit 1 ;;
    src/global/*|src/util/*|src/hooks/*|src/lib/*|src/api/*|src/styles/*|src/assets/*|src/i18n/en.yaml) exit 1 ;;
  esac
done

exit 0

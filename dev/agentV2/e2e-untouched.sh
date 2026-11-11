#!/bin/bash

# Usage: e2e-untouched.sh <base> <head>
# Exits 0 only when every changed path is listed below; anything unproven exits 1.

base=${1:-}
head=${2:-}

base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || exit 1
head_sha=$(git rev-parse --verify --quiet "$head^{commit}") || exit 1

# A move out of an E2E input still reports the original path as a deletion.
changed=$(git -c core.quotePath=false diff --name-only --no-renames "$base_sha" "$head_sha") || exit 1
[ -n "$changed" ] || exit 1

# Split in memory so a failed temporary file cannot turn an empty loop into a skip.
set -f
IFS=$'\n'
for path in $changed; do
  # Only folders outside the Agent E2E build inputs and opened screens may skip.
  # Pushes to master always run the tests.
  case "$path" in
    src/components/agent/*|src/components/agentV2/*|src/components/ui/*|src/components/main/*|src/components/App.tsx) exit 1 ;;
    src/components/receive/*|src/components/common/*) exit 1 ;;
    src/components/settings/Settings.tsx|src/components/settings/SettingsAppearance.tsx|src/components/settings/SettingsHeader.tsx|src/components/settings/Settings.module.scss) exit 1 ;;
    src/i18n/en.yaml|.github/workflows/test.yml|deploy/copy_to_dist.sh) exit 1 ;;
    dev/agentV2/*|dev/locales/*|dev/loadEnv.ts|dev/buildStamp.ts) exit 1 ;;
    src/components/*|src/i18n/*.yaml|.github/*|deploy/*|dev/*) ;;
    mobile/*|maestro/*|docs/*|.agents/*|.claude/*|.codex/*|.cursor/*|.milkignore) ;;
    */*) exit 1 ;;
    *.md) ;;
    *) exit 1 ;;
  esac
done

exit 0

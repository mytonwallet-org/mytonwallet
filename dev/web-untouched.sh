#!/bin/bash

# Usage: web-untouched.sh <netlify|actions> <base> <head>
# Exits 0 only when every path changed in the range is listed below; anything unproven exits 1.

scope=${1:-}
base=${2:-}
head=${3:-}

case "$scope" in
  netlify|actions) ;;
  *) exit 1 ;;
esac

base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || exit 1
head_sha=$(git rev-parse --verify --quiet "$head^{commit}") || exit 1

# A rename reports only its destination, so a file moved from `src/` to `docs/` would look docs-only
changed=$(git -c core.quotePath=false diff --name-only --no-renames "$base_sha" "$head_sha") || exit 1
[ -n "$changed" ] || exit 1

# Split in memory: a long here-string needs a temp file, and when that fails the loop never runs
set -f
IFS=$'\n'
for path in $changed; do
  # eslint, stylelint and jest glob the whole tree, so a script or stylesheet counts wherever it lives
  if [ "$scope" = actions ]; then
    case "$path" in
      *.js|*.mjs|*.cjs|*.jsx|*.mjsx|*.ts|*.mts|*.cts|*.tsx|*.mtsx|*.css|*.scss) exit 1 ;;
    esac
  fi

  case "$path" in
    mobile/*|docs/*|.agents/*|.claude/*|.codex/*|.cursor/*|.milkignore) ;;
    # `test:signing-schedule` parses the iOS signing workflows, and the web jobs are defined here
    .github/*) [ "$scope" = netlify ] || exit 1 ;;
    */*) exit 1 ;;
    *.md) ;;
    *) exit 1 ;;
  esac
done

exit 0

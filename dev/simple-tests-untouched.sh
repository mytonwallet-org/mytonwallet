#!/bin/bash

# Usage: simple-tests-untouched.sh <base> <head>
# Exits 0 only when no path changed in the range is read by the Simple tests job; anything unproven exits 1.

base=${1:-}
head=${2:-}

base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || exit 1
head_sha=$(git rev-parse --verify --quiet "$head^{commit}") || exit 1

# A rename reports only its destination, so a file moved from `src/` to `docs/` would look docs-only
changed=$(git -c core.quotePath=false diff --name-only --no-renames "$base_sha" "$head_sha") || exit 1
[ -n "$changed" ] || exit 1

# Split in memory: a long here-string needs a temp file, and when that fails the loop never runs
set -f
IFS=$'\n'
for path in $changed; do
  # Stylelint globs every stylesheet, Jest every test outside `mobile/`, and ESLint every script outside its ignores
  case "$path" in
    # Jest picks up a mock of an npm package from any directory
    *.css|*.scss|__mocks__/*|*/__mocks__/*) exit 1 ;;
    mobile/*) continue ;;
    *.test.*|*.spec.*|test.*|spec.*|*/test.*|*/spec.*|*/__tests__/*) exit 1 ;;
    dev/*|maestro/*|deploy/*|.github/*|.claude/*) ;;
    *.js|*.mjs|*.cjs|*.jsx|*.mjsx|*.ts|*.mts|*.cts|*.tsx|*.mtsx) exit 1 ;;
  esac

  case "$path" in
    maestro/*|docs/*|changelogs/*|.agents/*|.claude/*|.codex/*|.cursor/*|.husky/*|.milkignore|netlify.toml) ;;
    deploy/ios_sign/*|deploy/*.md) ;;
    # The steps run the `dev/` modules listed here, and Jest runs the tests in `dev/mfa/`
    dev/locales/*|dev/agentV2/*|dev/mfa/*|dev/loadEnv.ts|dev/buildStamp.ts|dev/fileNaming*|dev/fixFileNames*) exit 1 ;;
    dev/layoutAnimationPlugin*|dev/extensionLicenses*|dev/signingExpirySchedule*|dev/web-untouched*) exit 1 ;;
    dev/netlify-ignore.sh|dev/simple-tests-untouched*|dev/ciSettle*|dev/checkPrTitle*|dev/broadcastGuard*) exit 1 ;;
    dev/testnetProxy*|dev/checkAgentV2Contract*|dev/jestForChanges*|dev/webE2eSummary*|dev/gramReleaseDispatch*) exit 1 ;;
    dev/*) ;;
    .github/workflows/test.yml|.github/workflows/ios-signing-expiry*|.github/ci-settle.json) exit 1 ;;
    .github/*) ;;
    */*) exit 1 ;;
    *.md) ;;
    *) exit 1 ;;
  esac
done

exit 0

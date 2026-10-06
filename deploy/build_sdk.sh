#!/bin/bash

# Without this the script keeps going after a failed build and copies whatever `dist-air`
# happened to hold, which reaches the mobile asset dirs as a silently stale SDK.
set -euo pipefail

# The Agent host has to be settled BEFORE the bundles are built, because this is the only moment
# it can still reach them: `defineEnv` bakes `process.env.AGENT_API_URL` into the SDK at build time
# and the native app has no way to point itself elsewhere afterwards. Resolving it after the build,
# as this did, validated a value nothing used - a TestFlight build of the beta app shipped talking
# to the production Agent, where the V2 API is switched off, and every chat it opened failed on a
# 404 that named no host.
#
# A repository variable that is unset expands to an empty string rather than disappearing, and
# `defineEnv` keeps an empty string as-is (it only replaces null and undefined), so the bundle used
# to inherit `''` and fall through to the production default inside src/config.ts. In CI that
# silence is the bug, so an empty value stops the build instead; a developer without .env still
# gets the default.
if [ -n "${CI:-}" ] && [ -z "${AGENT_API_URL:-}" ]; then
  echo "AGENT_API_URL is empty. Set the repository variable, or the SDK would silently ship pointing at the production Agent." >&2
  exit 1
fi

AGENT_API_URL=$(node -r dotenv/config -e 'process.stdout.write(process.env.AGENT_API_URL || "https://agent.mywallet.io/api")')
node -e '
const [agentApiBaseUrl] = process.argv.slice(1);
const url = new URL(agentApiBaseUrl);
const loopbackHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
const hasSafeProtocol = url.protocol === "https:"
  || (url.protocol === "http:" && loopbackHosts.has(url.hostname.toLowerCase()));
if (!hasSafeProtocol || !url.hostname || url.username || url.password || url.search || url.hash) {
  throw new Error("AGENT_API_URL must use HTTPS, or HTTP on loopback, without credentials, query, or fragment");
}
' "$AGENT_API_URL"
export AGENT_API_URL

# Printed because the shipped host was not observable anywhere: neither the job log nor the app
# said which Agent the bundle would talk to, and answering that took a device log export.
echo "Agent API for this SDK: $AGENT_API_URL"

# Build SDKs
rm -rf dist-air
SDK_OUTPUT_CLEAN=1 IS_GRAM_WALLET=0 vite build --config vite-air.config.ts
SDK_OUTPUT_CLEAN=0 IS_GRAM_WALLET=1 vite build --config vite-air.config.ts

for sdk in dist-air/mytonwallet-sdk.js dist-air/gramwallet-sdk.js; do
  if [ ! -s "$sdk" ]; then
    echo "SDK build produced no $sdk" >&2
    exit 1
  fi
done

# The frozen iOS Agent reads its protocol override from this bundle resource.
AGENT_OVERRIDE_VALUE=$(node -r dotenv/config -e 'process.stdout.write(process.env.AGENT_OVERRIDE || "v1")')
case "$AGENT_OVERRIDE_VALUE" in
  no_override|v1|v2) ;;
  *)
    echo "Unsupported AGENT_OVERRIDE value: $AGENT_OVERRIDE_VALUE" >&2
    exit 1
    ;;
esac
node -e '
const [override, agentApiBaseUrl] = process.argv.slice(1);
process.stdout.write(`${JSON.stringify({ override, agentApiBaseUrl })}\n`);
' "$AGENT_OVERRIDE_VALUE" "$AGENT_API_URL" > dist-air/agent-override-config.json

mkdir -p dist
bash ./deploy/copy_to_dist.sh

IOS_LEGACY_TARGET="mobile/ios/Air/SubModules/WalletResources/Resources/JS"
IOS_MYTONWALLET_TARGET="mobile/ios/App/App/Resources/MyTonWallet/JS"
IOS_GRAM_TARGET="mobile/ios/App/App/Resources/GramWallet/JS"
ANDROID_MYTONWALLET_TARGET="mobile/android/app/src/mytonwallet/assets/js"
ANDROID_GRAM_TARGET="mobile/android/app/src/gram/assets/js"

mkdir -p "$IOS_MYTONWALLET_TARGET"
mkdir -p "$IOS_GRAM_TARGET"
mkdir -p "$ANDROID_MYTONWALLET_TARGET"
mkdir -p "$ANDROID_GRAM_TARGET"

# Copy SDKs to iOS target-specific asset dirs
rm -f "$IOS_LEGACY_TARGET"/*-sdk.js "$IOS_LEGACY_TARGET"/*-sdk.js.LICENSE.txt

rm -f \
  "$IOS_MYTONWALLET_TARGET"/*-sdk.js \
  "$IOS_MYTONWALLET_TARGET"/*-sdk.js.LICENSE.txt \
  "$IOS_MYTONWALLET_TARGET"/agent-*-config.json
cp dist-air/mytonwallet-sdk.js "$IOS_MYTONWALLET_TARGET/"
cp dist-air/agent-override-config.json "$IOS_MYTONWALLET_TARGET/"

rm -f \
  "$IOS_GRAM_TARGET"/*-sdk.js \
  "$IOS_GRAM_TARGET"/*-sdk.js.LICENSE.txt \
  "$IOS_GRAM_TARGET"/agent-*-config.json
cp dist-air/gramwallet-sdk.js "$IOS_GRAM_TARGET/"
cp dist-air/agent-override-config.json "$IOS_GRAM_TARGET/"

# Copy SDKs to Android flavor-specific asset dirs
rm -f \
  "$ANDROID_MYTONWALLET_TARGET"/*-sdk.js \
  "$ANDROID_MYTONWALLET_TARGET"/*-sdk.js.LICENSE.txt \
  "$ANDROID_MYTONWALLET_TARGET"/agent-*-config.json
cp dist-air/mytonwallet-sdk.js "$ANDROID_MYTONWALLET_TARGET/"

rm -f \
  "$ANDROID_GRAM_TARGET"/*-sdk.js \
  "$ANDROID_GRAM_TARGET"/*-sdk.js.LICENSE.txt \
  "$ANDROID_GRAM_TARGET"/agent-*-config.json
cp dist-air/gramwallet-sdk.js "$ANDROID_GRAM_TARGET/"

# What actually shipped, read back out of the copies instead of trusted from the commands that made
# them. Every check above runs before the copy, so a target directory still holding an older bundle
# passes all of them - which is how an app reached TestFlight running JS six weeks older than the
# wrapper around it. The stamp printed here is the same token the app logs as it loads, so a device
# and this job can be compared directly.
echo "Shipped SDK bundles:"
node ./deploy/report_sdk_assets.js \
  dist-air/mytonwallet-sdk.js \
  "$IOS_MYTONWALLET_TARGET/mytonwallet-sdk.js" \
  "$ANDROID_MYTONWALLET_TARGET/mytonwallet-sdk.js"
node ./deploy/report_sdk_assets.js \
  dist-air/gramwallet-sdk.js \
  "$IOS_GRAM_TARGET/gramwallet-sdk.js" \
  "$ANDROID_GRAM_TARGET/gramwallet-sdk.js"

# Build .xcstrings from YAML locale files when Xcode is available. Local Agent launchers reuse the
# checked-in compiled strings so the acceptance cycle stays offline.
if [ "${MOBILE_SDK_SKIP_IOS_LOCALIZATIONS:-0}" != "1" ] && command -v xcrun > /dev/null 2>&1; then
  PY_SCRIPTS_DIR="./mobile/ios/Air/scripts/strings"
  PY_VENV_DIR="$PY_SCRIPTS_DIR/.venv"

  if [ ! -d "$PY_VENV_DIR" ]; then
    python3 -m venv "$PY_VENV_DIR"
  fi

  "$PY_VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade pip
  "$PY_VENV_DIR/bin/python" -m pip install --disable-pip-version-check -r "$PY_SCRIPTS_DIR/requirements.txt"

  "$PY_VENV_DIR/bin/python" "$PY_SCRIPTS_DIR/import_localizations.py"
fi

echo "SDK build completed and copied to mobile platforms"

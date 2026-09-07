#!/bin/bash

# Without this the script keeps going after a failed webpack run and copies whatever `dist-air`
# happened to hold, which reaches the mobile asset dirs as a silently stale SDK.
set -euo pipefail

# Build SDKs
rm -rf dist-air
SDK_OUTPUT_CLEAN=1 IS_GRAM_WALLET=0 webpack --config webpack-air.config.ts
SDK_OUTPUT_CLEAN=0 IS_GRAM_WALLET=1 webpack --config webpack-air.config.ts

for sdk in dist-air/mytonwallet-sdk.js dist-air/gramwallet-sdk.js; do
  if [ ! -s "$sdk" ]; then
    echo "SDK build produced no $sdk" >&2
    exit 1
  fi
done

# `??` falls back only on an undefined variable, and CI hands these two an empty string instead: a
# workflow env of `${{ vars.X }}` expands to `""` when the repository does not define the variable,
# and so does a bare `X=` line in `.env`. The public repository has no AGENT_API_URL, which turned
# the fallback below into `new URL("")` and took down all three mobile release builds of v26.9.0.
# `||` treats empty and unset alike, which is what a default here means.
AGENT_OVERRIDE_VALUE=$(node -r dotenv/config -e 'process.stdout.write(process.env.AGENT_OVERRIDE || "v1")')
case "$AGENT_OVERRIDE_VALUE" in
  no_override|v1|v2) ;;
  *)
    echo "Unsupported AGENT_OVERRIDE value: $AGENT_OVERRIDE_VALUE" >&2
    exit 1
    ;;
esac
AGENT_API_BASE_URL=$(node -r dotenv/config -e 'process.stdout.write(process.env.AGENT_API_URL || "https://agent.mywallet.io/api")')
node -e '
const [override, agentApiBaseUrl] = process.argv.slice(1);
const url = new URL(agentApiBaseUrl);
const loopbackHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
const hasSafeProtocol = url.protocol === "https:"
  || (url.protocol === "http:" && loopbackHosts.has(url.hostname.toLowerCase()));
if (!hasSafeProtocol || !url.hostname || url.username || url.password || url.search || url.hash) {
  throw new Error("AGENT_API_URL must use HTTPS, or HTTP on loopback, without credentials, query, or fragment");
}
process.stdout.write(`${JSON.stringify({ override, agentApiBaseUrl })}\n`);
' "$AGENT_OVERRIDE_VALUE" "$AGENT_API_BASE_URL" > dist-air/agent-override-config.json

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
cp dist-air/mytonwallet-sdk.js.LICENSE.txt "$IOS_MYTONWALLET_TARGET/" 2>/dev/null || true
cp dist-air/agent-override-config.json "$IOS_MYTONWALLET_TARGET/"

rm -f \
  "$IOS_GRAM_TARGET"/*-sdk.js \
  "$IOS_GRAM_TARGET"/*-sdk.js.LICENSE.txt \
  "$IOS_GRAM_TARGET"/agent-*-config.json
cp dist-air/gramwallet-sdk.js "$IOS_GRAM_TARGET/"
cp dist-air/gramwallet-sdk.js.LICENSE.txt "$IOS_GRAM_TARGET/" 2>/dev/null || true
cp dist-air/agent-override-config.json "$IOS_GRAM_TARGET/"

# Copy SDKs to Android flavor-specific asset dirs
rm -f "$ANDROID_MYTONWALLET_TARGET"/*-sdk.js "$ANDROID_MYTONWALLET_TARGET"/*-sdk.js.LICENSE.txt
cp dist-air/mytonwallet-sdk.js "$ANDROID_MYTONWALLET_TARGET/"
cp dist-air/mytonwallet-sdk.js.LICENSE.txt "$ANDROID_MYTONWALLET_TARGET/" 2>/dev/null || true

rm -f "$ANDROID_GRAM_TARGET"/*-sdk.js "$ANDROID_GRAM_TARGET"/*-sdk.js.LICENSE.txt
cp dist-air/gramwallet-sdk.js "$ANDROID_GRAM_TARGET/"
cp dist-air/gramwallet-sdk.js.LICENSE.txt "$ANDROID_GRAM_TARGET/" 2>/dev/null || true

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

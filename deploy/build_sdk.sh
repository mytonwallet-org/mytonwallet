#!/bin/bash

# Build SDKs
rm -rf dist-air
SDK_OUTPUT_CLEAN=1 IS_GRAM_WALLET=0 webpack --config webpack-air.config.ts
SDK_OUTPUT_CLEAN=0 IS_GRAM_WALLET=1 webpack --config webpack-air.config.ts

bash ./deploy/copy_to_dist.sh

IOS_TARGET="mobile/ios/Air/SubModules/WalletContext/Resources/JS"
ANDROID_MYTONWALLET_TARGET="mobile/android/app/src/mytonwallet/assets/js"
ANDROID_GRAM_TARGET="mobile/android/app/src/gram/assets/js"

mkdir -p "$IOS_TARGET"
mkdir -p "$ANDROID_MYTONWALLET_TARGET"
mkdir -p "$ANDROID_GRAM_TARGET"

# Copy SDKs to iOS
rm -f "$IOS_TARGET"/*-sdk.js "$IOS_TARGET"/*-sdk.js.LICENSE.txt
cp dist-air/*-sdk.js "$IOS_TARGET/"
cp dist-air/*-sdk.js.LICENSE.txt "$IOS_TARGET/" 2>/dev/null || true

# Copy SDKs to Android flavor-specific asset dirs
rm -f "$ANDROID_MYTONWALLET_TARGET"/*-sdk.js "$ANDROID_MYTONWALLET_TARGET"/*-sdk.js.LICENSE.txt
cp dist-air/mytonwallet-sdk.js "$ANDROID_MYTONWALLET_TARGET/"
cp dist-air/mytonwallet-sdk.js.LICENSE.txt "$ANDROID_MYTONWALLET_TARGET/" 2>/dev/null || true

rm -f "$ANDROID_GRAM_TARGET"/*-sdk.js "$ANDROID_GRAM_TARGET"/*-sdk.js.LICENSE.txt
cp dist-air/gramwallet-sdk.js "$ANDROID_GRAM_TARGET/"
cp dist-air/gramwallet-sdk.js.LICENSE.txt "$ANDROID_GRAM_TARGET/" 2>/dev/null || true

# Build .xcstrings from YAML locale files
PY_SCRIPTS_DIR="./mobile/ios/Air/scripts/strings"
PY_VENV_DIR="$PY_SCRIPTS_DIR/.venv"

if [ ! -d "$PY_VENV_DIR" ]; then
  python3 -m venv "$PY_VENV_DIR"
fi

"$PY_VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade pip
"$PY_VENV_DIR/bin/python" -m pip install --disable-pip-version-check -r "$PY_SCRIPTS_DIR/requirements.txt"

"$PY_VENV_DIR/bin/python" "$PY_SCRIPTS_DIR/import_localizations.py"

echo "SDK build completed and copied to mobile platforms"

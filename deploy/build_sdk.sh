#!/bin/bash

# Build SDK
webpack --config webpack-air.config.ts

bash ./deploy/copy_to_dist.sh

IOS_TARGET="mobile/ios/Air/SubModules/WalletContext/Resources/JS"
ANDROID_TARGET="mobile/android/air/SubModules/AirAsFramework/src/main/assets/js"

mkdir -p "$IOS_TARGET"
mkdir -p "$ANDROID_TARGET"

# Copy SDK to iOS
cp dist-air/mytonwallet-sdk.js "$IOS_TARGET/"

# Copy SDK to Android
cp dist-air/mytonwallet-sdk.js "$ANDROID_TARGET/"

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

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENT_BASE_URL="${AGENT_V2_LOCAL_BASE_URL_A:-http://127.0.0.1:${WEB_PORT:-3001}}"
AGENT_BASE_URL="${AGENT_BASE_URL%/}"
DERIVED_DATA_PATH="${AGENT_V2_IOS_DERIVED_DATA_PATH:-/tmp/agent-v2-air-app-derived}"

wait_ready() {
  local url="$1"
  local attempts=120
  while (( attempts > 0 )); do
    local readiness=""
    if readiness="$(curl --fail --silent --show-error --max-time 3 "$url/ready" 2>/dev/null)" \
      && node -e '
        try {
          const snapshot = JSON.parse(process.argv[1]);
          if (snapshot?.schemaVersion !== 1 || snapshot?.ready !== true) process.exit(1);
        } catch {
          process.exit(1);
        }
      ' "$readiness"; then
      echo "Local my-agent is ready: $url"
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 0.25
  done
  echo "Local my-agent did not become ready at $url/ready" >&2
  echo "Start it first and set AGENT_V2_LOCAL_BASE_URL_A if it does not use port 3001" >&2
  exit 1
}

select_iphone_simulator() {
  local requested_udid="${1:-}"
  local last_used_udid=""
  last_used_udid="$(defaults read com.apple.iphonesimulator CurrentDeviceUDID 2>/dev/null || true)"

  xcrun simctl list devices available --json | node -e '
    let input = "";
    const requestedUdid = process.argv[1];
    const lastUsedUdid = process.argv[2];
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { input += chunk; });
    process.stdin.on("end", () => {
      const payload = JSON.parse(input);
      const devices = Object.values(payload.devices).flat().filter((device) => (
        device.isAvailable && device.deviceTypeIdentifier.includes(".iPhone-")
      ));
      const iphone = (
        devices.find((device) => requestedUdid && device.udid === requestedUdid)
        || devices.find((device) => device.state === "Booted")
        || devices.find((device) => lastUsedUdid && device.udid === lastUsedUdid)
        || devices[0]
      );
      if (!iphone) process.exit(1);
      process.stdout.write(iphone.udid);
    });
  ' "$requested_udid" "$last_used_udid"
}

boot_iphone_simulator() {
  local simulator_udid="$1"

  if ! xcrun simctl list devices booted --json | grep -Fq "$simulator_udid"; then
    echo "Booting iPhone Simulator $simulator_udid..."
    xcrun simctl boot "$simulator_udid"
  fi

  open -a Simulator --args -CurrentDeviceUDID "$simulator_udid"
  xcrun simctl bootstatus "$simulator_udid" -b
}

build_install_and_launch_air() {
  local requested_udid="${AGENT_V2_IOS_SIMULATOR_UDID:-}"
  local simulator_udid=""
  if ! simulator_udid="$(select_iphone_simulator "$requested_udid")"; then
    echo "No available iPhone Simulator was found. Install an iOS Simulator runtime in Xcode and retry." >&2
    exit 1
  fi
  if [[ -n "$requested_udid" && "$simulator_udid" != "$requested_udid" ]]; then
    echo "Requested iPhone Simulator is unavailable: $requested_udid" >&2
    exit 1
  fi

  boot_iphone_simulator "$simulator_udid"

  local workspace="$ROOT_DIR/mobile/ios/App/App.xcworkspace"
  local app_bundle="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/My Wallet_AirOnly.app"
  echo "Building MyTonWallet_AirOnly for iOS Simulator..."
  xcodebuild \
    -workspace "$workspace" \
    -scheme MyTonWallet_AirOnly \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -skipMacroValidation \
    build \
    -quiet

  if [[ ! -d "$app_bundle" ]]; then
    echo "Air application bundle was not produced at $app_bundle" >&2
    exit 1
  fi

  xcrun simctl install "$simulator_udid" "$app_bundle"
  xcrun simctl launch --terminate-running-process "$simulator_udid" org.mytonwallet.app
  echo "Air was rebuilt, installed and launched on Simulator $simulator_udid."
}

wait_ready "$AGENT_BASE_URL"

cd "$ROOT_DIR"
  AGENT_API_URL="$AGENT_BASE_URL/api" \
  MOBILE_SDK_SKIP_IOS_LOCALIZATIONS=1 \
  npm run mobile:build:dev

IOS_AGENT_BUNDLE="$ROOT_DIR/mobile/ios/App/App/Resources/MyTonWallet/JS/mytonwallet-sdk.js"
if ! grep -Fq "AGENT_API_URL = \"$AGENT_BASE_URL/api\"" "$IOS_AGENT_BUNDLE"; then
  echo "Air SDK was built without the required local Agent API URL" >&2
  exit 1
fi

build_install_and_launch_air

echo "Agent V2 iOS app is ready."
echo "Local my-agent: $AGENT_BASE_URL"

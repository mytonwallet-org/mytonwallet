#!/bin/zsh

set -euo pipefail

MODE="${1:-verify}"
case "$MODE" in
  record|verify) ;;
  *)
    echo "Usage: $0 [record|verify]"
    exit 2
    ;;
esac

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:A:h:h:h:h}"
WORKSPACE="$REPO_ROOT/mobile/ios/App/App.xcworkspace"
CATALOG="$REPO_ROOT/mobile/ios/Air/SubModules/AirAsFramework/Debug/ProtectedActionPresentationSnapshots.swift"
SNAPSHOT_ROOT="$REPO_ROOT/mobile/ios/Air/Tests/ProtectedActionSnapshotTests"
SNAPSHOT_DIR="$SNAPSHOT_ROOT/__Snapshots__/ProtectedActionPresentationSnapshotTests"
FAILURE_DIR="$SNAPSHOT_ROOT/__Failures__"
GALLERY="$SNAPSHOT_ROOT/gallery.html"
BUNDLE_ID="org.mytonwallet.app.preview"
CAPTURE_DELAY="${CAPTURE_DELAY:-1.5}"
STABILITY_INTERVAL="${STABILITY_INTERVAL:-0.25}"
STABILITY_ATTEMPTS="${STABILITY_ATTEMPTS:-24}"
RECORDING_DIR=""

SIMULATOR_ID="${SIMULATOR_ID:-$(xcrun simctl list devices booted | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -1)}"
if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No booted iOS Simulator found. Boot the simulator to use, or set SIMULATOR_ID."
  exit 1
fi

snapshot_identifiers() {
  sed -n '/public static let identifiers = \[/,/^    \]/p' "$CATALOG" \
    | sed -nE 's/^[[:space:]]*"([^"]+)",$/\1/p'
}

snapshot_case_id() {
  local identifier="$1"
  case "$identifier" in
    *-passcode) echo "${identifier%-passcode}" ;;
    *-mfa) echo "${identifier%-mfa}" ;;
    *-success) echo "${identifier%-success}" ;;
    *) return 1 ;;
  esac
}

snapshot_phase() {
  local identifier="$1"
  case "$identifier" in
    *-passcode) echo "passcode" ;;
    *-mfa) echo "mfa" ;;
    *-success) echo "success" ;;
    *) return 1 ;;
  esac
}

snapshot_filename() {
  local identifier="$1"
  local case_id="$(snapshot_case_id "$identifier")"
  local phase="$(snapshot_phase "$identifier")"
  local position
  case "$phase" in
    passcode) position="01" ;;
    mfa) position="02" ;;
    success) position="03" ;;
  esac
  echo "protected-action-presentations.$case_id.$position-$phase.png"
}

snapshot_case_ids() {
  snapshot_identifiers | sed -nE 's/-passcode$//p'
}

has_snapshot_identifier() {
  local expected="$1"
  snapshot_identifiers | grep -Fxq "$expected"
}

snapshots_match() {
  local reference="$1"
  local actual="$2"

  if cmp -s "$reference" "$actual"; then
    return 0
  fi

  # Core Animation and the Simulator display mask occasionally vary by one or
  # two color levels along antialiased edges. Keep the comparison strict while
  # ignoring only that sub-visible rasterization noise.
  if command -v magick >/dev/null; then
    magick compare -fuzz 1% -metric AE "$reference" "$actual" null: >/dev/null 2>&1
    return $?
  fi

  return 1
}

apply_status_bar_override() {
  xcrun simctl status_bar "$SIMULATOR_ID" override \
    --time 9:41 \
    --dataNetwork wifi \
    --wifiBars 3 \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 100
}

capture_stable_screenshot() {
  local output="$1"
  local previous="${output%.png}.previous.$$.png"
  local current="${output%.png}.current.$$.png"
  local stable_matches=0
  local attempt

  # Keep the complete display so status-bar, safe-area, and bottom-sheet margins
  # are covered. The alpha hardware mask preserves the real device shape without
  # the intermittent framebuffer corruption caused by simctl's black mask.
  apply_status_bar_override
  xcrun simctl io "$SIMULATOR_ID" screenshot --type=png --mask=alpha "$previous" >/dev/null 2>&1
  for (( attempt = 1; attempt <= STABILITY_ATTEMPTS; attempt += 1 )); do
    sleep "$STABILITY_INTERVAL"
    xcrun simctl io "$SIMULATOR_ID" screenshot --type=png --mask=alpha "$current" >/dev/null 2>&1
    if cmp -s "$previous" "$current"; then
      (( stable_matches += 1 ))
      if (( stable_matches >= 2 )); then
        mv "$current" "$output"
        rm -f "$previous"
        return 0
      fi
    else
      stable_matches=0
    fi
    mv "$current" "$previous"
  done

  rm -f "$previous" "$current"
  return 1
}

if [[ -z "$(snapshot_identifiers)" ]]; then
  echo "Could not read snapshot identifiers from $CATALOG"
  exit 1
fi

cleanup() {
  xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$SIMULATOR_ID" clear >/dev/null 2>&1 || true
  if [[ -n "$RECORDING_DIR" ]]; then
    rm -rf "$RECORDING_DIR"
  fi
}
trap cleanup EXIT INT TERM

if [[ "$MODE" == "verify" ]] && ! find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name '*.png' -print -quit 2>/dev/null | grep -q .; then
  echo "No local snapshot references found. Run '$0 record' first."
  exit 1
fi

echo "Building the hosted snapshot app..."
set -o pipefail
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme MyTonWallet_Preview \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  build | xcbeautify

APP_PATH="$(
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme MyTonWallet_Preview \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -showBuildSettings \
    | awk -F ' = ' '/ TARGET_BUILD_DIR = / { directory=$2 } / WRAPPER_NAME = / { name=$2 } END { print directory "/" name }'
)"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH"
  exit 1
fi

xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl terminate "$SIMULATOR_ID" org.mytonwallet.app >/dev/null 2>&1 || true
apply_status_bar_override

mkdir -p "$SNAPSHOT_DIR"
if [[ "$MODE" == "record" ]]; then
  RECORDING_DIR="$(mktemp -d "$SNAPSHOT_ROOT/.recording.XXXXXX")"
else
  rm -rf "$FAILURE_DIR"
  mkdir -p "$FAILURE_DIR"
fi

count=0
failures=0
while IFS= read -r identifier; do
  (( count += 1 ))
  filename="$(snapshot_filename "$identifier")"
  reference="$SNAPSHOT_DIR/$filename"
  if [[ "$MODE" == "record" ]]; then
    actual="$RECORDING_DIR/$filename"
  else
    actual="$FAILURE_DIR/$filename"
  fi

  echo "[$count] $identifier"
  apply_status_bar_override
  launch_output=$(SIMCTL_CHILD_PROTECTED_ACTION_PRESENTATION_SNAPSHOT="$identifier" \
  SIMCTL_CHILD_AppleLanguages='(en)' \
  SIMCTL_CHILD_AppleLocale='en_US' \
    xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$BUNDLE_ID")
  pid="${launch_output##*: }"
  sleep "$CAPTURE_DELAY"
  if ! xcrun simctl spawn "$SIMULATOR_ID" launchctl procinfo "$pid" >/dev/null 2>&1; then
    echo "Snapshot app exited before capture: $identifier"
    exit 1
  fi
  if ! capture_stable_screenshot "$actual"; then
    echo "Snapshot did not reach a stable rendered frame: $identifier"
    exit 1
  fi

  if [[ "$MODE" == "verify" ]]; then
    if [[ ! -f "$reference" ]] || ! snapshots_match "$reference" "$actual"; then
      echo "  changed"
      (( failures += 1 ))
      if command -v magick >/dev/null && [[ -f "$reference" ]]; then
        magick compare -fuzz 1% "$reference" "$actual" "$FAILURE_DIR/${filename%.png}.diff.png" 2>/dev/null || true
      fi
    else
      rm "$actual"
    fi
  fi
done < <(snapshot_identifiers)

if [[ "$MODE" == "verify" && "$failures" -gt 0 ]]; then
  echo "$failures of $count snapshots changed. Actual images and diffs: $FAILURE_DIR"
  exit 1
fi

if [[ "$MODE" == "record" ]]; then
  find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name '*.png' -delete
  mv "$RECORDING_DIR"/*.png "$SNAPSHOT_DIR"/
  rmdir "$RECORDING_DIR"
  RECORDING_DIR=""
fi

TMP_GALLERY="$(mktemp)"
{
  echo '<!doctype html>'
  echo '<html lang="en"><head><meta charset="utf-8">'
  echo '<meta name="viewport" content="width=device-width,initial-scale=1">'
  echo '<title>Protected action presentation snapshots</title>'
  echo '<style>'
  echo 'body{margin:0;padding:32px;background:#111;color:#eee;font:14px -apple-system,BlinkMacSystemFont,sans-serif}'
  echo 'h1{margin:0 0 8px;font-size:28px}p{margin:0 0 32px;color:#aaa}'
  echo '.gallery{min-width:900px}'
  echo '.columns,.row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}'
  echo '.columns{position:sticky;top:0;z-index:1;margin-bottom:24px;padding:12px 0;background:#111e;color:#aaa;font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;backdrop-filter:blur(12px)}'
  echo '.flow{margin-bottom:36px}.flow-name{margin:0 0 12px;font-size:18px}'
  echo '.card{min-width:0;background:#1c1c1e;border:1px solid #333;border-radius:16px;padding:12px;box-shadow:0 8px 32px #0008}'
  echo '.card.empty{visibility:hidden}.name{padding:4px 4px 12px;font-weight:600;text-transform:capitalize}'
  echo 'img{display:block;width:100%;height:auto;border-radius:10px;background:#000}'
  echo '</style></head><body>'
  echo '<h1>Protected action presentations</h1>'
  echo '<p>Each row shows the full confirmation, compact MFA confirmation, and feature-owned completion in execution order.</p>'
  echo '<main class="gallery">'
  echo '<div class="columns"><div>Passcode</div><div>MFA</div><div>Success</div></div>'
  while IFS= read -r case_id; do
    echo "<section class=\"flow\"><h2 class=\"flow-name\">$case_id</h2><div class=\"row\">"
    for phase in passcode mfa success; do
      identifier="$case_id-$phase"
      if has_snapshot_identifier "$identifier"; then
        filename="$(snapshot_filename "$identifier")"
        echo "<article class=\"card\"><div class=\"name\">$phase</div><img loading=\"lazy\" src=\"__Snapshots__/ProtectedActionPresentationSnapshotTests/$filename\" alt=\"$case_id $phase\"></article>"
      else
        echo '<article class="card empty" aria-hidden="true"></article>'
      fi
    done
    echo '</div></section>'
  done < <(snapshot_case_ids)
  echo '</main></body></html>'
} > "$TMP_GALLERY"
mv "$TMP_GALLERY" "$GALLERY"

if [[ "$MODE" == "verify" ]]; then
  rmdir "$FAILURE_DIR" 2>/dev/null || true
fi
echo "$count snapshots $MODE complete."
echo "Snapshot gallery: $GALLERY"

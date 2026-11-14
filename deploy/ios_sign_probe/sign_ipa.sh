#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

for name in P12_PATH P12_PASSWORD_FILE TEAM_ID APP_PROFILE WIDGET_PROFILE NOTIFICATION_PROFILE ENTITLEMENTS_DIR RCODESIGN; do
  [ -n "${!name:-}" ] || fail "$name is not set"
done
[ "$#" -eq 2 ] || fail "usage: sign_ipa.sh <app.tar> <out.ipa>"

archive=$1
out="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# rcodesign reads only PKCS#12 with a SHA-1 MAC and PBES1 ciphers and reports any other scheme as a wrong
# password, so openssl, which reads them all, unpacks the signing identity into PEM first.
unpack() {
  openssl pkcs12 -in "$P12_PATH" -passin "file:$P12_PASSWORD_FILE" "$@" 2>/dev/null \
    || openssl pkcs12 -legacy -in "$P12_PATH" -passin "file:$P12_PASSWORD_FILE" "$@" 2>/dev/null
}
if ! { unpack -nocerts -nodes | openssl pkey -out "$work/key.pem" 2>/dev/null \
  && unpack -clcerts -nokeys | openssl x509 -out "$work/certificate.pem" 2>/dev/null; }; then
  fail "openssl cannot open $P12_PATH with the password in $P12_PASSWORD_FILE"
fi
openssl pkcs12 -info -noout -in "$P12_PATH" -passin "file:$P12_PASSWORD_FILE" 2>&1 | grep -E '^(MAC|PKCS7 Encrypted data):' || true

mkdir "$work/Payload"
tar -xf "$archive" -C "$work/Payload"
shopt -s nullglob
apps=("$work"/Payload/*.app)
[ "${#apps[@]}" -eq 1 ] || fail "expected exactly one .app in $archive, found ${#apps[@]}"
app=${apps[0]}

plist_value() {
  python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))[sys.argv[2]])' "$1" "$2"
}

sign_args=()
prepare() {
  local bundle=$1 profile=$2 source=$3 key=$4 scope=$5
  local executable identifier granted
  executable=$(plist_value "$bundle/Info.plist" CFBundleExecutable)
  [ -x "$bundle/$executable" ] || fail "$bundle/$executable is not executable after the artifact round trip"

  openssl smime -inform der -verify -noverify -in "$profile" -out "$work/$key.profile.plist"
  identifier=$(plist_value "$bundle/Info.plist" CFBundleIdentifier)
  granted=$(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["Entitlements"]["application-identifier"])' "$work/$key.profile.plist")
  [ "$granted" = "$TEAM_ID.$identifier" ] || fail "$profile is issued for $granted, not $TEAM_ID.$identifier"

  python3 "$here/merge_entitlements.py" "$ENTITLEMENTS_DIR/$source" "$work/$key.profile.plist" "$work/$key.entitlements.plist"
  cp "$profile" "$bundle/embedded.mobileprovision"
  if [ -z "$scope" ]; then
    sign_args+=(-e "$work/$key.entitlements.plist")
  else
    sign_args+=(-e "$scope:$work/$key.entitlements.plist")
  fi
  echo "$bundle/$executable" >> "$work/binaries"
}

prepare "$app" "$APP_PROFILE" MyTonWallet_Preview.entitlements app ""
found_widget='' found_notification=''
for extension in "$app"/PlugIns/*.appex; do
  scope="PlugIns/$(basename "$extension")"
  case "$(plist_value "$extension/Info.plist" CFBundleIdentifier)" in
    *.AirWidget)
      prepare "$extension" "$WIDGET_PROFILE" AirWidgetExtension_Preview.entitlements widget "$scope"
      found_widget=1
      ;;
    *.notification-service)
      prepare "$extension" "$NOTIFICATION_PROFILE" MyTonWalletNotificationServiceExtension_Preview.entitlements notification "$scope"
      found_notification=1
      ;;
    *) fail "no signing setup for extension $scope" ;;
  esac
done
[ -n "$found_widget" ] && [ -n "$found_notification" ] || fail "the app lacks its widget or notification extension"

"$RCODESIGN" sign --pem-file "$work/key.pem" --pem-file "$work/certificate.pem" --team-name "$TEAM_ID" \
  --timestamp-url none "${sign_args[@]}" "$app"
while read -r binary; do
  "$RCODESIGN" print-signature-info "$binary"
done < "$work/binaries"

rm -f "$out"
(cd "$work" && zip -qry "$out" Payload)
echo "signed $(basename "$app") into $out"

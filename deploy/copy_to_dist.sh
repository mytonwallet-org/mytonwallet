#!/usr/bin/env bash

DESTINATION=${1:-"dist"}
SOURCE=${2:-"public"}

cp -R ./$SOURCE/* "$DESTINATION/"

cp ./src/lib/rlottie/rlottie-wasm.js "$DESTINATION/"
cp ./src/lib/rlottie/rlottie-wasm.wasm "$DESTINATION/"

FILES_TO_REMOVE=("static-sites")

if [ "$IS_EXTENSION" = "1" ] || [ "$IS_PACKAGED_ELECTRON" = "1" ]; then
    FILES_TO_REMOVE+=("get" "_headers" "_headers_telegram" "_redirects")
fi

if [ "$IS_EXTENSION" = "1" ]; then
    FILES_TO_REMOVE+=("site.webmanifest")
fi

if [ "$IS_GRAM_WALLET" = "1" ]; then
   # Any Gram-branded build (pure gram, the wallet.ton.org combo, and any future Gram mobile bundle) ships
   # gramWallet/ assets only. Brand asset retention keys on brand alone; platform axes must not gate it, or a
   # Gram build off the else-branch would strip its own gramWallet/ dir that runtime code (QR logo, manifest) needs.
   FILES_TO_REMOVE+=("apple-touch-icon.png" "browserconfig.xml" "favicon.ico" "icon*" "logo.svg" "mstile*" "site.webmanifest" "coreWallet*" "core_wallet*" "assets/ui/about.txt")
   sed -i.bak 's#https://get.mytonwallet.io#https://get.gramwallet.io#' "$DESTINATION/_redirects" && rm -f "$DESTINATION/_redirects.bak"
elif [ "$IS_CORE_WALLET" = "1" ]; then
   FILES_TO_REMOVE+=("apple-touch-icon.png" "browserconfig.xml" "favicon.ico" "icon*" "logo.svg" "mstile*" "site.webmanifest" "gramWallet*" "gram_wallet*" "assets/ui/about.txt")
else
   FILES_TO_REMOVE+=("coreWallet*" "core_wallet*" "gramWallet*" "gram_wallet*" "assets/")
fi

if [ "$IS_PACKAGED_ELECTRON" != "1" ]; then
    FILES_TO_REMOVE+=("background-electron-dmg.tiff" "electron-entitlements.mac.plist" "icon-electron-*")
fi

for FILE in "${FILES_TO_REMOVE[@]}"; do
    rm -rf $DESTINATION/$FILE
done

# Both Telegram Mini App hosts (production tma.* and staging tma-beta.*) stay out of search: a TMA
# opens inside Telegram, not via crawlers. Telegram builds ship their webpack headers as
# `_headers_telegram`, a name Netlify does not process, so this `_headers` is the only header file
# Netlify applies. The default `dist` destination is the TMA build; the push and mfa bundles pass
# their own dist-push and dist-mfa destinations, so they are left untouched.
if [ "$IS_TELEGRAM_APP" = "1" ] && [ "$DESTINATION" = "dist" ]; then
    HEADERS_FILE="$DESTINATION/_headers"
    # Append only if absent: copy_to_dist may run against a reused dist, and a bare `>>` would
    # stack duplicate `/*` blocks on every rerun. Separate from any existing block with a blank line.
    if ! grep -q 'X-Robots-Tag: noindex' "$HEADERS_FILE" 2>/dev/null; then
        [ -s "$HEADERS_FILE" ] && printf '\n' >> "$HEADERS_FILE"
        printf '/*\n  X-Robots-Tag: noindex\n' >> "$HEADERS_FILE"
    fi
fi

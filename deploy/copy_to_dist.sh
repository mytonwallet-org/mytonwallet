#!/usr/bin/env bash

DESTINATION=${1:-"dist"}
SOURCE=${2:-"public"}

cp -R ./$SOURCE/* "$DESTINATION/"

FILES_TO_REMOVE=("static-sites")

if [ "$IS_EXTENSION" = "1" ] || [ "$IS_PACKAGED_ELECTRON" = "1" ]; then
    FILES_TO_REMOVE+=("get" "_headers" "_redirects")
fi

if [ "$IS_EXTENSION" = "1" ]; then
    FILES_TO_REMOVE+=("site.webmanifest")
fi

if [ "$IS_GRAM_WALLET" = "1" ]; then
   # Any Gram-branded build (web and any future Gram mobile bundle) ships gramWallet/ assets only. Brand asset
   # retention keys on brand alone; platform axes must not gate it, or a Gram build off the else-branch would
   # strip its own gramWallet/ dir that runtime code (QR logo, manifest) needs.
   FILES_TO_REMOVE+=("apple-touch-icon.png" "browserconfig.xml" "favicon.ico" "icon*" "logo.svg" "mstile*" "site.webmanifest" "assets/ui/about.txt")
   sed -i.bak 's#https://get.mytonwallet.io#https://get.gramwallet.io#' "$DESTINATION/_redirects" && rm -f "$DESTINATION/_redirects.bak"
else
   FILES_TO_REMOVE+=("gramWallet*" "gram_wallet*" "assets/")
fi

if [ "$IS_PACKAGED_ELECTRON" != "1" ]; then
    FILES_TO_REMOVE+=("background-electron-dmg.tiff" "electron-entitlements.mac.plist" "icon-electron-*")
fi

for FILE in "${FILES_TO_REMOVE[@]}"; do
    rm -rf $DESTINATION/$FILE
done

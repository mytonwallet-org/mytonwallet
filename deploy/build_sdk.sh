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

echo "SDK build completed and copied to mobile platforms"

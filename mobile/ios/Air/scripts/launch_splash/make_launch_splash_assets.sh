#!/bin/bash
# Regenerates the launch ribbon pieces and the static launch screen image from AppIcon.icon.
# Run after changing the icon or Air/SubModules/AirAsFramework/Root/LaunchSplashGeometry.swift;
# it prints the measured trim extents to paste into LaunchSplashGeometry.pieces.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$SCRIPT_DIR/../../.."
GEOMETRY="$IOS_DIR/Air/SubModules/AirAsFramework/Root/LaunchSplashGeometry.swift"
ICON_ASSETS="$IOS_DIR/App/App/Resources/MyTonWallet/AppIcon.icon/Assets"
CATALOG="$IOS_DIR/App/App/Resources/MyTonWallet/Assets.xcassets"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Top-level code must live in main.swift when compiling several files.
cp "$SCRIPT_DIR/make_launch_splash_assets.swift" "$BUILD_DIR/main.swift"
xcrun --sdk macosx swiftc -O "$GEOMETRY" "$BUILD_DIR/main.swift" -o "$BUILD_DIR/make_assets"
"$BUILD_DIR/make_assets" "$ICON_ASSETS" "$CATALOG"

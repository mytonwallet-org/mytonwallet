# Gram Wallet iOS App Variant

Status: native iOS target work started on 2026-04-21.

This document tracks the technical work needed to ship Gram Wallet as a second iOS App Store app alongside MyTonWallet. App Review positioning is intentionally out of scope here.

## Goals

- Build Gram Wallet from the same codebase as MyTonWallet.
- Keep behavior identical at launch except variant identity and branding.
- Allow both apps to be installed on the same device without sharing private user state by accident.
- Extend GitHub CI and fastlane later so both iOS apps can be built and deployed predictably.

## Current State

- [x] iOS app lives in `mobile/ios/App` with shared native modules in `mobile/ios/Air`.
- [x] Existing iOS schemes are `MyTonWallet`, `MyTonWallet_NoExtensions`, `MyTonWallet_AirOnly`, and `AirWidgetExtension`.
- [x] Existing production bundle ID is `org.mytonwallet.app`; widget bundle ID is `org.mytonwallet.app.AirWidget`.
- [x] Gram app name is `Gram Wallet`; app bundle ID is `io.gramwallet.app`.
- [x] Gram widget bundle ID is `io.gramwallet.app.widget`; app group is `group.io.gramwallet.app`.
- [x] Native display name, URL schemes, app group, Firebase plist, fastlane profiles, and several Swift constants are MyTonWallet-specific.
- [x] CI release workflow is `.github/workflows/package-and-publish.yml`; iOS release uses `npm run mobile:build:*`, installs one app profile and one widget profile, then runs `bundle exec fastlane beta` or `bundle exec fastlane release`.

## Implementation Checklist

### App Variant Model

- [x] Add `IS_GRAM_WALLET` alongside `IS_CORE_WALLET` in TypeScript config.
- [x] Keep `IS_CORE_WALLET` separate; Gram Wallet is an app variant, not the TON Wallet/Core variant.
- [ ] Centralize variant values: app name, bundle IDs, URL schemes, universal link hosts, app group ID, Firebase plist name, icon names, support URLs, privacy URLs, feature flags, defaults, and TonConnect metadata.
- [x] Make iOS Air SDK TypeScript values such as `APP_NAME`, WalletConnect metadata, and TonConnect deeplink URLs variant-aware.
- [x] Make Swift config in `mobile/ios/Air/SubModules/WalletContext/Config.swift` variant-aware for native app name, biometric username, self scheme, and TonConnect scheme.

### Air SDK

- [x] Generate separate SDK bundles: `mytonwallet-sdk.js` and `gramwallet-sdk.js`.
- [x] Compile the Gram SDK with `IS_GRAM_WALLET=1`; TypeScript config now consumes the flag for app identity, deeplinks, and dApp metadata.
- [x] Load `gramwallet-sdk.js` from the Gram iOS target through `index-gramwallet.html`.
- [ ] Decide whether Android needs a Gram target before wiring its loader to `gramwallet-sdk.js`.

### iOS Project

- [x] Add a `GramWallet` app target and shared `GramWallet` scheme.
- [x] Add a `GramWalletWidgetExtension` target and shared widget scheme.
- [x] Use target build settings for `PRODUCT_BUNDLE_IDENTIFIER`, display name, app icon, entitlements, and plist path.
- [ ] Add Gram bundle IDs in Apple Developer:
  - app: `io.gramwallet.app`
  - widget: `io.gramwallet.app.widget`
- [x] Add Gram entitlements in the project:
  - APNs
  - Associated Domains
  - App Group: `group.io.gramwallet.app`
- [x] Add Gram app icon in `mobile/ios/App/App/Resources/GramWalletIcon.icon`.
- [x] Add Gram fallback app icon in `mobile/ios/App/App/Resources/Assets.xcassets/GramWalletIcon.appiconset`.
- [x] Reuse existing widget assets for the first native target pass.
- [x] Add a Gram `GoogleService-Info.plist` and include the correct plist per target.
- [x] Add Firebase SwiftPM products to the no-Pods app targets:
  - `MyTonWallet_AirOnly`
  - `GramWallet`
- [x] Keep legacy Pods-backed targets on `FirebaseMessaging` pod `11.15.0` to avoid duplicate Google/Firebase transitive libraries while those targets still use CocoaPods.
- [x] Update hardcoded app group usage in:
  - `mobile/ios/App/AirWidget/Models/WidgetSupport.swift`
  - widget entitlements
  - app entitlements
- [x] Update hardcoded shortcut type in `mobile/ios/App/App/Classes/HomeScreenQuickAction.swift`.

### State Isolation

- [ ] Confirm keychain behavior for the new bundle ID. Current native keychain storage uses service name `cap_sec` without an explicit access group, so data should be app-isolated by default.
- [ ] Do not add a shared keychain access group unless account migration/sharing is explicitly required.
- [ ] Keep `UserDefaults.standard`, WKWebView data, documents, and SQLite stores isolated by bundle ID.
- [x] Use separate app group containers for widgets so MyTonWallet and Gram Wallet widgets do not read each other's cached balances.
- [ ] Decide whether existing MyTonWallet users should be offered migration into Gram Wallet. If yes, design an explicit export/import or shared access flow instead of implicit state sharing.

### Deeplinks and Web Identity

- [x] Configure Gram-specific custom schemes: `gramwallet://` and `gramwallet-tc://`.
- [ ] Decide whether Gram claims shared schemes such as `ton`, `tc`, and `wc`; test install-order behavior on device.
- [x] Add Gram-specific TonConnect scheme `gramwallet-tc://`.
- [ ] Add Gram universal link domain `gramwallet.io` and update server-side AASA files.
- [x] Update Swift deeplink allow-lists in `mobile/ios/Air/SubModules/UIBrowser/ExploreTab/ExploreTabVC.swift`.
- [x] Make in-app browser TonConnect and WalletConnect/Solana provider injection variant-aware for Gram Wallet identity.
- [x] Update TypeScript deeplink constants in `src/util/deeplink/constants.ts` for Gram custom schemes and universal links.
- [x] Route Gram TonConnect universal links through `https://gramwallet.io/tonconnect` in native parser and Air SDK deeplink handling.
- [x] Make WalletConnect relay metadata variant-aware for the iOS Air SDK.
- [ ] Update TonConnect wallet metadata, wallet list entries, and manifest URLs outside the app bundle as needed.

### CI and Deployment

- [x] Parameterize iOS fastlane variables in `mobile/ios/App/fastlane/Fastfile` instead of hardcoding:
  - scheme
  - app identifier
  - widget identifier
  - provisioning profile names
  - TestFlight group
  - metadata path
- [x] Pass `APP_VARIANT=gram` into the existing fastlane lanes for Gram releases.
- [ ] Add GitHub secrets/vars for Gram:
  - `IOS_GRAM_PROVISION_PROFILE_BASE64`
  - `IOS_GRAM_PROVISION_PROFILE_WIDGET_BASE64`
  - `IOS_GRAM_CERTIFICATE_BASE64` and password if not reusing the current distribution certificate
  - `IOS_GRAM_AUTH_KEY_BASE64` if App Store Connect credentials differ
  - optional if App Store Connect credentials differ: `IOS_GRAM_AUTH_KEY_ID`, `IOS_GRAM_AUTH_KEY_ISSUER_ID`
  - optional if the TestFlight group differs from the default: `IOS_GRAM_TESTFLIGHT_GROUP`
- [x] Update `.github/workflows/package-and-publish.yml` to build both iOS variants through a matrix.
- [x] Add `workflow_dispatch` input for iOS variant selection.
- [x] Pass variant env through CI release steps; SDK generation builds both Air variants in one `npm run mobile:build:sdk` run.
- [x] Avoid running `cap sync ios` for the Gram release job; Gram uses the native Air target and only needs the Air SDK/localization build.
- [ ] Update CI only if release jobs need to resolve SwiftPM packages or cache Firebase SPM artifacts explicitly.
- [ ] Upload or publish Gram TestFlight/App Store builds through the correct App Store Connect app record.

### Verification

- [ ] Build MyTonWallet after introducing variants:
  - `CAP_PLATFORM=ios npm run mobile:build` currently still fails with `EMFILE: too many open files, watch`
  - `WEBPACK_SERVE=false CAP_PLATFORM=ios npm run mobile:build` succeeded before native target work
  - `xcodebuild -workspace /Users/nikstar/mywallet/gram/mobile/ios/App/App.xcworkspace -scheme MyTonWallet_AirOnly -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/GramWalletDerived CODE_SIGNING_ALLOWED=NO build` succeeded after Firebase SPM migration
- [x] Build Gram Wallet locally with the new scheme:
  - `xcodebuild -workspace /Users/nikstar/mywallet/gram/mobile/ios/App/App.xcworkspace -scheme GramWallet -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/GramWalletDerivedOnly CODE_SIGNING_ALLOWED=NO build` succeeded after Firebase SPM migration
  - `xcodebuild -workspace mobile/ios/App/App.xcworkspace -scheme GramWallet -configuration Debug -destination 'generic/platform=iOS Simulator' build | xcbeautify -q` succeeded after in-app browser provider identity changes
  - `xcodebuild -workspace mobile/ios/App/App.xcworkspace -scheme GramWallet -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/GramWalletTonConnectDerived CODE_SIGNING_ALLOWED=NO build | xcbeautify -q` succeeded after TypeScript and native TonConnect/WalletConnect identity changes
- [x] Build MyTonWallet AirOnly after shared TonConnect/WalletConnect changes:
  - `xcodebuild -workspace mobile/ios/App/App.xcworkspace -scheme MyTonWallet_AirOnly -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/MyTonWalletAirTonConnectDerived CODE_SIGNING_ALLOWED=NO build | xcbeautify -q` succeeded
- [x] Build affected in-app browser module:
  - `xcodebuild -workspace mobile/ios/App/App.xcworkspace -scheme UIInAppBrowser -configuration Debug -destination 'generic/platform=iOS Simulator' build | xcbeautify -q` succeeded after provider injection changes
- [x] Type-check and lint TypeScript variant changes:
  - `npx tsc --noEmit` succeeded
  - `npx eslint src/config.ts src/util/deeplink/constants.ts src/api/dappProtocols/adapters/walletConnect/index.ts` succeeded
- [x] Rebuild Air SDK bundles:
  - `npm run mobile:build:sdk` succeeded; webpack reported only SDK size warnings
- [x] Build the Pods-backed app target after Firebase split:
  - `xcodebuild -workspace /Users/nikstar/mywallet/gram/mobile/ios/App/App.xcworkspace -scheme MyTonWallet_NoExtensions -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/NoExtensionsFirebaseDerived2 CODE_SIGNING_ALLOWED=NO build` succeeded after keeping Firebase pod-scoped to legacy targets
- [ ] Install both apps on one device and verify separate app data, keychain, widgets, push tokens, and deeplink behavior.
- [ ] Verify Firebase Messaging token registration for both apps.
- [ ] Verify TestFlight upload for Gram Wallet from CI.
- [ ] Verify MyTonWallet CI output remains unchanged.

## Open Technical Decisions

- Gram App Store provisioning profiles and Apple Developer identifiers for `io.gramwallet.app`, `io.gramwallet.app.widget`, and `group.io.gramwallet.app`.
- Gram Firebase plist and push project setup.
- Whether legacy Pods-backed targets should keep the pinned Firebase pod long term or move to SPM after CocoaPods is removed from those targets.
- Whether Gram Wallet uses unique universal links or shares existing MyTonWallet links.
- Whether wallet/account migration between apps is required.
- Whether App Store metadata and screenshots live in fastlane metadata folders or stay managed manually in App Store Connect.
- Whether CI should always release both iOS apps from `master` or allow per-variant release dispatch.

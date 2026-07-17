# MyTonWallet Air iOS

Air is the native iOS UI for MyTonWallet. It lives in the monorepo and uses the shared TypeScript SDK through a hidden WebView bridge.

The iOS app shell always launches Air; the former Capacitor/Classic switching path is no longer part of the native app.

## Build

Use the workspace in `mobile/ios/App`, not the Air project directly.

From the repository root, refresh SDK and iOS app artifacts when needed:

```bash
npm run mobile:build:dev
```

For a full app build:

```bash
xcodebuild -workspace mobile/ios/App/App.xcworkspace -scheme MyTonWallet_AirOnly -configuration Debug -destination 'generic/platform=iOS Simulator' build | xcbeautify
```

Do not pass `-sdk iphonesimulator` to this workspace.

## Structure

- `SubModules/` contains Air native modules. Feature UI code lives mostly in `UI*` modules, shared infrastructure in `WalletCore`, `WalletContext`, and `UIComponents`.
- `WalletCore/JSWebViewBridge` hosts the TypeScript SDK and routes Swift API calls and SDK updates.
- `notes/` contains working notes, old plans, audit outputs, diagrams, and scratchpad material. Treat it as non-canonical unless a note is explicitly promoted.
- Durable platform documentation lives in `docs/technical/platforms/ios.md`.

## References

- [iOS platform overview](../../../docs/technical/platforms/ios.md)
- [Submodule notes](notes/submodules.md)
- [Bridge notes](notes/js-bridge.md)

<img src="notes/screenshot.png" alt="Application Screenshot" width="320" style="border-radius: 16px;"/>

# Air iOS — Technical Summary

The iOS Air app is a fully-native wallet with a **UIKit + SwiftUI hybrid** UI and an **invisible WebView** running the TypeScript SDK for all blockchain logic.

**Deployment target:** iOS 16.0+
**Project:** `mobile/ios/MyTonWalletAir.xcodeproj` (integrated into `App/App.xcworkspace`)

---

## Architecture

### Pattern: MVVM + MVP Hybrid

- **ViewControllers** (`*VC`) — UIKit-based, inherit from `WViewController`
- **ViewModels** (`*VM`, `*Model`) — observable state holders using `@Perceptible` macro
- **Stores** — singleton data holders (`AccountStore`, `TokenStore`, `NftStore`, `BalanceStore`, etc.) with `UnfairLock` thread safety
- **Event System** — `WalletCoreData.EventsObserver` pub/sub for state propagation

### Module Structure (24 modules, ~730 Swift files)

```
mobile/ios/Air/SubModules/
├── AirAsFramework/       # App bootstrap, deeplink handler, root navigation
├── WalletCore/           # WebView bridge, API layer, stores, event system (175 files)
├── WalletContext/        # Theme, localization, keychain, global storage (49 files)
│
├── UIHome/               # Home tab, dashboard, wallet cards, balance
├── UIAssets/             # Token list, NFT gallery, collections
├── UISettings/           # Settings, security, appearance, language, recovery
├── UIComponents/         # Reusable widgets: buttons, lists, charts, animations (191 files)
├── UISend/               # Send flow: compose → confirm → sending → result
├── UISwap/               # Swap UI: token selection, confirm, cross-chain
├── UIEarn/               # Staking: pools, add/claim/unstake
├── UIBrowser/            # Explore tab, curated DApp listings
├── UIInAppBrowser/       # Embedded browser, minimizable sheet
├── UIDapp/               # TonConnect/WalletConnect: approvals, signing
├── UICreateWallet/       # Onboarding: intro, mnemonic backup/verify, import
├── UIPasscode/           # Passcode setup, unlock, biometric auth
├── UIQRScan/             # QR scanner with camera
├── UIReceive/            # Receive addresses, QR, share
├── UIToken/              # Token detail with chart and activity
├── UITransaction/        # Activity list, transaction detail
│
├── Ledger/               # Hardware wallet via BLE
├── WReachability/        # Network monitoring
├── RLottieBinding/       # Telegram animation engine (C++)
├── GZip/                 # Compression (C)
└── YUVConversion/        # Video color space (C)
```

---

## WebView Bridge

### Setup

A 1×1 invisible `WKWebView` (`JSWebViewBridge`) loads a pre-bundled `index.html` containing the webpack-compiled TypeScript SDK.

### Communication Protocol

**Swift → JavaScript (API calls):**
```swift
let result = try await Api.importMnemonic(networks, mnemonic, password)
// → callAsyncJavaScript("window.airBridge.callApi('importMnemonic', ...)")
// → JS SDK executes, Promise resolves
// → Result decoded to Swift types
```

**JavaScript → Swift (updates):**
```
window.webkit.messageHandlers.onUpdate.postMessage(JSON.stringify(update))
  → WalletCoreData.notify(event:) → all EventsObservers
```

**JavaScript → Swift (native calls):**
```
window.webkit.messageHandlers.nativeCall.postMessage(...)
  → Keychain: capacitorStorageGetItem/SetItem/RemoveItem/Keys
  → Ledger: exchangeWithLedger(apdu), getLedgerDeviceModel()
```

Errors are caught in JS, serialized to JSON, and rethrown as `BridgeCallError` with stack traces.

---

## Navigation

```
RootStateCoordinator (singleton)
  └─ RootHostVC → RootContainerVC
      ├─ HomeTabBarController (phone) — 3 tabs:
      │   ├─ Tab 0: HomeVC (WNavigationController)
      │   ├─ Tab 1: ExploreTabVC (WNavigationController)
      │   └─ Tab 2: SettingsVC (WNavigationController)
      ├─ SplitRootViewController (iPad, 700+ width)
      │   ├─ Sidebar: Home/Explore
      │   └─ Detail pane
      └─ MinimizableSheetContainerViewController
          └─ InAppBrowser (collapsible to 44pt pill)
```

Push/pop navigation via `WNavigationController`. Modals via `present()`. Deep links (`ton://`, `tc://`, `wc://`, `mtw://`) parsed by `DeeplinkHandler` and routed through `RootContainerRouting`.

---

## State Management

### Three-Tier Storage

| Tier             | Backing                   | Purpose                                                    |
|------------------|---------------------------|------------------------------------------------------------|
| Keychain         | Secure Enclave            | Wallet accounts, biometric passcode, private keys          |
| GlobalStorage    | WKWebView `localStorage`  | Settings, cached activities, token lists (shared with web) |
| In-Memory Stores | `@Perceptible` singletons | Live UI state, populated from cache + SDK events           |

### Event-Driven Updates

1. JS SDK emits update via `onUpdate` message handler
2. `WalletCoreData` decodes and dispatches typed `WalletEvent`
3. Stores update cached data
4. ViewModels (registered as `EventsObserver`) receive callbacks
5. ViewModels call delegate methods on ViewControllers
6. UI refreshes

---

## Theme System

- `WTheme` singleton with semantic colors: `tint`, `label`, `background`, etc.
- Light/Dark/System modes
- Per-account accent colors (from NFT selection)
- All themed views implement `updateTheme()` callback

---

## Dependencies

**SPM:**
- `GRDB` — SQLite for account persistence
- `Kingfisher` — image caching/loading
- `OrderedCollections` — ordered dictionaries
- `Dependencies` — DI container
- `Perception` — `@Perceptible` reactive framework
- `BleTransport` — Ledger BLE communication

**CocoaPods (via workspace):**
- Capacitor plugins (shared workspace)
- Firebase Messaging (push notifications)

No native networking libraries — all API calls go through the WebView bridge.

---

## Native Capabilities

| Capability         | Implementation                                                  |
|--------------------|-----------------------------------------------------------------|
| Biometrics         | `LAContext` (Face ID / Touch ID)                                |
| Keychain           | Secure Enclave via `KeychainHelper`                             |
| Bluetooth          | `CoreBluetooth` for Ledger HW wallet                            |
| Push notifications | `UserNotifications` + Firebase Cloud Messaging                  |
| Camera/QR          | `AVFoundation` with custom decoder                              |
| Pasteboard         | Copy with 180s expiry, `.localOnly` isolation                   |
| Persistence        | GRDB SQLite at `~/Library/Application Support/air/db/db.sqlite` |
| Animations         | RLottie (C++ binding) for Telegram stickers                     |
| Network monitoring | `Network.framework` via `WReachability`                         |

---

## Security

- **Private keys**: encrypted in Keychain (Secure Enclave), never exposed to WebView memory; accessed only during signing via `capacitorStorageGetItem` callback
- **Mnemonics**: entered during import, never stored in app, verified via word selection test
- **Transaction signing**: performed by JS SDK, user confirms in native UI first
- **App lock**: triggered on background, configurable timeout
- **Clipboard**: 180s expiry, local-only isolation
- **Deep links**: strict scheme validation, TonConnect/WalletConnect require user approval

# Air Android — Technical Summary

The Android Air app is a fully-native wallet with a **custom UIKit-style view framework** (not Jetpack Compose) and an **invisible WebView** running the TypeScript SDK for all blockchain logic.

**Min SDK:** 23 · **Target SDK:** 34 · **Compile SDK:** 35
**Project:** `mobile/android/air/` (Gradle subproject of `mobile/android/`)

---

## Architecture

### Pattern: MVP with Custom ViewController Framework

A custom framework mirrors the iOS UIKit approach:

- **`WWindow`** (`AppCompatActivity`) — single-activity container
- **`WNavigationController`** — stack-based push/pop navigation
- **`WViewController`** (`*VC`) — screen/fragment-like view controller
- **`*VM`** — presenter/viewmodel with `WalletCore.EventObserver`
- **Delegate interfaces** — VM → VC callbacks for UI updates

```
HomeVC implements HomeVM.Delegate
  └─ HomeVM extends WalletCore.EventObserver
     └─ Receives WalletEvent updates
     └─ Calls delegate: update(), updateBalance(), reloadCard()
```

### Module Structure (28 modules)

```
mobile/android/air/
├── app/                      # Main app module (MTWAirApplication)
├── AirAsFramework/           # MainWindow Activity, SplashVC, widget config
├── WalletCore/               # JS WebView bridge, API calls, stores, push
├── WalletContext/            # Global/cache/secure storage, helpers
├── WalletBaseContext/        # Base utilities
├── WalletNative/             # NDK C/C++ code (CMake, NDK 27.3)
│
├── UIComponents/             # Base widgets, drawables, common views
├── UIHome/                   # Home tab, wallet cards, activity list
├── UICreateWallet/           # Onboarding flow
├── UIPasscode/               # PIN entry, biometric unlock
├── UISend/                   # Send transaction
├── UIReceive/                # Receive address, QR
├── UIAssets/                 # Token and NFT browsing
├── UIToken/                  # Token detail with chart
├── UIBrowser/                # Explore / DApp browser
├── UIInAppBrowser/           # In-app WebView browser
├── UISettings/               # Settings screens
├── UIStake/                  # Staking UI
├── UISwap/                   # Swap / exchange
├── UITransaction/            # Transaction detail / history
├── UITonConnect/             # TonConnect 2.0 DApp integration
├── UIWidgets/                # Home screen widgets
├── UIWidgetsConfigurations/  # Widget management
├── QRScan/                   # QR scanner (ML Kit + Camera)
├── Icons/                    # Icon resources
│
├── Ledger/                   # Hardware wallet integration
├── OverScroll/               # Custom scroll behavior
└── vkryl/
    ├── core/                 # Core utilities (strings, colors, math, futures)
    └── android/              # Android utilities (storage, SDK compat, animators)
```

---

## WebView Bridge

### Setup

`JSWebViewBridge` loads `file:///android_asset/js/index.html` at startup. The JS SDK runs inside an invisible WebView. Communication uses `@JavascriptInterface` annotation on `JsWebInterface`.

### Communication Protocol

**Native → JavaScript (API calls):**
```kotlin
WalletCore.call(ApiMethod.Transfer(address, amount)) { result, error ->
    // evaluateJavascript("window.airBridge.callApi('transfer', ...)")
    // JS SDK executes, callback invoked with result
}
```

**JavaScript → Native (callbacks):**
```javascript
androidApp.callback(identifier, success, resultJson)
// → Handler.post { callbacks[identifier]?.invoke(result, error) }
```

**JavaScript → Native (updates):**
```javascript
androidApp.onUpdate(JSON.stringify(updateObject))
// → JsWebInterface.onUpdate() → Store update → WalletCore.notifyEvent()
```

### Update Types

`updateBalances` · `updatingStatus` · `updateTokens` · `newLocalActivities` · `newActivities` · `updateStaking` · `updateNfts` · `updateSwapTokens`

### Type Safety

API methods defined in `moshi/api/ApiMethod.kt` with Moshi code generation (KSP) for JSON serialization/deserialization.

---

## Navigation

Single-activity architecture (`MainWindow` extends `WWindow`):

```
MainWindow (AppCompatActivity)
  └─ WNavigationController (stack-based)
     ├─ push(ViewController)
     ├─ pop()
     ├─ popToRoot()
     └─ setRoot(ViewController)
```

Deep links processed in `SplashVC` at startup, routed to appropriate screens.

---

## UI Framework

**Not Jetpack Compose.** Custom programmatic Android views:

- `WView` — base container (ConstraintLayout)
- `WCell` — reusable row component
- `WRecyclerViewAdapter` — custom list adapter
- `WNavigationBar` — top navigation bar
- `WPopupHost` — modal/dialog host

Layouts constructed programmatically in Kotlin (not XML). Fresco for image loading. Lottie for animations. MPAndroidChart for price charts.

### Theme System

- `ThemeManager` — light/dark/system modes
- Per-account accent colors (from NFT selection)
- Views implement `WThemedView` interface

---

## State Management

### Event-Driven Observer Pattern

```kotlin
object WalletCore {
    interface EventObserver {
        fun onWalletEvent(walletEvent: WalletEvent)
    }
    fun registerObserver(observer: EventObserver)
    fun notifyEvent(walletEvent: WalletEvent)
}
```

Events: `AccountChanged` · `BalanceChanged` · `TokensChanged` · `NetworkConnected` · `ReceivedPendingActivities` · `CollectionNftsReceived` · `StakingDataUpdated`

### Three-Tier Storage

| Tier          | Backing                             | Purpose                                                 |
|---------------|-------------------------------------|---------------------------------------------------------|
| SecureStorage | Encrypted SharedPreferences         | Biometric passcode, private keys, failed login tracking |
| GlobalStorage | Custom provider (`WGlobalStorage`)  | Settings, account metadata, schema migrations           |
| CacheStorage  | SharedPreferences (`WCacheStorage`) | Tokens, NFTs, staking, explore history (per-account)    |

### Stores (In-Memory Singletons)

`AccountStore` · `ActivityStore` · `AddressStore` · `AuthStore` · `BalanceStore` · `ConfigStore` · `DappsStore` · `ExploreHistoryStore` · `NftStore` · `StakingStore` · `TokenStore`

Populated from cache on startup, updated by SDK events in real time.

---

## Data Models

Moshi-serialized classes with KSP code generation:

```kotlin
MAccount         // accountId, name, icon, type (mnemonic/privKey/ledger/viewOnly)
MToken           // slug, address, symbol, decimals, balance
MBlockchain      // enum: ton, tron, solana
MBlockchainNetwork // enum: mainnet, testnet
ApiNft           // address, collection, collectionName, owner
MApiTransaction  // transaction data
ApiMethod.*      // type-safe API call definitions
ApiUpdate        // push updates from SDK
```

---

## Dependencies

**AndroidX:** core-ktx, appcompat, activity, constraintlayout, biometric, lifecycle, camera, webkit, work-runtime, browser, palette
**UI:** Material Design, Fresco (images), Lottie (animations), BlurView, MPAndroidChart
**Serialization:** Moshi (core + kotlin + adapters + codegen via KSP)
**Vision:** ML Kit barcode scanning, ZXing, CameraX
**Firebase:** Cloud Messaging (push notifications)
**Kotlin:** 2.2.0, coroutines
**Build:** Gradle 8.11.1, AGP, Google Services

No native HTTP/networking libraries — all API calls go through the WebView bridge.

---

## Native Capabilities

| Capability                 | Implementation                                    |
|----------------------------|---------------------------------------------------|
| Biometrics                 | `androidx.biometric` library                      |
| Secure storage             | Encrypted SharedPreferences                       |
| Push notifications         | Firebase Cloud Messaging (`AirPushNotifications`) |
| Camera/QR                  | CameraX + ML Kit barcode scanning                 |
| Hardware wallet            | Ledger module (BLE)                               |
| App lock                   | `AutoLockHelper` with configurable timeout        |
| Screen recording detection | `DETECT_SCREEN_RECORDING` permission              |
| Native code                | NDK 27.3, CMake, `libhash-utils.so`               |
| Network monitoring         | `ConnectivityManager`                             |
| Home screen widgets        | `UIWidgets` + `UIWidgetsConfigurations` modules   |

---

## Build Configuration

```
Kotlin: 2.2.0
AGP: 8.11.1
compileSdk: 35 / minSdk: 23 / targetSdk: 34
NDK: 27.3.13750724
JVM target: 1.8
Version: 0.7.0 (code: 17)
Package: org.mytonwallet.app
```

Build types: Debug (unminified) and Release (ProGuard minification for app module).

Version catalog at `mobile/android/gradle/libs.versions.toml`.

---

## Security

- **Private keys**: encrypted in SecureStorage, accessed only during signing via WebView bridge callback
- **Biometrics**: `NativeBiometric` helper with attempt limiting
- **App lock**: auto-lock on background with configurable timeout
- **Screen recording**: detection permission for sensitive screens
- **Deep links**: validated and routed only to recognized schemes
- **DApp transactions**: require explicit user approval in native UI before JS SDK signs

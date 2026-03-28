# MyTonWallet — Technical Architecture Overview

MyTonWallet is a multi-platform cryptocurrency wallet supporting **TON**, **TRON**, and **Solana** blockchains. The architecture is split into two layers: a shared **TypeScript SDK** for all blockchain logic, and **platform-specific UI** implementations.

---

## Platform Map

| Platform                                     | UI Layer                     | SDK Transport             | Detailed Docs                              |
|----------------------------------------------|------------------------------|---------------------------|--------------------------------------------|
| **Web**                                      | Teact (TypeScript)           | Web Worker                | [classic.md](platforms/classic.md)         |
| **Electron** (Win/Mac/Linux)                 | Teact (TypeScript)           | Web Worker                | [classic.md](platforms/classic.md)         |
| **Browser Extension** (Chrome/Firefox/Opera) | Teact (TypeScript)           | Extension Service Worker  | [classic.md](platforms/classic.md)         |
| **Telegram Mini App**                        | Teact (TypeScript)           | Web Worker                | [classic.md](platforms/classic.md)         |
| **iOS** (Air)                                | Native UIKit + SwiftUI       | Invisible WKWebView       | [air-ios.md](platforms/air-ios.md)         |
| **Android** (Air)                            | Native custom views (Kotlin) | Invisible Android WebView | [air-android.md](platforms/air-android.md) |
| **iOS/Android** (Capacitor)                  | Teact in WebView (legacy)    | Web Worker                | [classic.md](platforms/classic.md)         |

The **Classic** TypeScript codebase (`src/`) directly renders the UI on web-based platforms. On native mobile (**Air**), the same TypeScript code runs headlessly inside an invisible WebView, acting purely as an SDK — the UI is fully native.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Platform UI Layer                         │
│                                                                     │
│  ┌───────────────────┐  ┌──────────────┐  ┌───────────────────┐     │
│  │  Classic (Teact)  │  │  Air iOS     │  │  Air Android      │     │
│  │  Web / Electron / │  │  UIKit +     │  │  Custom VC        │     │
│  │  Extension / TMA  │  │  SwiftUI     │  │  Framework        │     │
│  └────────┬──────────┘  └──────┬───────┘  └────────┬──────────┘     │
│           │                    │                   │                │
│      Direct call         WKWebView bridge    Android WebView        │
│      (same process)      (message handlers)  (@JavascriptInterface) │
│           │                   │                    │                │
├───────────┴───────────────────┴────────────────────┴────────────────┤
│                                                                     │
│                        TypeScript SDK Layer                         │
│                            (src/api/)                               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  API Methods                                             │       │
│  │  auth · transfer · swap · staking · nfts · domains ·     │       │
│  │  dapps · tonConnect · activities · tokens · polling      │       │
│  └──────────────────────┬───────────────────────────────────┘       │
│                         │                                           │
│  ┌──────────────────────┴───────────────────────────────────┐       │
│  │  Chain SDKs (src/api/chains/)                            │       │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────┐                  │       │
│  │  │   TON   │  │  TRON   │  │  Solana  │                  │       │
│  │  └─────────┘  └─────────┘  └──────────┘                  │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  Common Infrastructure                                   │       │
│  │  mnemonic encryption · account storage · polling ·       │       │
│  │  backend socket · token management · swap protocol       │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## SDK Layer (`src/api/`)

The TypeScript SDK is the single source of truth for all blockchain logic. It runs in different contexts depending on the platform:

| Platform             | SDK Runs In               | Transport                                     |
|----------------------|---------------------------|-----------------------------------------------|
| Web / Electron / TMA | Web Worker                | `postMessage`                                 |
| Browser Extension    | Service Worker            | Extension messaging                           |
| Air iOS              | Invisible WKWebView       | `callAsyncJavaScript` ↔ `messageHandlers`     |
| Air Android          | Invisible Android WebView | `evaluateJavascript` ↔ `@JavascriptInterface` |

### Entry Point

All platforms call the SDK through `callApi(methodName, ...args)` which returns a `Promise`. The SDK may return `undefined` on transport errors — all callers must handle this.

### Chain SDKs

Each blockchain implements the `ChainSdk<T>` interface (`src/api/types/chains.ts`) covering auth, transfers, activities, polling, NFTs, staking, and more.

```
src/api/chains/
├── ton/       # Full-featured: contracts, Ledger, staking, DNS, TonCenter
├── tron/      # TRC-20 tokens, energy/bandwidth fees
└── solana/    # SPL tokens, program interactions, rental fees
```

Chain-specific code is **only allowed** in these designated locations:

1. `ApiChain` union — `src/api/types/misc.ts`
2. `CHAIN_CONFIG` — `src/util/chain.ts`
3. `$byChain` SCSS map — `src/styles/scssVariables.scss`
4. `ApiWalletByChain` — `src/api/types/storage.ts`
5. Chains registry — `src/api/chains/index.ts`
6. Font icons — `src/assets/font-icons/chain-<chain>.svg`
7. Token styles — `TOKEN_CUSTOM_STYLES` in `src/config.ts`

### API Methods

Domain-organized in `src/api/methods/`: `auth` · `accounts` · `wallet` · `activities` · `tokens` · `transfer` · `nfts` · `domains` · `staking` · `swap` · `dapps` · `tonConnect` · `notifications` · `polling` · `prices` · `init`

Methods call chains only through the chains registry. Reverse imports are forbidden.

### dApp Protocols (`src/api/dappProtocols/`)

A pluggable `DappProtocolManager` routes dApp requests to protocol adapters:

- **TON Connect** — extension injection, mobile in-app browser, SSE bridge
- **WalletConnect v2** — EVM and Solana chain support

### Security

- Mnemonics encrypted via **PBKDF2** (100K iterations) + **AES-GCM**
- Private keys never stored unencrypted
- Password hashing via Web Crypto API
- Debug logs sanitize sensitive data

---

## Classic Platform (Web / Electron / Extension / TMA)

**Full docs:** [platforms/classic.md](platforms/classic.md)

The Classic codebase uses the TypeScript SDK for both logic **and** UI:

- **Teact** — lightweight vendored React-like framework (`src/lib/teact/`)
- **TeactN** — global state store with `withGlobal` HOC (`src/global/`)
- **SCSS Modules** — styling
- **Webpack** — build with platform-specific env flags

### State Management

All state in a single `GlobalState` object (`src/global/types.ts`). Actions in `src/global/actions/`, selectors in `src/global/selectors/`. State persisted to `localStorage` with versioned migrations (`STATE_VERSION`, `migrateCache` in `cache.ts`).

### Platform-Specific Layers

| Platform  | Additional Layer                                                                    |
|-----------|-------------------------------------------------------------------------------------|
| Electron  | Main process (`src/electron/`): IPC boundary, OS keychain, auto-updates, deep links |
| Extension | Service worker + content script (`src/extension/`): dApp provider injection         |
| TMA       | Telegram Mini App integration via `IS_TELEGRAM_APP` flag                            |

---

## Air Platforms (Native iOS & Android)

The native mobile apps have **fully native UI** and use the TypeScript SDK headlessly through an invisible WebView bridge.

### Shared Architecture Pattern

Both Air apps follow the same conceptual design:

```
Native UI (ViewController/Activity)
    ↕ delegate/observer callbacks
ViewModel / Presenter
    ↕ async API calls
WebView Bridge (invisible)
    ↕ JavaScript ↔ Native message passing
TypeScript SDK (src/api/)
    ↕ HTTP/WS
Blockchain Networks
```

### Bridge Protocol

**Native → SDK:** Call API methods, receive typed results
```
native.callApi("transfer", args) → JS SDK executes → Promise resolves → decoded result
```

**SDK → Native:** Real-time state updates
```
JS SDK emits update → native message handler → Store update → Observer notification → UI refresh
```

**SDK → Native:** Secure storage callbacks
```
JS SDK needs keychain access → native callback → Keychain/KeyStore read/write → result returned to JS
```

### Three-Tier Storage (Both Platforms)

| Tier       | iOS                       | Android                     | Contents                      |
|------------|---------------------------|-----------------------------|-------------------------------|
| Secure     | Keychain (Secure Enclave) | Encrypted SharedPreferences | Private keys, biometric data  |
| Persistent | WKWebView localStorage    | WGlobalStorage              | Settings, account metadata    |
| In-Memory  | `@Perceptible` singletons | Singleton stores            | Live UI state from SDK events |

### Native Capabilities

| Capability      | iOS                              | Android                  |
|-----------------|----------------------------------|--------------------------|
| Biometrics      | Face ID / Touch ID (`LAContext`) | `androidx.biometric`     |
| Hardware wallet | Ledger via `CoreBluetooth`       | Ledger via BLE           |
| Push            | `UserNotifications` + FCM        | Firebase Cloud Messaging |
| QR scanner      | AVFoundation                     | CameraX + ML Kit         |
| App lock        | Background timeout               | `AutoLockHelper`         |

**Full docs:** [Air iOS](platforms/air-ios.md) · [Air Android](platforms/air-android.md)

---

## Build System

### Classic Builds

```bash
npm run dev                        # Web dev server
npm run build                      # Web production
npm run electron:dev               # Electron dev
npm run electron:package           # Electron release
npm run extension-chrome:package   # Chrome extension
npm run telegram:build             # Telegram Mini App
```

### Air Builds

Prerequisites — bundle the SDK for WebView:
```bash
npm run mobile:build:production    # Webpack with IS_CAPACITOR=1 + cap sync
```

Then build natively:
```bash
cd mobile/android && ./gradlew assembleDebug           # Android
cd mobile/ios && xcodebuild build -workspace App/App.xcworkspace -scheme MyTonWallet ...  # iOS
```

### Build Flags

| Flag                   | Effect                       |
|------------------------|------------------------------|
| `IS_EXTENSION`         | Browser extension mode       |
| `IS_PACKAGED_ELECTRON` | Electron desktop             |
| `IS_CAPACITOR`         | Capacitor / Air SDK bundle   |
| `IS_AIR_APP`           | Native Air app detection     |
| `IS_TELEGRAM_APP`      | Telegram Mini App            |
| `IS_CORE_WALLET`       | TON Foundation branded build |

---

## Key Design Principles

1. **Single SDK, multiple UIs** — blockchain logic written once in TypeScript, consumed by all platforms
2. **Chain-agnostic core** — ~99% of code is chain-independent; adding a chain requires changes only in designated files
3. **Security boundaries** — Electron IPC, WebView bridge, and extension messaging all treated as untrusted boundaries with strict validation
4. **Native where it matters** — Air apps deliver native UX/performance while reusing the battle-tested SDK
5. **Offline-capable state** — three-tier storage (secure, persistent, in-memory) with versioned migrations ensures data survives across updates

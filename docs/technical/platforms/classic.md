# Classic (TypeScript) Platform — Technical Summary

The "Classic" codebase is a TypeScript single-page application that powers the **Web**, **Electron**, **Browser Extension**, and **Telegram Mini App** platforms. It also serves as the **SDK layer** for native mobile apps via an invisible WebView bridge.

## Stack

- **Language**: TypeScript (strict mode)
- **UI Framework**: Teact — a lightweight vendored React-like library (`src/lib/teact/`)
- **State Management**: TeactN — global store with `withGlobal` HOC (`src/global/`)
- **Build**: Webpack with platform-specific env flags
- **Styling**: SCSS Modules
- **Tests**: Jest (unit), Playwright (E2E)
- **Linting**: ESLint, Prettier, Stylelint, Husky pre-commit hooks

---

## Directory Structure

```
src/
├── api/                 # Backend API layer (runs in Web Worker)
│   ├── chains/          # Chain SDK implementations (ton, tron, solana)
│   ├── common/          # Shared API infrastructure
│   ├── dappProtocols/   # TON Connect, WalletConnect adapters
│   ├── methods/         # API methods by domain
│   ├── providers/       # Transport: worker, direct, extension
│   └── types/           # API type definitions
├── components/          # UI components (Teact)
├── electron/            # Electron main process, preload, IPC
├── extension/           # Browser extension: manifest, service worker, content script
├── global/              # TeactN global state
│   ├── actions/         # Action handlers (api/, apiUpdates/, ui/)
│   ├── selectors/       # Pure read functions (no allocations)
│   ├── reducers/        # Domain state reducers
│   ├── cache.ts         # LocalStorage persistence + migrations
│   ├── initialState.ts  # Default state values
│   └── types.ts         # GlobalState type definition
├── hooks/               # 80+ custom hooks
├── i18n/                # Localization (YAML → JSON)
├── lib/                 # Vendored libraries (teact, etc.)
├── styles/              # Global SCSS, chain variables
├── util/                # Utilities (chain, crypto, deeplink, DOM, etc.)
├── push/                # Push notification worker (separate webpack build)
├── giveaways/           # Giveaway/gift claim module (separate build)
├── multisend/           # Batch transfer tool (separate build)
├── portfolio/           # Portfolio dashboard (separate build)
└── config.ts            # App-wide constants and env flags
mobile/
├── android/             # Android: Gradle project + air/ subproject
└── ios/                 # iOS: Xcode workspace + Air/ native code
```

---

## API Layer

### Transport

The API runs in a **Web Worker** by default. The main thread communicates via `callApi(methodName, ...args)` which returns a `Promise`. Transport variants:

| Provider  | Location                   | Used By                                  |
|-----------|----------------------------|------------------------------------------|
| Worker    | `api/providers/worker/`    | Web, Electron, Capacitor, Air            |
| Direct    | `api/providers/direct/`    | Environments without workers             |
| Extension | `api/providers/extension/` | Browser extension popup ↔ service worker |

`callApi` may return `undefined` on transport errors — callers must handle this.

### Chain SDKs

Each chain implements `ChainSdk<T>` (`src/api/types/chains.ts`) with ~20 methods covering auth, transfers, activities, polling, NFTs, staking, etc.

```
src/api/chains/
├── ton/       # Full-featured: contracts, ledger, staking, DNS, TonCenter provider
├── tron/      # TRC-20 tokens, energy/bandwidth fees
└── solana/    # SPL tokens, program interactions, rental fees
```

Chain-specific code is **forbidden** outside these designated locations:
1. `ApiChain` union — `src/api/types/misc.ts`
2. `CHAIN_CONFIG` — `src/util/chain.ts`
3. `$byChain` SCSS map — `src/styles/scssVariables.scss`
4. `ApiWalletByChain` — `src/api/types/storage.ts`
5. Chains registry — `src/api/chains/index.ts`
6. Font icons — `src/assets/font-icons/chain-<chain>.svg`
7. Token styles — `TOKEN_CUSTOM_STYLES` in `src/config.ts`

### API Methods

Domain-organized in `src/api/methods/`:

`auth` · `accounts` · `wallet` · `activities` · `tokens` · `transfer` · `nfts` · `domains` · `staking` · `swap` · `dapps` · `tonConnect` · `notifications` · `polling` · `prices` · `init`

Methods call chains only through the chains registry. Reverse imports are forbidden.

---

## State Management

### TeactN Global Store

All application state lives in a single `GlobalState` object (`src/global/types.ts`, ~40K lines). Key sections:

```
GlobalState {
  appState          // Auth | Main | Explore | Settings | Ledger | Inactive | Empty
  auth              // Authentication flow state
  byAccountId       // Per-account state (balances, activities, NFTs, staking)
  currentTransfer   // Active send flow
  currentSwap       // Active swap flow
  currentStaking    // Active staking flow
  currentDappTransfer // dApp-initiated transaction
  tokenInfo         // Token metadata cache
  settings          // Theme, language, animation level, etc.
  restrictions      // Region-based feature flags
  dialogs, toasts   // UI notification system
}
```

### Bindings (`src/global/index.ts`)

| Export               | Purpose                                           |
|----------------------|---------------------------------------------------|
| `getGlobal()`        | Read current state                                |
| `setGlobal()`        | Write state                                       |
| `getActions()`       | Get action dispatcher                             |
| `addActionHandler()` | Register action handler                           |
| `withGlobal()`       | Connect component to state (like Redux `connect`) |

### Actions (`src/global/actions/`)

```
actions/
├── api/          # Server-side operations (auth, transfer, swap, staking, etc.)
├── apiUpdates/   # Handle real-time polling updates
└── ui/           # Client-only state changes (modals, navigation, forms)
```

### Selectors

Pure functions in `src/global/selectors/`. **Must not allocate** new arrays/objects — this breaks memoization and causes rerender storms.

### Persistence (`src/global/cache.ts`)

- `STATE_VERSION` (currently 53) — bumped on schema changes
- Throttled writes: 5s desktop, 500ms mobile
- `migrateCache()` handles version upgrades
- Selective persistence — only essential data cached (last 20 activities, token info, etc.)

---

## UI Architecture

### Teact (`src/lib/teact/`)

A vendored lightweight React alternative. Key differences from React:
- `useLastCallback` instead of `useCallback` (avoids dependency arrays)
- `memo()` for components without non-memoizable props (e.g., `children`)
- `withGlobal` HOC for state connection (like Redux `connect`)
- No `useRef` for DOM — different approach

### Component Structure

```
src/components/
├── App.tsx              # Root component
├── auth/                # Onboarding, import, create wallet
├── main/                # Main wallet UI, token list, activity
├── transfer/            # Send flow
├── receive/             # Receive flow with QR
├── swap/                # Token swap UI
├── staking/             # Staking UI
├── explore/             # dApp browser
├── dapps/               # dApp connection modals
├── settings/            # Settings screens
├── ledger/              # Hardware wallet connection
├── mediaViewer/         # NFT/media viewer
├── mintCard/            # MTW Card minting
├── domain/              # TON DNS management
├── customizeWallet/     # Wallet card customization
├── vesting/             # Vesting UI
├── common/              # Shared components
├── ui/                  # Base UI primitives
└── Dialogs.tsx          # Global dialog/toast system
```

### Performance Rules

- **No `withGlobal` in loops** — creates N listeners per global change
- **No loops in `mapStateToProps`** — slows evaluation on every state change
- **No new references in `mapStateToProps`** — breaks shallow equality (no `[]`, `{}` literals)
- **`useLastCallback`** over `useCallback`
- **`useMemo`** only for expensive computations or complex objects passed to `memo` children

---

## dApp Protocols

### Architecture (`src/api/dappProtocols/`)

A pluggable `DappProtocolManager` routes dApp requests to protocol adapters:

- **TON Connect** (`adapters/tonConnect/`) — extension injection, mobile in-app browser, SSE bridge
- **WalletConnect v2** (`adapters/walletConnect/`) — EVM and Solana chain support

### Deep Links

Supported schemes: `ton://`, `tc://`, `mtw://`. Parsed and validated before execution. Protocol-specific handlers route to appropriate actions.

---

## Platform Targets

### Build Flags

| Flag                   | Platform                     |
|------------------------|------------------------------|
| `IS_EXTENSION`         | Browser extension            |
| `IS_FIREFOX_EXTENSION` | Firefox-specific             |
| `IS_OPERA_EXTENSION`   | Opera-specific               |
| `IS_PACKAGED_ELECTRON` | Electron desktop             |
| `IS_CAPACITOR`         | Capacitor mobile             |
| `IS_AIR_APP`           | Native mobile (Air)          |
| `IS_TELEGRAM_APP`      | Telegram Mini App            |
| `IS_EXPLORER`          | Explorer mode                |
| `IS_CORE_WALLET`       | TON Foundation branded build |

### Electron (`src/electron/`)

- **Main process**: `main.ts` — app lifecycle, window management, deep links
- **Preload**: `preload.ts` — `contextBridge` with strict allowlist (IPC is a security boundary)
- **Secrets**: `secrets.ts` — macOS Keychain, Windows Credential Manager, Linux password store
- **Auto-updates**: `autoUpdates.ts` — electron-updater

### Extension (`src/extension/`)

- Service worker background
- Content script injection for dApp provider API
- Popup ↔ service worker communication via PostMessage

### Mobile

- **Capacitor**: Web assets bundled with `IS_CAPACITOR=1`, synced via `cap sync`
- **Air (Native)**: Fully-native UI in `mobile/ios/Air/` (Swift) and `mobile/android/air/` (Kotlin) with an invisible WebView as API/SDK bridge
- Build from `mobile/android/` (Gradle) and `mobile/ios/` (Xcode workspace)

---

## Security

### Key Management

- Mnemonics encrypted via **PBKDF2** (100K iterations) + **AES-GCM**
- Private keys never stored unencrypted
- Password hashing via Web Crypto API
- Electron: OS keychain integration for biometric-protected secrets

### IPC Boundary (Electron)

- Renderer is untrusted — all inputs validated
- Explicit allowlist via `contextBridge`
- No direct fs/shell/network access from renderer

### dApp Security

- Message origin validation
- Transaction emulation before signing
- Payload preview for user verification
- Proof tracking for TON Connect

### Sensitive Data

- Debug logs sanitize mnemonics/keys
- Error messages stripped of sensitive content
- In-memory password store with encryption

---

## Async Patterns

| Pattern                             | Usage                           |
|-------------------------------------|---------------------------------|
| `createTaskQueue(concurrency)`      | Serialized storage writes       |
| `throttleWithTickEnd()`             | Coalesce updates within a frame |
| `throttle()`                        | Time-based rate limiting        |
| Polling with `setupActivePolling()` | Per-chain real-time updates     |
| `createPostMessageInterface()`      | Worker/window message passing   |

---

## Build Commands

```bash
npm run dev                    # Dev server (web)
npm run build                  # Production build
npm run check                  # TypeScript type check
npm test                       # Jest unit tests
npm run test:playwright        # Playwright E2E

npm run electron:dev           # Electron dev
npm run electron:package       # Electron build

npm run extension:dev          # Extension dev
npm run extension-chrome:package  # Chrome extension

npm run mobile:build:production   # Capacitor mobile build
cd mobile/android && ./gradlew assembleDebug  # Android native
cd mobile/ios && xcodebuild build -workspace App/App.xcworkspace -scheme MyTonWallet ...  # iOS native
```

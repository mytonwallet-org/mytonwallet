# Submodules

This directory hosts every Swift module that composes the Air app. Use the list below to jump straight to the code that owns a given flow or service.

## Core Infrastructure
- `AirAsFramework` – Bootstraps the native app, wires `AppActions`, splash, and deeplink handling.
- `WalletCore` – Hosts the WebView bridge, API surface, and event routing between Swift and the TypeScript SDK.
- `WalletContext` – Shared themes, localized strings, formatting helpers, and other cross-feature context.

## Feature UI Modules
- `UICreateWallet` – Intro, backup words display/check, and success screens for the wallet creation flow.
- `UIPasscode` – Passcode setup, confirmation, and app unlock views.
- `UIHome` – Home tab controllers, dashboard surface, and account switching sheet.
- `UITransaction` – Activity list, transaction detail views, and success summary screens.
- `UIAssets` – Wallet assets tab, token list, NFT gallery, detailed NFT and hidden collection views.
- `UIToken` – Token detail screen with price, chart, and activity panels.
- `UIReceive` – Receive address, deposit link sharing, and buy-crypto entry points.
- `UISend` – Compose, confirm, sending progress, and sent-result screens for transfers.
- `UISwap` – Swap flow UI including cross-chain, CEX support, and buy-with-card sheet.
- `UIEarn` – Staking experience: Earn home, add stake, claim rewards, and unstake walkthroughs.
- `UIBrowser` – Explore tab, curated collections, and top DApp listings.
- `UIInAppBrowser` – Embedded browser shell and minimizable sheet presentation for web content.
- `UIQRScan` – QR scanner camera flow and result handling for addresses, TonConnect, and URLs.
- `UIDapp` – TonConnect connection approvals, DApp send confirmations, and session management UIs.
- `UISettings` – Root settings navigation plus appearance, security, assets & activity, language, wallet versions, and related screens.
- `UIComponents` – Shared components (buttons, lists, navigation wrappers, toasts, context menus, etc.) used across all feature modules.

## Platform Services & Libraries
- `Ledger` – Discovers, connects to, and exchanges APDUs with Ledger hardware wallets.
- `GZip` – Compression/decompression helpers for payloads and cached assets.
- `RLottieBinding` – Bridging layer to render Telegram’s RLottie animations inside SwiftUI/UIKit.
- `WReachability` – Network reachability monitoring and status notifications.
- `YUVConversion` – Accelerated YUV↔RGB conversion routines backing animation and camera surfaces.

Each module is added to `MyTonWalletAir.xcodeproj`; update this document whenever you introduce, rename, or retire a module so future contributors can orient instantly.

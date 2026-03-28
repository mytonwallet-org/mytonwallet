# MyTonWallet · [mytonwallet.io](https://mytonwallet.io)

**The most feature-rich wallet for the [TON Network](https://ton.org)** – available as a native mobile app (iOS & Android), desktop app (Electron), web app, browser extension, and Telegram Mini App. Supports jettons, NFT, TON DNS, TON Sites, TON Proxy, and TON Magic.

<img src="https://user-images.githubusercontent.com/102837730/193835310-1436afcd-ed78-4656-92c3-9c8f4beacacf.png" width="600" />

The wallet is **self-custodial and safe**. The developers **do not** have access to funds, browser history or any other information. We focus on **speed**, **size** and **attention to detail**. We try to avoid using third-party libraries to ensure maximum reliability and safety, and also to lower the bundle size.

## Table of contents

- [Architecture](#architecture)
- [Requirements](#requirements)
- [Local Setup](#local-setup)
- [Dev Mode](#dev-mode)
- [Linux](#linux-desktop-troubleshooting)
- [Electron](./docs/electron.md)
- [Verifying GPG Signatures](./docs/gpg-check.md)
- [Support Us](#support-us)

## Architecture

MyTonWallet is built on two pillars that share a single TypeScript SDK (`src/api/`) for all blockchain logic (TON, TRON, Solana):

| Pillar | UI | Platforms | Code |
|--------|----|-----------|------|
| **Air** | Native (UIKit + SwiftUI / Kotlin) | iOS, Android | `mobile/ios/Air/`, `mobile/android/air/` |
| **Classic** | Teact (TypeScript) | Web, Electron, Browser Extension, Telegram Mini App | `src/` |

On **Air** platforms the UI is fully native while the SDK runs headlessly in an invisible WebView — delivering a first-class mobile experience with platform-native performance and feel. On **Classic** platforms the SDK and UI run together in a single web context.

For detailed architecture docs — including the SDK layer, chain SDKs, bridge protocol, state management, and build system — see **[docs/technical/summary.md](./docs/technical/summary.md)**.

## Requirements

Ready to build on **macOS** and **Linux**.

To build on **Windows**, you will also need:

- Any terminal emulator with bash (Git Bash, MinGW, Cygwin)
- A zip utility (for several commands)

## Local Setup
### NPM Local Setup
```sh
cp .env.example .env

npm ci
```

## Dev Mode

```sh
npm run dev
```

## Linux Desktop Troubleshooting

**If the app does not start after click:**

Install the [FUSE 2 library](https://github.com/AppImage/AppImageKit/wiki/FUSE).

**If the app does not appear in the system menu or does not process ton:// and TON Connect deeplinks:**

Install [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher) and install the AppImage file through it.

```bash
sudo add-apt-repository ppa:appimagelauncher-team/stable
sudo apt-get update
sudo apt-get install appimagelauncher
```

**If the app does not connect to Ledger:**

Copy the udev rules from the [official repository](https://github.com/LedgerHQ/udev-rules) and run the file `add_udev_rules.sh` with root rights.

```bash
git clone https://github.com/LedgerHQ/udev-rules
cd udev-rules
sudo bash ./add_udev_rules.sh
```

## Support Us

If you like what we do, feel free to contribute by creating a pull request, or just support us using this TON wallet: `EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S`. We appreciate it a lot!

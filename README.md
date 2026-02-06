# MyTonWallet · [mytonwallet.io](https://mytonwallet.io)

**The most feature-rich web wallet and browser extension for the [TON Network](https://ton.org)** – with support of jettons, NFT, TON DNS, TON Sites, TON Proxy, and TON Magic.

<img src="https://user-images.githubusercontent.com/102837730/193835310-1436afcd-ed78-4656-92c3-9c8f4beacacf.png" width="600" />

The wallet is **self-custodial and safe**. The developers **do not** have access to funds, browser history or any other information. We focus on **speed**, **size** and **attention to detail**. We try to avoid using third-party libraries to ensure maximum reliability and safety, and also to lower the bundle size.

## Table of contents

- [Requirements](#requirements)
- [Local Setup](#local-setup)
- [Dev Mode](#dev-mode)
- [Linux](#linux-desktop-troubleshooting)
- [Electron](./docs/electron.md)
- [Verifying GPG Signatures](./docs/gpg-check.md)
- [Support Us](#support-us)

## Requirements

Ready to build on **macOS** and **Linux**.

To build on **Windows**, you will also need:

- Any terminal emulator with bash (Git Bash, MinGW, Cygwin)
- A zip utility (for several commands)

## Local Setup
### Prepare macOS
`node-gyp` tries to build `node-canvas`, so we pre-install [all necessary dependencies](https://github.com/Automattic/node-canvas/wiki/Installation:-Mac-OS-X#homebrew) in advance.
```sh
brew install pkg-config cairo pango libpng jpeg giflib librsvg
```

### NPM Local Setup
```sh
mv .env.example .env

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
sudo bash !

# **MyTonWallet** · [mytonwallet.io](https://mytonwallet.io)

**All you need to enjoy crypto.** A safe, self-custodial **multichain wallet** for [**TON**](https://ton.org), [**TRON**](https://trondao.org/), and [**Solana**](https://solana.com/) — native mobile (iOS & Android), desktop, web, and **Telegram Mini App**. One account, any device.

<img src="https://mytonwallet.io/img/og-image.png" width="600" alt="MyTonWallet — All You Need to Enjoy Crypto" />

You keep full control: we **do not** have access to your funds, keys, or data. **MyTonWallet** is built for **speed** and **reliability**, with a minimal dependency footprint for maximum safety.

---

## Why **MyTonWallet**?

**🌐 One wallet for everything**  
Keep TON, TRON, and Solana in one place. You can send, receive, and swap across chains without jumping between different apps.

**📱 Use it wherever you are**  
**MyTonWallet** works as a native mobile app, desktop app, web app, Telegram Mini App, and browser extension for all major browsers, so your wallet is always within reach.

**⚡ Instant transfers**  
Transfers and swaps feel almost instant across supported chains, so you can send crypto and other assets in less than a second in typical conditions.

**🤖 Built-in smart Agent**  
Talk to Agent in natural language to send assets, swap, stake, open Explore, and jump to token pages. It is non-custodial by design: you always review and confirm every action.

**🪙 Gasless transfers**  
Send supported tokens on TON and Solana without holding native gas tokens, with fees covered from the transferred token where available.

**💳 Easy on-ramp and off-ramp**  
Buy crypto with a bank card and withdraw back to card where supported, via providers like MoonPay.

**🔄 Smart swaps**  
Swap inside the app with an aggregator that finds efficient routes across TON, TRON, and Solana.

**📊 Portfolio tracking**  
Follow your portfolio and net worth over time in the base fiat currency you choose.

**💰 High-yield staking**  
Stake TON and other supported assets, including options like USDe, directly in the wallet.

**🛡️ Industry-leading security**  
**MyTonWallet** uses advanced security practices audited by CertiK. We also run a [bug bounty on CertiK SkyShield](https://skyshield.certik.com/bounties/mytonwallet) with **$100K** in reserved funds and rewards of up to **$5,000**. The program has been live since **March 23, 2024**, and no vulnerabilities have been found to date.

**🧰 Hundreds of handy features**  
Connect Ledger hardware wallets, hide balances, personalize interface, send multiple transfers at once, view other wallets, use AI plugins for OpenClaw, ChatGPT, and Claude, and much more.

**⭐ Trusted by millions**  
**MyTonWallet** has a **4.8** rating on [Trustpilot](https://www.trustpilot.com/), strong App Store and Google Play rankings, and **9M+ users** worldwide.

---

## 🔗 Links

- 📲 **Get the app**: [get.mytonwallet.io](https://get.mytonwallet.io/)
- 📚 **Help Center**: [help.mytonwallet.io](https://help.mytonwallet.io)
- 🛟 **24/7 Support**: [t.me/mysupport](https://t.me/mysupport)
- 💬 **Telegram**: [t.me/mytonwalleten](https://t.me/mytonwalleten)
- 🐦 **X (Twitter)**: [x.com/mytonwallet_io](https://x.com/mytonwallet_io)
- 📰 **Blog & updates**: [mytonwallet.io](https://mytonwallet.io)

---

## 🛠️ For developers

### 📑 Table of contents

- ⚙️ [Requirements](#requirements)
- 🧩 [Local Setup](#local-setup)
- 🚀 [Dev Mode](#dev-mode)
- 🐧 [Linux](#linux-desktop-troubleshooting)
- 🖥️ [Electron](https://github.com/mytonwallet-org/mytonwallet/blob/master/docs/electron.md)
- 🔐 [Verifying GPG Signatures](https://github.com/mytonwallet-org/mytonwallet/blob/master/docs/gpg-check.md)
- ❤️ [Support Us](#support-us)

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

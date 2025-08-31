# Submodules

These are the main modules defined in the project:

### :fire: AirAsFramework

The core module containing the app startup code.

It also handles the deeplinks logic, located in SplashVC.

### :popcorn: UICreateWallet

The UI implementation of the wallet creation flow, including the Intro, WalletCreated, WordDisplay,
WordCheck, and Completed pages.

### :key: UIPasscode

The UI implementation for the set passcode flow.

### :house: UIHome/UITransaction

The UI implementation of the home (main) page and wallet transactions.

### :fireworks: UIAssets/UIToken

The UI implementation of the NFT and token screens.

### :rocket: UIReceive/UISend

The UI implementation of the receive and send screen pages.

### :dollar: UIStake

The UI implementation of the staking screens.

### :earth_africa: UIBrowser/UIInAppBrowser

The UI implementation of the Explore tab and in-app browser screens.

### :gear: UISettings

Contains all settings, including the root settings screen, Appearance, WalletVersions, and more.

### :movie_camera: UIQRScan

QR scanner for scanning ton and ton connect bridge URLs.

### :rocket: UITonConnect

Handles TonConnect 2 DApp connections and transfer features.

### :jack_o_lantern: UIComponents

All the UI components!

This module also includes utility methods for view classes and elements.

### :gear: WalletCore

The bridge between the UI and the SDK. It defines API calls and wallet events.

### :books: WalletContext

Shared class/struct files used by the UI modules are developed here, including WStrings, WTheme, and
more.

### :lock: Ledger

Responsible for discovering and connecting to Ledger devices. It also transmits data to the Ledger
and returns responses to the SDK.

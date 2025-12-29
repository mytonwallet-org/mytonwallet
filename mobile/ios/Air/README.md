# :gem: MyTonWallet Air :gem:

**The most feature-rich web wallet and browser extension for the [TON Network](https://ton.org)** – with support of jettons, NFT, TON DNS, TON Sites, TON Proxy, and TON Magic. **Now on the Air!**

<img src="docs/screenshot.png" alt="Application Screenshot" width="320" style="border-radius: 16px;"/>

## :beers: How to Build

First, Make sure you've installed these on your system:

- Xcode (recommended version: latest release version)
- NodeJS (recommended version: 24)

This directory is part of the MyTonWallet monorepo. [MyTonWallet](https://github.com/mytonwalletorg/mytonwallet).

After cloning the `air` branch, follow the build instructions and run:

```
npm run build
npm run mobile:run:ios
```

If you've modified SDK files (src/api/\*), please run the SDK file generator command:

```
npm run mobile:build:sdk
```

This command will generate the js file required in the Air applications and place it in the project directory automatically.

## SubModules

The Air application is splitted into many ui and logic submodules.

You can get a summary for submodules [here](docs/submodules.md).

If you want the dependency graph, visit [here](scripts/README.md).

<img src="docs/dependency_graph.svg" alt="Dependency Graph" style="border-radius: 16px;" />

## Blockchain Communications

All the api calls and blockchain logic is shared with our long-lived stable production webapp, through a js bridge. The native app is developed around that SDK.

To learn more about this bridge, read [this doc](docs/js-bridge.md).

## Storage

### Shared Storages:

- GlobalStorage

  Global storage stores all the non-critical data, including cached activities, settings and so on.

  It stores data in the web-view local-storage on both Legacy(Capacitor) app and the new Air(Native) app.

- SecureStorage

  Sensitive encrypted data are stored using this storage, into Keychain.

### Air Exclusive Storages:

- GRDB Sqlite DB

  Stores non-sensitive account data like account type, wallet name and so on. Used to handle unexpected localstorage removal.

- Logs

  Logs are stored in a .tsv file

- Nfts and Staking data

  Nfts and Staking data are stored in .json files

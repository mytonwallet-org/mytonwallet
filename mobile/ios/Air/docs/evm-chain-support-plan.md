# iOS EVM Chain Support Plan

Date: April 25, 2026

## Scope
- Add the EVM chains already implemented in the SDK and web app to Air iOS.
- Treat Ethereum and Base as the first EVM rollout, not as one-off chain additions.
- Prepare the iOS model, config, assets, and dapp layers for more EVM chains soon, potentially up to 10 additional chains.

## Chains in the current branch

The current branch adds shared EVM SDK support and registers two concrete chains:

| Chain | `ApiChain` | Native token slug | Default enabled tokens | Explorer | WalletConnect CAIP-2 |
| --- | --- | --- | --- | --- | --- |
| Ethereum | `ethereum` | `eth` | `eth`, `ethereum-0xdac17f95` | Etherscan | `eip155:1` mainnet, `eip155:5` testnet |
| Base | `base` | `base` | `base`, `base-0xfde4c96c`, `base-0x833589fc` | BaseScan | `eip155:8453` mainnet, `eip155:84532` testnet |

Additional token definitions already present on the web side:

| Token | Slug | Chain | Contract | Decimals |
| --- | --- | --- | --- | --- |
| ETH | `eth` | `ethereum` | native | 18 |
| Base ETH | `base` | `base` | native | 18 |
| Ethereum USDT | `ethereum-0xdac17f95` | `ethereum` | `0xdAC17F958D2ee523a2206206994597C13D831ec7` | 6 |
| Ethereum USDC | `ethereum-0xa0b86991` | `ethereum` | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 6 |
| Base USDT | `base-0xfde4c96c` | `base` | `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2` | 6 |
| Base USDC | `base-0x833589fc` | `base` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 |

Common EVM behavior from the SDK/web config:
- Address format: `^0x[a-fA-F0-9]{40}$`
- Address prefix format: `^0x[a-fA-F0-9]{0,40}$`
- Default derivation path: `m/44'/60'/0'/0/{index}`
- Chain standard: `ethereum`
- Subwallets: supported by derivation path
- Transfer payloads/comments: not supported
- Encrypted comments: not supported
- Full native balance transfer: not supported
- Ledger: not supported
- Push notifications: not supported
- Backend socket: not supported
- Token import by address: not supported
- NFTs: supported
- Net worth details: not supported

## Design direction for many EVM chains

The main iOS risk is adding Ethereum/Base by spreading concrete `ethereum` and `base` switch cases across the app. That would make the next batch of EVM chains expensive and error-prone.

Instead, iOS should introduce a small EVM-aware config layer:

- Keep `ApiChain.rawValue` as the stable identifier used by the SDK.
- Make "supported chain" checks config-driven instead of hardcoded to specific enum cases.
- Add `chainStandard` or `chainFamily` to `ChainConfig`; EVM chains should report `chainStandard == .ethereum` or equivalent.
- Move shared EVM defaults into one helper/factory instead of duplicating them per chain.
- Keep per-chain differences as data: title, native token, default enabled slugs, stablecoins, explorer, marketplace chain name, WalletConnect chain IDs, and assets.
- Prefer `chain.isEvm` / `chain.chainStandard == .ethereum` checks over `chain == .ethereum || chain == .base`.
- Make `ApiChain.allCases` / chain order come from a static ordered registry. Future EVM additions should require adding a descriptor and assets, not editing every feature switch.

Recommended native shape:

```swift
struct EvmChainDescriptor: Sendable {
    let chain: ApiChain
    let title: String
    let nativeToken: ApiToken
    let usdtSlug: [ApiNetwork: String]
    let defaultEnabledSlugs: [ApiNetwork: [String]]
    let crosschainSwapSlugs: [String]
    let tokenInfo: [ApiToken]
    let explorer: ChainConfig.Explorer
    let marketplace: ChainConfig.Marketplace?
    let walletConnectChainIds: [ApiNetwork: Int]
}
```

The exact type can change during implementation, but the important part is that adding another EVM chain should look like adding one descriptor plus assets.

## Phase 1: Chain registry and config foundation

Update `WalletCore/Models/Chain` first.

- Add Ethereum and Base to the supported chain registry.
- Add `chainStandard` or `chainFamily` to `ChainConfig`.
- Add `defaultDerivationPath` to `ChainConfig`.
- Add `isNftSupported`, NFT pagination limits, explorer list, and marketplace list if iOS needs parity with web explorer/NFT behavior.
- Change `ApiChain.isSupported` to use the registry/config instead of a fixed switch.
- Change `ApiChain.allCases` to use ordered config data: `ton`, `tron`, `solana`, `ethereum`, `base`.
- Update `getChainByNativeSlug` so native EVM token slugs resolve to their chains.
- Keep existing TON/TRON/Solana behavior unchanged.

For the next EVM chains, the desired delta should be:

- Add token constants.
- Add one EVM chain descriptor.
- Add the chain to the ordered registry.
- Add assets.
- Rebuild the SDK bundle.

## Phase 2: Token definitions and defaults

Add native Swift token constants matching web config:

- `ETH`
- `BASE`
- Ethereum USDT
- Ethereum USDC
- Base USDT
- Base USDC

Update token bootstrapping:

- Include EVM token info in the local fallback token cache.
- Include Ethereum/Base default enabled slugs by network.
- Keep Ethereum USDC available in token info even though it is not default-enabled in the current web config.
- Keep Base USDT and Base USDC default-enabled.
- Ensure invalid-price fallback lists and token image fixups are data-driven where possible.

## Phase 3: Assets, explorer links, and visual surfaces

Add or verify assets:

- `chain_ethereum` already exists.
- Add `chain_base`.
- Add `inline_chain_ethereum`.
- Add `inline_chain_base`.
- Add receive header background/ornament assets for Ethereum/Base, or add a deliberate fallback for chains without custom receive artwork.

Update explorer handling:

- Add Etherscan and BaseScan.
- Avoid menu icon logic that assumes only Tonviewer/Tonscan.
- Prefer explorer icons keyed by explorer id, with a fallback for unknown explorers.
- Add NFT and collection link patterns if iOS exposes NFT explorer links.

Update chain color/palette usage:

- Move chain colors into a registry or config if possible.

First-pass implementation status:

- Added `chain_base` from the shared web full-color Base asset.
- Added `inline_chain_ethereum` and `inline_chain_base` from shared web font-icon assets.
- Wired receive headers to use existing chain-specific background/ornament assets when present and fall back to a chain-colored placeholder background plus the chain mark when final artwork is missing.
- Moved explorer selection to the chain config source so Ethereum uses Etherscan and Base uses BaseScan.
- Kept Tonviewer/Tonscan menu icons, and use the generic explorer/globe icon for explorers without dedicated iOS menu artwork.

Still missing final design assets:

- Dedicated `receive_background_ethereum` and `receive_ornament_ethereum`.
- Dedicated `receive_background_base` and `receive_ornament_base`.
- Dedicated menu icons for Etherscan and BaseScan, if product wants explorer-specific icons instead of the generic explorer icon.
- Marketplace/NFT artwork for EVM chains, if EVM marketplaces are enabled in iOS.
- Avoid adding one more hardcoded portfolio color switch per EVM chain.

## Phase 4: Accounts, import, and subwallets

Mnemonic import:

- After the SDK bundle is rebuilt, mnemonic import can return `byChain.ethereum` and `byChain.base`.
- Ensure iOS stores and displays those addresses instead of filtering them out as unsupported.
- Verify `upgradeMultichainAccounts` can add missing EVM chain addresses to existing multichain accounts.

Subwallets:

- Set EVM multi-wallet support to derivation-path based.
- Use the shared EVM derivation path `m/44'/60'/0'/0/{index}`.
- Verify subwallet creation, naming, and ordering across Solana plus multiple EVM chains.

Private key import:

- Current iOS private-key import is effectively TON-only.
- If EVM private-key import is in scope, add an explicit chain picker or EVM-chain picker.
- Do not assume one imported private key should silently create every supported EVM chain unless product confirms that behavior.

View wallet import:

- A `0x` address is valid on every EVM chain.
- Decide whether a view wallet should import one selected EVM chain, all supported EVM chains, or show an EVM chain selector.
- This decision matters more once there are 10 or more EVM chains.

First-pass implementation status:

- Validated the web call path: `verifyPassword` in `src/api/methods/wallet.ts` decrypts the account mnemonic, marks the password valid, then awaits `upgradeMultichainAccounts(password)`.
- `upgradeMultichainAccounts` in `src/api/methods/auth.ts` scans stored BIP-39 accounts, finds supported subwallet-capable chains that are missing a derivation, derives the missing wallet from the mnemonic, updates stored `byChain`, and emits `updateAccount` for each added chain.
- Air iOS reaches that same web path through `AuthSupport.verifyPassword` -> `Api.verifyPassword`, so unlock/passcode/biometric password verification already triggers the account upgrade without a separate native bridge call.
- The iOS `updateAccount` handler now updates `AccountStore.accountsById` immediately before persisting to GRDB, so newly added Ethereum/Base account chains become visible without waiting for database observation to round-trip.
- Mnemonic import already stores `result.byChain` directly from the SDK; Ethereum/Base are retained now that `ApiChain` and chain config mark them supported.
- Subwallet UI derives its displayed and selectable chains from `account.orderedChains` plus `account.supportsSubwallets(on:)`, and creation/addition stores the SDK-provided `byChain`; EVM chains participate when present on the account.
- View-wallet import currently follows web behavior: it tries every supported chain whose validator accepts the address, so a `0x` address imports Ethereum and Base together.

Still open for Phase 4:

- Private-key import remains explicitly TON-only until product confirms EVM chain-picker semantics.
- Revisit view-wallet import once the next EVM batch lands; importing one `0x` address into every supported EVM chain may become too broad with 10 or more EVM chains.

## Phase 5: Send, receive, swap, and activities

Receive:

- Add Ethereum/Base receive tabs once the chain registry supports them.
- Deposit Link should remain unavailable unless a chain config provides `formatTransferUrl`; web does not currently define one for Ethereum/Base.
- Verify QR, copy, share, and address labels for `0x` addresses.

Send:

- Use the JS bridge for draft checks and submit, as with other chains.
- Ensure EVM chains do not expose unsupported comment/encrypted comment/full-balance-transfer controls.
- Verify native and ERC-20 transfers.
- Verify not-enough-gas states for ERC-20 transfers.

Swap:

- Keep on-chain swap disabled for Ethereum/Base.
- Configure cross-chain swap slugs to match web:
  - Ethereum: `eth`, `ethereum-0xdac17f95`
  - Base: `base`

Activities:

- Ensure activity models decode EVM fields without assuming TON/TRON/Solana-only shapes.
- Account for web's `chainStandard` grouping for cross-chain activity fetching.
- Verify transaction hashes are displayed as hex and explorer links do not base64-convert EVM hashes.

First-pass implementation status:

- Receive tabs are already driven by `account.orderedChains`, so Ethereum/Base appear when the upgraded/imported account contains those chains.
- Deposit Link remains hidden for Ethereum/Base because their chain config does not provide `formatTransferUrl`.
- Receive "Buy with crypto" now defaults to a chain's configured cross-chain swap slug, so Base uses `base` instead of defaulting to a USDT slug it does not support.
- Send now hides and suppresses comment/memo payloads for chains where `isTransferPayloadSupported` is false; this keeps EVM transfers from exposing unsupported comment UI or sending payload data.
- Encrypted comments remain disabled through chain config.
- On-chain swap remains disabled for Ethereum/Base through `ApiChain.isOnchainSwapSupported`.
- Activity fetching stays in the JS SDK path; web groups requests by `chainStandard`, so iOS does not duplicate per-EVM-chain grouping logic.
- EVM explorer transaction links keep hex transaction hashes because Ethereum/Base config sets `doConvertHashFromBase64` to false.

Still open for Phase 5:

- Manual SDK-backed validation with real Ethereum/Base accounts: native token transfer, ERC-20 transfer, insufficient-gas states, receive QR/copy/share, and explorer transaction navigation.

## Phase 6: NFTs

Add EVM NFT model support:

- Decode ERC-721 and ERC-1155 interfaces explicitly.
- Keep unknown NFT interfaces non-crashing.
- Add explorer/marketplace URL support for EVM NFT items and collections.
- Verify pagination assumptions against SDK EVM NFT fetching.

First-pass implementation status:

- NFT decoding now recognizes `ERC721` and `ERC1155`; unknown interfaces still fall back without crashing.
- Non-TON NFT identity is now chain-qualified, preventing the same contract/token address from colliding across Ethereum, Base, and future EVM chains.
- Cached NFT dictionaries are normalized to the chain-qualified key shape when loaded.
- EVM NFT item links can open the configured marketplace; Ethereum/Base use OpenSea on mainnet.
- NFT collection explorer links now use chain explorer config where available; TON keeps its existing Getgems fallback.
- NFT burn actions are hidden for chains that do not support SDK burn; TON and Solana remain enabled, Ethereum/Base are disabled.
- Stream prune/account NFT setting validation is no longer TON-only.

Still open for Phase 6:

- Final marketplace icon artwork for EVM actions, if product wants marketplace-specific icons.
- Testnet marketplace policy; current OpenSea config is mainnet-only.
- Manual SDK-backed validation with real Ethereum/Base NFT inventories: pagination, collection rows, item links, marketplace opening, and transfer/burn action visibility.

## Phase 7: Dapps, WalletConnect, and in-app browser

This is the largest native feature gap.

Current iOS injection mainly supports Solana wallet-standard behavior. EVM dapps expect an EIP-1193 provider and EIP-6963 discovery.

Add EVM browser injection:

- Inject a provider compatible with `window.ethereum.request(...)`.
- Announce the provider through EIP-6963.
- Use a chain-id registry instead of hardcoded Ethereum/Base-only logic.
- Route connect, reconnect, disconnect, send transaction, and sign-data requests through the existing native message handler where possible.

Supported EVM WalletConnect methods:

- `eth_sendTransaction`
- `eth_signTransaction`
- `personal_sign`
- `eth_sign`
- `eth_signTypedData`
- `eth_signTypedData_v4`
- `wallet_getCapabilities`

Signing:

- Add EIP-712 payload support to the native sign-data model.
- Add a safe EIP-712 review UI in `UIDapp`.
- EVM sign results are raw hex signatures; do not assume the Solana/TonConnect result shape.

Connection scope:

- A dapp may request multiple EVM chains.
- Store and display the approved chain IDs clearly.
- Handle unsupported EVM chain IDs with a clear error.
- Future EVM additions should only update the chain-id registry.

First-pass implementation status:

- Added `walletConnectChainIds` to native chain config; Ethereum/Base now define their EIP-155 mainnet/testnet IDs in the registry instead of in browser JS.
- The in-app browser now injects an EIP-1193 provider at document start and announces it through EIP-6963.
- The provider routes `eth_requestAccounts`, `eth_accounts`, disconnect/revoke, EVM transaction signing/sending, personal/eth signing, EIP-712 signing, chain switching, and `wallet_getCapabilities` through the existing native `walletConnect:*` bridge.
- Chain routing is based on the selected EIP-1193 chain ID, not only the `0x` address. This avoids sending Base/future EVM requests to Ethereum when the same address exists on multiple chains.
- The provider exposes only the active account network's EIP-155 chain IDs in a browser session; testnet chain IDs are used when the active Air account is testnet.
- Native sign-data decoding now supports `type: "eip712"` and `UIDapp` shows primary type, domain, message, and the signature warning before requesting the passcode.

Still open for Phase 7:

- Manual dapp validation with real sites: provider discovery, account connection, Ethereum/Base chain switching, `personal_sign`, `eth_sign`, `eth_signTypedData_v4`, `wallet_getCapabilities`, `eth_sendTransaction`, and `eth_signTransaction`.
- Decide whether the injected provider should proxy read-only JSON-RPC calls such as `eth_call`, `eth_getBalance`, and `eth_blockNumber`; the first pass focuses on wallet/account/sign/send methods already supported by the SDK adapter.
- Add product-specific EVM dapp allowlist/testing targets once selected.

## Phase 8: JS bundle and validation

After the native model is ready, rebuild the JS SDK bundle consumed by Air:

```bash
npm run mobile:build:sdk
```

Validation should use the workspace:

- Start with the smallest relevant schemes for touched modules, such as `WalletCore`, `UIReceive`, `UISend`, `UIAssets`, `UISwap`, `UIDapp`, and `UIInAppBrowser`.
- Finish with `MyTonWallet_AirOnly`, because the rollout crosses model decoding, stores, app shell integration, the JS bridge, and dapp browser injection.

Core manual scenarios:

- Create/import mnemonic and verify Ethereum/Base addresses appear.
- Upgrade an existing account and verify EVM addresses are added.
- Create subwallets and verify EVM derivation paths.
- Receive Ethereum/Base and copy/share QR addresses.
- Send native ETH on Ethereum and Base.
- Send ERC-20 USDT/USDC.
- Open token details and activity details.
- Open Etherscan/BaseScan links.
- View ERC-721/ERC-1155 NFTs.
- Connect an EVM dapp in the in-app browser.
- Sign `personal_sign`, `eth_sign`, and EIP-712 typed data.
- Send an EVM dapp transaction.

## Future EVM chain onboarding checklist

For each new EVM chain after Ethereum/Base:

1. Confirm web/SDK support:
   - chain id in `EVMChain`
   - chain registered in SDK
   - chain config in web
   - native token and default tokens defined
   - explorer and WalletConnect chain IDs defined

2. Add iOS data:
   - chain descriptor
   - native token
   - default enabled token slugs
   - stablecoin token info
   - explorer config
   - marketplace config if NFTs are supported
   - WalletConnect mainnet/testnet chain IDs

3. Add assets:
   - chain icon
   - inline mark
   - receive artwork or fallback approval

4. Rebuild the Air SDK bundle.

5. Validate the minimum flow:
   - import/upgrade account
   - receive
   - native send
   - token send if default tokens exist
   - activity details
   - explorer links
   - dapp connect/sign/send if dapps are enabled for the chain

## Open decisions

- Should `ApiChain` get concrete enum cases for every future EVM chain, or should future EVM chains be represented as `.other(rawValue)` plus config entries?
- Should a `0x` view wallet import all supported EVM chains or prompt for specific chains?
- Should EVM private-key import create one selected chain or multiple EVM chain accounts?
- Which EVM chains should be default-visible in receive and token lists when the list grows to 10 or more?
- Which EVM chains should support dapps in the first iOS release?
- What is the exact testnet policy for each EVM chain, especially where SDK/web chain IDs and explorer names differ?
- Do we need custom receive artwork for every EVM chain, or is a generic EVM fallback acceptable?

## Acceptance criteria

- Ethereum and Base appear as supported chains in iOS without being filtered as unknown chains.
- New mnemonic imports and account upgrades include Ethereum/Base addresses.
- Default Ethereum/Base token lists match web config.
- Send, receive, swap availability, activity, NFT, and explorer behavior match web-supported capabilities.
- EVM dapps can connect, sign, and send transactions through the in-app browser.
- The next EVM chain can be added mostly by adding config, tokens, WalletConnect IDs, and assets.

# Adding a New Blockchain (Chain) Guide

This short guide lists the minimum required code touch-points to register a new chain in the project.
For deeper architectural rules (stubs, UI gating, import boundaries, etc.) please see [the multichain Cursor rule](../.cursor/rules/multichain.mdc).

## Required Code Changes (Single Source Spots)

Update all of the following in one PR:

1. Add the chain literal to `ApiChain` in `src/api/types/misc.ts`.
2. Extend `ApiWalletByChain` (and add a wallet type) in `src/api/types/storage.ts`.
3. Add a config entry to `CHAIN_CONFIG` in `src/util/chain.ts` (title, flags, regexes, native token, explorer, optional `formatTransferUrl`, etc.).
4. Add per‑chain style variables in `$byChain` inside `src/styles/scssVariables.scss` (colors, accents, etc.).
5. Create the SDK folder `src/api/chains/<chain>/` and export `const <chain>Sdk: ChainSdk<'<chain>'>` from its `index.ts` (all interface methods present; unsupported ones throw `Not supported in <ChainName>`, see `src/api/chains/tron/index.ts` as example).
6. Register the SDK in the map `chains` in `src/api/chains/index.ts`.
7. Add a font icon: `src/assets/font-icons/chain-<chain>.svg` (match size & baseline of existing chain icons).
8. (Optional) Map the native token icon in `TOKEN_FONT_ICONS` in `src/config.ts` if a custom glyph is needed.

## Minimum Viable Feature Set (Recommended Order)

Implement these first so the chain is actually usable.

### Authentication (Importing / Viewing Wallets)

- Importing from a BIP39 mnemonic
- Importing from an address (view-only)

Nice to have later:
- Importing from a Ledger hardware wallet

### Token List

- Native token is required
- Prices
- Jettons can be added later

### Balances

- The SDK chain polling methods must update the balance of the supported tokens

### Activity History

- Fetching activity history slices
- Fetching activity fee
- The SDK chain polling methods must check for new transactions and add them to the start of the list

Nice to have later:
- Comment decryption (if applicable)

### Sending Tokens

- Fetching the fee in the Send form
- Sending

Nice to have later:
- Comment
- Encrypted comment (if applicable)
- Sending with a Ledger hardware wallet

## UI Gating Basics

Only surface features that are actually supported:
- If your chain has no `formatTransferUrl`, it must not appear in Deposit Link flows.
- Use flags from `CHAIN_CONFIG` (e.g. `isTransferCommentSupported`, `isLedgerSupported`) instead of hard-coded `if (chain === ...)`.

## Stubs & Unsupported Features

Provide throwing stubs (`function notSupported(): never`) for every `ChainSdk` method you cannot implement yet.

## Backend & Infrastructure Coordination

A new chain is not only a client concern. It also requires backend support:

What you need from backend:
- Access to a reliable node / RPC endpoint (or cluster) for the new chain
- Indexing & enrichment for activity
- Real-time activity notifications via our backend socket (set by `CHAIN_CONFIG[chain].doesBackendSocketSupport`)

`doesBackendSocketSupport` flag:
- Set to `false` only temporarily while backend adds socket activity support.
- Once backend provides notifications, switch it to `true` so the client receives push updates instead of relying solely on polling.
- Do not leave it `false` long-term; stale value means unnecessary latency and extra battery consumption from polling.

Reach out to the backend team early (ideally before starting client implementation) with the chain’s requirements: activity feed shape, fee estimation endpoints (if any), token metadata plans, and any staking / NFT / domain features you plan to enable soon.
Clearly mark in the PR description whether backend socket support is already live or pending.

If in doubt about what backend exposes, ask — do *not* guess or scrape public explorers.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Added chain but missed `$byChain` styles | Add style map entry before shipping |
| Added special-case UI `if (chain === '<name>')` | Replace with a config flag in `CHAIN_CONFIG` |
| Method missing in one chain SDK | Add stub throwing `Not supported in <ChainName>` |
| Catching stub error to hide feature | Gate the feature in UI instead |
| Left `doesBackendSocketSupport` = false after backend enabled | Set it to true and remove temporary polling-only logic |

# Swap Release Scenarios

This document lists important user scenarios that should keep working consistently across platforms. These are not formal test cases and do not need step-by-step automation. They are a release-awareness checklist for manual testing on the live app before release.

Use small amounts and dedicated QA wallets. Prefer pairs with enough liquidity and known wallet support, and adjust exact tokens when backend availability changes.

## Swap Routes

Cover all swap routes because they have different UI and execution paths:

- On-chain swap: same-chain DEX swap, for example TON token to TON token.
- Cross-chain inside wallet: selling and buying chains are both supported by the current wallet, so no external address entry is needed.
- Cross-chain from wallet: selling chain is supported by the current wallet, buying chain is not; user must enter an external payout address.
- Cross-chain to wallet: selling chain is external, buying chain is supported by the current wallet; user must send funds to a pay-in address and may need a memo.
- Invalid external-to-external pair: neither side belongs to the wallet; it should not proceed as a valid swap.

## Core Scenarios

### 1. Amount Entry

- Editing the selling amount reloads the estimate and updates the buying amount without reload loops.
- Programmatic amount changes from an estimate, fee adjustment, or max-amount recalculation do not create repeated estimate reloads.
- On-chain pairs that support reverse estimates allow editing the buying amount.
- On-chain reverse-prohibited pairs disable buying amount entry and show the expected explanation/toast.
- Cross-chain swaps disable buying amount entry consistently across platforms.
- Clearing the active amount clears stale estimated output and returns the button/details to an empty or waiting state.
- Very small, very large, and too-many-decimal amounts are rounded or rejected consistently.

### 2. Full Amount

Full-amount behavior is high risk and should be covered for each route where the wallet is sending funds:

- On-chain native token: Use All leaves enough native balance for the blockchain fee, or clearly explains why it cannot.
- On-chain non-native token: Use All sends the full token amount while preserving/validating the native fee balance.
- On-chain gasless/diesel pair: Use All still works with diesel status and authorization requirements.
- Cross-chain inside wallet, native token: Use All accounts for CEX transfer fee and native chain fee before submit.
- Cross-chain inside wallet, non-native token: Use All sends the token amount and validates native gas separately.
- Cross-chain from wallet, native token: Use All survives the external-address step and final confirmation without changing amounts unexpectedly.
- Cross-chain from wallet, non-native token: Use All plus external payout address keeps the same sell amount through confirm.
- Cross-chain to wallet: no wallet balance should be required for the external pay-in asset; the pay-in instructions must reflect the typed amount.

### 3. Pair Selection And Reversal

- Switching sell token resets stale estimates, details, errors, and max-amount context.
- Switching buy token resets stale estimates and preserves the sell amount when appropriate.
- Tapping reverse swaps tokens and amounts correctly for on-chain and supported cross-chain pairs.
- Reversal into an unsupported route is blocked or transformed into the correct route consistently.
- Same-token pairs are rejected.
- Unsupported or external-to-external pairs are rejected before confirmation.

### 4. Estimate Refresh

- Estimates refresh after user edits and on the scheduled refresh timer.
- Refreshes stop while the flow is in confirmation, external-address entry, payment-waiting, or completion stages.
- Rate-limited estimates keep the current visible estimate and retry later instead of showing a hard failure.
- Network errors, insufficient liquidity, min/max CEX limits, invalid pair, and unexpected backend errors surface as actionable button or details states.
- The estimate displayed in details matches the amounts shown in the input fields and confirm sheet.
- If the backend adjusts the sell amount for fees, the UI updates once and does not enter an estimate loop.

### 5. Fees And Details

- On-chain details show exchange rate, slippage, blockchain fee, routing/aggregator fee when applicable, price impact warning, and minimum received.
- Slippage draft edits do not reload estimates until committed.
- Invalid slippage is visibly rejected or normalized before it reaches an estimate request.
- Cross-chain details show exchange rate and blockchain fee where relevant.
- Cross-chain provider info is visible and consistent with web.
- CEX swap fee is not shown as a separate details row unless product behavior changes across platforms together.
- Details collapse/expand without hiding important error or button state.

### 6. Confirmation And Submit

- The confirm sheet uses the same sell/buy amounts as the latest accepted estimate.
- Changing amount, pair, account, or balance before confirmation prevents submitting stale data.
- Passcode/biometric cancellation returns to the correct previous stage without hidden estimation.
- Submit failure returns to an editable state with a clear error.
- Submit success either opens the correct wait/result flow or relies on activity updates consistently.
- New swap activity appears in the activity list and opens with coherent details.

### 7. Cross-Chain From Wallet

- External payout address entry validates against the buying chain.
- Paste, scan, saved addresses, and own-account suggestions apply the address and revalidate.
- Unsupported-chain scan results are ignored or rejected clearly.
- Continue stays disabled for empty or invalid addresses.
- Confirmation and transaction submission happen through the main swap execution path, not a separate address-screen path.
- If submit fails after address entry, user remains in the external-address flow and can correct or retry.

### 8. Cross-Chain To Wallet

- Payment instructions show pay-in address, amount, destination wallet, and provider transaction id where available.
- Memo/tag is shown when required and QR code is hidden or adjusted so users do not miss the memo.
- Expired payment state is visible after deadline.
- Internal swaps do not show misleading external payment instructions.
- Waiting, confirming, hold/refund/error states show useful support or recovery text.
- Copy/share actions copy the correct address, memo, amount, and support identifiers.

### 9. Balances, Accounts, And Privacy

- Switching accounts refreshes balances, supported chains, pair validity, and max amount.
- Sensitive-data hiding masks balances and fiat equivalents without breaking amount entry.
- A wallet missing native gas shows the fee problem before submit.
- A watch-only or unsupported account type cannot submit but can still inspect available swap information where appropriate.
- Activity updates are attributed to the correct account after submit.

### 10. App Lifecycle And Recovery

- Leaving and returning to the app preserves the current draft enough to continue safely, or resets stale state clearly.
- Backgrounding during estimation does not leave a permanent spinner.
- Backgrounding during confirmation or waiting does not submit twice.
- Offline mode and restored connectivity produce a clear retry path.
- App restart during cross-chain payment waiting can recover from activity/history state where possible.

## Suggested Release Pass

For each release, do at least one live small-amount pass through:

- One on-chain swap with sell amount.
- One on-chain swap with buy amount, using a pair that supports reverse estimation.
- One on-chain native-token Use All swap.
- One on-chain non-native-token Use All swap.
- One cross-chain inside-wallet swap.
- One cross-chain from-wallet swap with pasted external address.
- One cross-chain to-wallet swap, including pay-in instructions.
- One CEX min/max or too-small amount error.
- One insufficient native fee case.
- One interrupted flow: cancel auth, background the app, or change account before submit.

When a platform intentionally differs, note the reason in the release notes or in this document so future regressions are not mistaken for product decisions.

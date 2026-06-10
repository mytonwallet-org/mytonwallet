# Telegram 2FA iOS Progress

## Goal
Complete Telegram-backed 2FA end to end for Air iOS, starting with the Add 2FA setup flow.

## Step 1: Add 2FA
Status: source/build complete; data pipeline audited; runtime endpoints and contract constants wired; real on-chain validation pending

Runtime endpoints:
- Telegram Mini App: `https://t.me/mtw_giveaway_bot/mfa`
- MFA backend: `https://mfa-server.myinfra.dev`
- MFA frontend: `https://mfa-frontend.myinfra.dev`

Flow:
1. User opens Settings > Security > Confirm with Telegram.
2. iOS checks that the current TON wallet is W5 and has at least 0.15 TON for the connection transaction.
3. iOS publishes an install request through the JS bridge.
4. iOS opens Telegram with `startapp=i-<requestId>`.
5. Telegram Mini App confirms the Telegram user and writes the install request user.
6. iOS polls the install request until the Telegram user is available.
7. iOS asks for the wallet passcode with the wallet and Telegram account shown in the header.
8. iOS calls `installMfaFromRequest`, signs and submits the W5 extension install transaction, then persists `AccountMfa` locally.
9. The settings screen switches to the configured state.

Implemented:
- Settings entry point and Add 2FA screen.
- Install request publishing and Telegram handoff.
- Polling when the app becomes active and every second while the screen is open.
- Passcode confirmation after Telegram user confirmation.
- Local account MFA persistence after install succeeds.
- SDK account updates now carry MFA add/remove changes so JS storage, web state, and iOS `AccountStore` stay aligned.
- Stored/global MFA user types now include Telegram `id`, matching the install request data written by the Mini App.
- Pending install state can reopen Telegram without creating a second request.
- Install flow is disabled for non-W5 wallets before Telegram handoff.
- MFA extension code hash and master address are fixed in SDK config.
- Install request polling expects the backend response key `address`.

Known follow-ups:
- Add user-facing handling for expired or rejected install requests when the backend exposes those states.
- Validate the full setup transaction on device/simulator with a real W5 TON account and Telegram installed.

## Later Steps
- Complete Remove 2FA flow.
- Validate TON Connect / dapp send completion after Telegram confirmation against a real dapp request.
- Add recovery flow if it is in product scope for iOS.

## Data Pipeline Notes
- Launch path: wallet clients open Telegram with the raw request id in `startapp`; install requests keep the existing `i-` prefix expected by the deployed Mini App.
- Install request write path: iOS publishes request through `publishInstallMfaRequest`, Telegram Mini App writes `{ id, name, username, avatarUrl }` under `user`, and iOS polls `fetchInstallMfaRequest` until `user` is present.
- Install persistence path: `installMfaFromRequest` writes `{ address, user }` to SDK account storage and emits `updateAccount` with the same MFA payload; iOS also persists the same value locally for immediate UI refresh.
- Remove persistence path: `confirmMfaRemovalRequest` clears SDK account storage and emits `updateAccount` with `mfa: false`; iOS handles that as local MFA removal.
- Account update semantics: `mfa` omitted means unchanged, object means added/updated, and `false` means removed. This matches existing `domain` update semantics.
- Protected action write path: SDK methods publish signed MFA transaction requests and return `{ mfaRequestHash }` when Telegram confirmation is required.
- Send completion path: `SendConfirmVC` uses `newLocalActivities` as the activity source and shows the activity details only after both the protected confirmation flow succeeds and a matching local activity has arrived. For token/NFT sends that require Telegram confirmation, the existing `fetchMfaRequest` poll emits that local activity once the backend returns the confirmed `txHash`.
- Protected SDK methods covered: send, NFT transfer, DNS renewal/linking, stake, unstake, staking claim/unlock, DEX swap, CEX swap submit, and TON Connect transfer signing.
- Native protected-action foundation: `UnlockVC` is now kept as the passcode UI, passcode presentation lives in `PasscodeAuthPresenter`, app lock uses `AppLockUnlockVC`, and normal blockchain actions can use `AppActions.pushProtectedAction` with an explicit account and lazy Ledger payload to route passcode/Ledger and Telegram MFA through one coordinator.
- Native protected-action results now use the `MfaProtectedActionResult` protocol, so each SDK result type only needs to expose `mfaRequestHash` for the shared coordinator to trigger Telegram confirmation.
- Shared MFA confirmation UI: `MfaConfirmationVC` handles Telegram handoff and polling for any action with `mfaRequestHash`; Send, NFT send, swap, staking, staking claim/unlock, DNS linking/renewal, TON Connect send/connect/sign-data, and MFA install/remove confirmation now use the shared coordinator path.
- Existing web flows without an MFA confirmation screen guard these new SDK results as unsupported for now.

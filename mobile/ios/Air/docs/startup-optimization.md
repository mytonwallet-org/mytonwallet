# iOS Startup Optimization Tracker

Date: March 14, 2026

## Scope
- Target: `MyTonWallet`
- App mode: Air
- Primary goal: reduce time from process launch to Home screen
- Secondary goal: reduce time from process launch to wallet-ready state

## Success metrics
- `startup.toHomeVisible`
  - Process launch -> first Home screen visible
- `startup.toHomeReady`
  - Process launch -> first Home snapshot with wallet data ready
- `startup.toPresentUnlock`
  - Process launch -> unlock screen presentation decision

These are emitted both as textual logs and as Instruments signposts via `StartupTrace`.

## Current measurement setup
- Shared tracer: `WalletContext/Logging/StartupTrace.swift`
- Instruments signpost category: `Startup`
- Important phase intervals:
  - `startup.toHomeVisible`
  - `startup.toHomeReady`
  - `startup.toPresentUnlock`
  - `airLauncher.soarIntoAir`
  - `bridge.startup`
  - `walletCoreData.start`
  - `splashVM.activateAccount`
  - `rootState.transition.active`

## Current launch path
1. `AppDelegate.didFinishLaunching`
2. `SceneDelegate.willConnectTo`
3. `AppSwitcher.startTheApp`
4. `AirLauncher.soarIntoAir`
5. Global storage load + migration
6. Database connect + migrations
7. `WalletCoreData.start`
8. `SplashVC` setup
9. `Api.prepare` -> hidden `JSWebViewBridge`
10. Bridge becomes ready
11. `SplashVM.startApp`
12. `AccountStore.activateAccount`
13. `SplashVC.navigateToHome`
14. `RootStateCoordinator.transition(.active)`
15. `HomeVC` becomes visible
16. `HomeVC` publishes first ready snapshot

## Pre-measurement impressions
These are the obvious candidates before looking at timing data:

### 1. Duplicate WebView startup
- `GlobalStorage.loadFromWebView()` creates a temporary `WKWebView` to read `localStorage`.
- `JSWebViewBridge` then creates another hidden `WKWebView` for the SDK.
- This looks like duplicated startup cost on the cold path.

### 2. Too much serial bootstrap before active root
- `AirLauncher.soarIntoAir()` performs storage load, storage migration, database setup, legacy migration, and `WalletCoreData.start()` before the active root is built.
- Some of this likely belongs on the first-frame path.
- Some of it likely does not.

### 3. Bridge readiness is on the critical path
- `SplashVM.startApp()` waits for bridge readiness before doing account activation.
- That makes Home availability dependent on WebView startup, SDK injection, and JS bootstrap.

### 4. Non-home tabs are built eagerly
- `HomeTabBarController` instantiates Home, Explore, Settings, and Agent controllers during initial setup.
- Only Home is needed for first paint.

### 5. Early startup of secondary services
- `TonConnect.shared.start()`
- `InAppBrowserSupport.shared.start()`
- Remote notification registration
- These may be safe to defer until after Home is visible.

### 6. Home-visible and wallet-ready are different milestones
- `HomeVC` is considered ready only after the first activity snapshot path.
- This is useful for measurement, but it also suggests some data work could move out of the first-visible path.

## Backlog
| Priority | Status | Item | Expected impact | Notes |
| --- | --- | --- | --- | --- |
| P0 | Todo | Remove duplicate WebView startup for global storage and bridge startup | High | Best first bet without detailed logs |
| P0 | Todo | Split `AirLauncher` bootstrap into blocking vs deferred work | High | Keep only first-frame essentials on the critical path |
| P0 | Todo | Lazy-create non-home tabs in `HomeTabBarController` | Medium | Home should not pay to build Explore/Settings/Agent |
| P1 | Todo | Defer `TonConnect`, `InAppBrowserSupport`, and push registration until after Home visible | Medium | Verify no feature regression on deeplink / connect flows |
| P1 | Todo | Re-evaluate what `WalletCoreData.start()` must do before Home visible | Medium | Some caches/stores may be safe to warm after first paint |
| P1 | Todo | Reduce or defer legacy migration work on normal launches | Medium | Migrations may be correct but too eager |
| P1 | Todo | Decouple Home visible from wallet-ready data hydration | Medium | Allows earlier first paint even if some data keeps loading |
| P2 | Todo | Check if account activation can show cached UI before full JS activation completes | High if feasible | Depends on correctness and stale state tolerance |
| P2 | Todo | Audit repeated DB/cache loads done for startup and first Home render | Medium | Look for duplicate work between store bootstrap and first screen |

## Work plan

### Phase 1: Establish baseline
- Capture cold-launch traces on a representative device and simulator.
- Record at least:
  - `startup.toHomeVisible`
  - `startup.toHomeReady`
  - `startup.toPresentUnlock`
  - `airLauncher.soarIntoAir`
  - `bridge.startup`
  - `walletCoreData.start`
  - `splashVM.activateAccount`

### Phase 2: Remove obvious fixed costs
- Prototype removal of the extra storage `WKWebView`.
- Prototype lazy tab controller creation.
- Re-measure after each change independently.

### Phase 3: Reduce blocking work
- Move non-essential startup tasks behind first Home visibility.
- Split blocking and deferred work inside `AirLauncher` and `WalletCoreData.start()`.

### Phase 4: Architectural changes
- Explore whether cached account state can render Home before full JS activation completes.
- Tighten the definition of wallet-ready vs first usable screen.

## Measurement log

### Baseline
- Not recorded yet.

### Iteration 1
- Not started.

### Iteration 2
- Not started.

## Decisions log
- 2026-03-14: Added startup logs and Instruments signposts.
- 2026-03-14: Added dedicated interval for launch -> unlock presentation decision.
- 2026-03-14: Initial optimization hypotheses documented before analyzing traces.

## Guardrails
- Measure cold and warm launch separately.
- Treat `toHomeVisible` and `toHomeReady` as separate targets.
- Avoid moving correctness-critical migrations off the launch path without a rollback plan.
- Keep deeplink, lock screen, and account-switch flows working while optimizing.

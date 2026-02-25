# iOS Root State/Container Refactor Plan

Date: February 9, 2026

## Scope
- Native Air app root architecture only.
- Keep current active tab layout for compact width.
- Add iPad split root layout for regular width.

## Naming decisions
- `AppStateCoordinator` -> `RootStateCoordinator`
- Root state enum:
  - `.intro`
  - `.active`
  - No `accountId` in the enum for now.
- `NormalShellRouting` -> `RootContainerRouting`
- `NormalRootFactory` -> avoid "Factory" naming.
  - Use `RootContainerLayoutResolver` (or `RootContainerBuilder`) as the place that chooses/creates active layout by width.

## iPad split goals (new)
- Add root split container in `AirAsFramework/SplitRoot`.
- Sidebar should include:
  - Home card area.
  - Buttons for Home / Explore / Settings.
  - Extra content/actions block.
- Main area should switch between the same three sections without a tab bar.
- In split mode, Home main content should not show the top home card section (card lives in sidebar).

## Current flow map (implemented)
- Launch:
  - `SceneDelegate` creates window and starts app via `AppSwitcher`.
  - `AirLauncher.soarIntoAir()` sets root to `SplashVC`.
  - `SplashVC` prepares API bridge and `SplashVM.startApp()` decides initial state.
- Root transitions:
  - `AppActions.transitionToRootState(...)` delegates to `RootStateCoordinator`.
  - `RootStateCoordinator` keeps `RootHostVC` as stable `window.rootViewController`.
  - `RootHostVC` swaps content between intro (`WNavigationController(IntroVC)`) and active (`RootContainerVC` with adaptive tab/split layout).
- Intro -> active:
  - `SplashVC.navigateToHome()` and `IntroModel` use `AppActions.transitionToRootState(.active, ...)`.
- Active -> intro:
  - `AccountStore.resetAccounts()` emits `WalletCoreData.Event.accountsReset`.
  - `RootStateCoordinator` observes `accountsReset` and transitions to `.intro`.
- Language/app restart path:
  - `LanguageVC` calls `WalletContextManager.delegate?.restartApp()`.
  - `SplashVC.restartApp()` clears wallet observers/readiness and reruns `startApp()` (without manual root swap).
- Navigation & presentation:
  - Root-level primary navigation actions are abstracted by `RootContainerRouting` (`TabRootContainerRouter` + `SplitRootContainerRouter` impls).
  - `AppActionsImpl` uses centralized presentation helpers (`presentationAnchorViewController`, `presentFromTop`, `presentFromTopInNavigation`) to avoid presenting from wrong root level.
  - `WMinimizableSheet` minimizing support now checks `MinimizableSheetHosting` capability instead of `UITabBarController` presence.
- Ready/deeplink gate:
  - `walletIsReady(true)` remains emitted by active home flow (`HomeVC` snapshot path).

## Findings / pain points status
1. Root transitions are centralized.
- Resolved via `RootStateCoordinator`.

2. Active layout creation is abstracted.
- Resolved via `RootContainerLayoutResolver` (adaptive tab/split).

3. Data layer no longer calls UI restart directly for account reset.
- Resolved via `WalletCoreData.Event.accountsReset` -> coordinator transition.

4. Deeplink readiness is still tied to home lifecycle.
- Known limitation kept for this phase (acceptable for current scope).

5. JS bridge host is stable across intro/active shell switches.
- Resolved via `RootHostVC`.

## Target architecture
### 1) RootStateCoordinator
- Single owner of root state and transitions.
- Responsibilities:
  - Compute and apply target root state (`intro` or `active`).
  - Perform root transition animations.
  - Own startup transition entry points (currently in `SplashVC`/`SplashVM`).
  - Handle "accounts became empty" transition to intro.

### 2) RootContainerRouting
- Protocol used by `AppActions` for root-level navigation intent.
- First implementation wraps current tab layout.
- Example responsibilities:
  - `showHome(popToRoot:)`
  - `showExplore()`
  - `showImportWalletVersion()`
  - `showTemporaryViewAccount(accountId:)` or equivalent semantic route
  - Access to active presentation anchor for modal presentation (if needed)

### 3) RootContainerLayoutResolver
- Chooses active container by width/traits.
- Current behavior:
  - iPad + wide screen: split layout.
  - Otherwise: tab layout.
- Future: support more than one split variant.

### 4) Stable JS bridge host
- Keep bridge VC attached to a stable parent that stays visible across intro/active container swaps.
- Avoid moving bridge under tab/split-specific child VCs.

## Incremental plan (tab-only now)
### Phase 1: Centralize root transitions
- Add `RootStateCoordinator` in `AirAsFramework`.
- Move intro/active root switching API into coordinator.
- Replace direct root transitions in:
  - `SplashVC.navigateToIntro/navigateToHome`
  - `IntroModel.onOpenWallet`
  - restart flow triggered by account reset
Status: completed

### Phase 2: Introduce root routing abstraction
- Add `RootContainerRouting` protocol.
- Implement `TabRootContainerRouter` backed by `HomeTabBarController`.
- Update `AppActionsImpl` to depend on router protocol instead of direct `HomeTabBarController` API.
Status: completed

### Phase 3: Decouple store from UI restart
- Replace direct `restartApp()` call from `AccountStore.resetAccounts()` with a coordinator-level trigger/event handling path.
- Keep domain layer responsible for data only.
Status: completed

### Phase 4: Stabilize bridge host parent
- Move bridge hosting target from active screen VC to stable root-host container.
- Ensure host remains on-screen in both `.intro` and `.active`.
Status: completed
Notes:
- Added `RootHostVC` as stable `window.rootViewController`.
- `RootStateCoordinator` now swaps host content (`.intro` nav vs `.active` container).
- Bridge is moved to `RootHostVC` instead of per-state VC.

### Phase 5: Width resolver wiring (still tab-only behavior)
- Add `RootContainerLayoutResolver` and route active container creation through it.
- Return current tab layout unconditionally for now.
- No split UI creation in this phase.
Status: completed (tab-only)

### Phase 6: iPad split root layout
- Add `SplitRootViewController` and sidebar controller in `AirAsFramework/SplitRoot`.
- Extend `RootContainerLayoutResolver` to select split layout on iPad regular width.
- Add split router implementation under `RootContainerRouting` and let `AppActionsImpl` choose tab vs split router dynamically.
- Add dedicated split home controller (`SplitHomeVC`) as a separate `ActivitiesTableViewController` subclass.
Status: in progress
Implemented in first pass:
- Root split container + sidebar with card area, tab buttons, and quick actions.
- Width-based resolver switch (`>= 700` on iPad) to split layout.
- `SplitRootContainerRouter` wired into `AppActionsImpl`.
- `SplitHomeVC` used in split home stack; split-specific behavior is no longer added to `HomeVC`.
- Split UI moved under dedicated folders: `AirAsFramework/SplitRoot` and `AirAsFramework/SplitHome`.
- Sidebar extracted to a separate file (`SplitRootSidebarViewController`) and hosted inside its own `WNavigationController`.
Implemented in current iteration:
- Added shared split state model (`SplitRootViewModel`) with `SplitRootTab` enum; `SplitRootViewController` observes selected tab state and updates secondary content.
- Split home quick actions row moved to dedicated components (`SplitHomeActionButton`, `SplitHomeActionsRowView`) and rendered via horizontal `UICollectionView`.
- Quick action item geometry aligned with spec: fixed `96x96`, spacing `16`, rounded corners, supports horizontal scrolling in narrow widths.
- First row now contains both sections in one cell:
  - actions row at top
  - assets row below with `24` spacing
- Added dedicated split-home assets row (`SplitHomeAssetsRowView`) as a second horizontal `UICollectionView` in first row.
- Assets row now uses `WalletAssetsViewModel` and hosts real compact feature controllers (`WalletTokensVC`, `NftsVC`) per `displayTabs`.
- Assets cell geometry aligned with spec:
  - card area `368x404`
  - labeled cell total height `424`
Pending refinements:
- Sidebar home card visuals/data parity with existing Home card design.
- Sidebar action/content polish and final UX behavior details.
- Finalize copy/localization and visual polish of split-home section titles.

## Acceptance criteria for this phase
- There is one code path that changes root state (`RootStateCoordinator`).
- `AppActionsImpl` no longer depends on concrete `HomeTabBarController` outside router implementation.
- Removing all accounts transitions to `.intro` through coordinator path, not direct VC restart calls from store.
- Active layout remains visually/functionally identical to current tab setup.
- JS bridge host remains attached to a stable parent and continues receiving updates across root state changes.
Status: all criteria met

## Out of scope (explicitly deferred)
- Runtime active-layout switching on trait changes while app is already active.
- Additional split variants beyond the first implementation.
- Major refactor of all modal/push helpers beyond root routing boundaries.

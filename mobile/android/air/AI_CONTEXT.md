# Android Air AI Context

## Scope
- Android Air lives in `mobile/android/air` and is the implementation target for this subtree.
- Android Classic lives in sibling `mobile/android/app` and may be used as a behavior reference, but changes should stay in Android Air unless a task explicitly says otherwise.

## Repository Shape
- `app/` - Android Air application module.
- `SubModules/` - Native feature and platform modules.
- `docs/` - Android Air architecture notes such as submodules and JS bridge behavior.

## Architecture
- Startup flows through `MTWAirApplication` -> `AirAsFrameworkApplication` -> `MainWindow` -> `SplashVC`.
- Core wallet and blockchain logic run in the JavaScript SDK loaded through `JSWebViewBridge`.
- Native-to-SDK calls should go through `WalletCore.call(ApiMethod...)` or existing helpers in `walletcore/api`.
- SDK updates flow into singleton stores and then through `WalletCore.notifyEvent(...)`.
- Shared state and orchestration already exist in `WalletCore`, `WalletContextManager`, and singleton stores such as `AccountStore`, `ActivityStore`, `BalanceStore`, `TokenStore`, `NftStore`, `StakingStore`, and `ConfigStore`.

## Native UI Patterns
- Prefer the existing Android Air stack: `WViewController`, `WViewControllerWithModelStore`, `WNavigationController`, `WWindow`, `WRecyclerViewAdapter`, `WThemedView`, and shared UI from `UIComponents`.
- Reuse sibling submodules before creating new base views, helpers, models, storage keys, or formatting code.
- Reuse `ThemeManager`, `WColor`, `LocaleController`, `WGlobalStorage`, `WSecureStorage`, and `WCacheStorage` rather than introducing parallel systems.
- Do not introduce Compose, Fragments, or a new navigation/state architecture unless the task explicitly requires them.

## Behavioral Guardrails
- Keep blockchain and wallet business logic in the JS SDK unless the task explicitly requires native-only behavior.
- Use `WalletCore`, existing stores, and `WalletEvent` updates instead of duplicating state inside screens.
- Register and unregister `WalletCore.EventObserver` symmetrically.
- If a task says "classic already does X, do the same in air", inspect Classic for behavior only and implement the change using Air patterns.

## Verification
- Use `npm run mobile:build:sdk` after SDK, i18n, or shared bundle changes.
- For targeted Air validation, use the parent wrapper with a submodule task, for example:
  - `cd mobile/android && ./gradlew :air:SubModules:WalletCore:assembleDebug`
- For full Android integration validation, use:
  - `cd mobile/android && ./gradlew assembleDebug`
- Do not rely on the standalone `mobile/android/air` Gradle wrapper for validation until its version-catalog setup is fixed.

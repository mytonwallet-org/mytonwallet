# AGENTS

## Orientation
- Air is the native Swift-based iOS wallet; Classic is the Capacitor build that still ships in `App/`. Most native work happens under `Air/`.
- Core TON blockchain logic lives in a TypeScript bundle that Air loads through a hidden WebView bridge; keep native code focused on UI, device APIs, and orchestration.

## Repository Map
- `Air/` – Native iOS workspace (`MyTonWalletAir.xcodeproj`) plus docs and tooling.
  - `MTW Pure Air/` – Not currently used. Ignore.
  - `SubModules/` – Feature-specific Swift packages; see below.
  - `docs/` – Architecture notes and dependency diagrams.
  - `scripts/` – Dependency graph tooling (`analyze_dependencies.sh`).
- `App/` – Classic Capacitor shell and shared entrypoint. Contains the Web bundle (`App/public`) built from TypeScript/React sources.
- `capacitor-cordova-ios-plugins/` – Native plugins used by the Classic shell.

## Native Modular Layout (`Air/SubModules`)
Each folder is a SwiftPM-style module referenced from the Xcode project.
- **AirAsFramework** – Bootstraps Air, handles splash and deeplink routing (`SharedSplashVC`).
- **UI*** modules – Feature UIs (CreateWallet, Passcode, Home, Assets, Token, Receive, Send, Earn, Browser, InAppBrowser, QRScan, Settings, Dapp, Components, Charts, etc.).
- **WalletCore** – Bridge between Swift UI code and the JS SDK (`Api.swift`, `JSWebViewBridge.swift`).
- **WalletContext** – Shared themes, strings, and model helpers.
- **Ledger**, **WReachability**, **SwiftSignalKit**, **GZip**, etc. – Supporting services and third-party bindings.
Consult `docs/submodules.md` for a narrative description and dependencies.

## TypeScript Bridge
- The JS SDK bundle is produced by the web project and copied into `App/App/public` (multiple hashed `.js` files plus `main.*.js`).
- Air loads this bundle via `WalletCore/JSWebViewBridge`, injecting it into an off-screen `WKWebView` so Swift can `callApi` and receive events (`Api` singleton in `WalletCore/Api/Api.swift`).
- Regenerate the bundle with `npm run mobile:build:sdk` after TS API changes (`Air/README.md`).

## Build & Run
1. Install Xcode 16.3 and Node 24 (`Air/README.md`).
2. From the repo root, build the web bundle: `npm run build`.
3. Launch the native app with `npm run mobile:run:ios` or open `MyTonWalletAir.xcodeproj` in Xcode.
4. Use `npm run mobile:build:sdk` when bridge APIs change to keep Swift/JS in sync.

## Agent Guidelines
- Target iOS 26 APIs; lean on Swift Concurrency (`async`/`await`, `actors`) and Observation (`ObservableObject`, `@State`) instead of legacy callbacks or Combine where practical.
- Favor modular SwiftUI first; drop to UIKit only when platform capabilities demand it.
- Keep feature code inside the matching `SubModules` folder and wire dependencies through `WalletCore` rather than duplicating TS logic.
- When Classic needs updates, touch `App/` and its plugins; do not mix Classic assets into Air targets.

### Swift Implementation Guardrails
- **Layouts**: Avoid catch-all `GeometryReader`; prefer the modern layout system (`Layout` protocol, `ViewThatFits`, `ContainerRelativeFrame`) and the native grid APIs (`Grid`, `VGrid`, `HGrid`) for adaptive designs.
- **Navigation & State**: Flows are coordinated via UIKit navigation controllers and the shared `AppActions` entry points (`Air/SubModules/AirAsFramework/AppActionsImpl.swift`). Keep SwiftUI views screen-scoped while delegating cross-screen routing through `AppActions`. Use the Observation system to manage per-screen state cleanly.
- **Concurrency**: Use structured concurrency for async workflows. Bridge legacy completion handlers by wrapping them in `async` functions; keep UI updates on the main actor.
- **Lists & Collections**: For UIKit, always back `UICollectionView` with a diffable data source and compositional layout; for SwiftUI lists, opt into `.listStyle(.insetGrouped)` or custom list styles to match design. When pagination is needed, integrate the `UICollectionViewDiffableDataSource.SectionSnapshot` APIs or SwiftUI `ScrollViewReader` with `ScrollTargetBehavior`.
- **Animations & Feedback**: Use `TimelineView`, `PhaseAnimator`, and spring animations introduced in iOS 23+ for smooth motion; prefer `FeedbackGenerator` subclasses for haptics.
- **Interoperability**: When embedding UIKit in SwiftUI (or vice versa), keep the boundary thin via `UIViewControllerRepresentable`/`UIHostingController` and pass data through lightweight adapters rather than shared singletons.
- **Testing**: Extend the existing snapshot/unit test targets before adding new ones; isolate JS bridge dependencies using protocol abstractions so they can be mocked in tests.

## Reference Docs
- `Air/README.md` – Build primitives and SDK regeneration.
- `Air/docs/submodules.md` – Feature module overview.
- `Air/docs/js-bridge.md` – WebView bridge design.
- `Air/scripts/README.md` – Dependency analysis tooling.

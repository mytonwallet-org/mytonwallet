# Claude Instructions — MyTonWallet

This repository contains production-critical code for a multi-platform cryptocurrency wallet.
Claude MUST behave strictly as a senior software engineer performing architectural and security reviews.

---

## 0) Operating Modes

### Default: PR Review Mode (automatic)
Your job is to perform a **senior-level review** and leave **high-signal PR review comments**.
- Do **not** push code.
- Do **not** open PRs.
- Do **not** propose style/formatting changes.

### Manual: Implementation Mode (`/claude ...`)
When explicitly asked (e.g., “fix this”, “implement”, “open PR”), you may modify code and follow the implementation guidelines below.

---

## 1) Core Principles (All Modes)

- **Be concise.**
- **Reuse existing code.** Search before creating new types/functions/components.
- **No new libraries.** Use existing dependencies only. If truly impossible, stop and explain why.
- **Commit & PR titles** follow the **Commit Messages** section of [CODESTYLE.md](./CODESTYLE.md#commit-messages). Format is strict: `[Tag] Component / Area: Imperative description`. No conventional-commit prefixes (`fix:`, `feat:`), no past tense, no missing space after `]`.

### NO NOISE (strict)
- Do NOT comment on formatting, naming, spacing, lint, or code style.
- Do NOT suggest prettier/eslint/stylelint-driven changes.
- Do NOT request comments/documentation unless required for safety/correctness.
- Do NOT generate jokes/poems.
- Do NOT suggest large refactors unrelated to the PR scope.
- Do NOT request stylistic changes already enforced by CI.
- Do NOT request new abstractions unless it clearly reduces complexity or fixes duplication in a hot area.
- Do NOT assume platform behavior without considering build flags and targets.

### Review Output Constraints (PR Review Mode)
- **Max 5 findings** per review. If more exist, group them under 1–2 headings.
- Each finding MUST include:
  - **Location** (file path + symbol name; line numbers if available)
  - **Risk** (one sentence)
  - **Evidence** (why this is a risk, tied to the code)
  - **Minimal fix** (smallest actionable change)
- Tag each finding as:
  - **[Blocker]** security/funds/correctness regression likely
  - **[Suggestion]** worthwhile improvement, but not required
- Avoid “high level summary” unless explicitly requested.
- If there are no meaningful issues, explicitly say:
  > "No critical issues found."

---

## 2) Top Review Priorities (PR Review Mode)

Review in this order. Optimize for preventing expensive regressions.

1. **Security**
   - Handling of mnemonics/private keys/signing payloads
   - Electron IPC and preload exposure
   - Deeplinks/URLs/query params/protocol handlers
   - External APIs, message passing, iframe/postMessage
   - Injection risks (XSS, RCE, command execution)
   - Never log sensitive data (seeds/keys/signing payloads)

2. **Funds Safety**
   - Transaction construction and signing flows
   - Fee calculation
   - Network/chain selection correctness
   - Address validation and formatting
   - Replay/double-send risks
   - Confusing UI states that may cause wrong-chain/wrong-address actions

3. **Electron Boundary & Dangerous APIs**
   - Treat IPC as a security boundary (renderer is untrusted)
   - Be cautious with:
     - `shell.openExternal`
     - protocol handlers (`ton://`, `tc://`, `mtw://`, and any custom schemes)
     - navigation / `webContents` permissions
     - file downloads and path handling
   - Never expose filesystem/Node APIs to renderer without strict validation/allow-lists

4. **XSS / Injection & Rendering**
   - Any HTML/markdown rendering or user-generated content
   - Unsafe interpolation into HTML/CSS/URL contexts
   - `dangerouslySetInnerHTML`
   - `postMessage` without origin allow-lists
   - `eval`, `new Function`, dynamic code execution

5. **Correctness & Type Safety**
   - Edge cases, nullability, unexpected unions
   - Serialization boundaries (API ↔ UI, cache migrations)
   - Avoid unsafe casts; prefer narrowing/type guards
   - Ensure error branches are handled (transport vs business errors)

6. **Architectural Integrity**
   - Regressions in module boundaries
   - Hidden coupling between layers
   - Breaking assumptions used elsewhere in the app
   - State ownership mistakes and duplicated derived state

7. **Performance & Memory**
   - Unbounded listeners/subscriptions
   - Hot-path allocations
   - Global store / selectors causing rerenders
   - Electron main ↔ renderer inefficiencies

8. **Cross-Platform Consistency**
   - Web / Extension / Electron / Mobile parity
   - Platform-specific conditionals
   - Browser vs Node vs Mobile runtime assumptions

---

## 3) State Management Rules (Review-Critical)

We use TeactN for a lightweight global store. All state lives under `src/global/`.

### Folder Structure (context)
- `actions/`: Action handlers grouped by domain (`api/`, `apiUpdates/`, `ui/`)
- `selectors/`: Pure read functions; **must not allocate** new arrays/objects
- `reducers/`: Domain reducers (used inside action handlers when needed)
- `types.ts`: Global state and action payload types
- `cache.ts`: LocalStorage cache, migrations, throttled persistence
- `index.ts`: bindings: `getGlobal`, `setGlobal`, `getActions`, `addActionHandler`, `withGlobal`

### Review must flag
- Selectors that allocate arrays/objects (break memoization / rerender storms)
- `withGlobal` mappers returning new object/array literals (including `[]`, `{}`)
- New persisted state without migration updates
- Accidental cache invalidation or stale memoized selectors
- Subscription leaks (listeners that are not removed)

### Persistence & migrations
- Global is serializable; avoid non-serializable structures.
- Any change affecting persisted state MUST consider:
  - backward compatibility
  - user data survival
  - `cache.ts` migrations (`migrateCache`) and `STATE_VERSION` bump when needed
- If a new required section is added to `GlobalState`, update `migrateCache`.
- If global types or nested objects change, verify migration from older cached states.

---

## 4) Electron-Specific Rules (Review-Critical)

- IPC is a **security boundary**
  - Validate all inputs
  - Never trust renderer
  - Explicit allow-lists only
- URLs / deeplinks:
  - Strict validation and allow-lists
  - No dynamic protocol execution
  - No implicit redirects
  - Validate and sanitize any user-controlled URLs before opening
- Main process must not:
  - execute arbitrary shell commands
  - expose fs/network without validation

---

## 5) Tests & Verification (Review Guidance)

- Tests are required ONLY when:
  - logic changes
  - security-sensitive behavior changes
  - regressions are plausible
- Do NOT request tests for:
  - refactors without logic change
  - cosmetic changes

### Build / Check Commands (context)
- `npm run build`
- `npm run check`
- `npm test`
- `npm run test:playwright`

### Mobile Build Instructions
Mobile apps live in `mobile/`. Native code is in `mobile/ios/Air/` (Swift) and `mobile/android/air/` (Kotlin), but builds must run from the parent directories.

**Prerequisites** — run once before building native projects:
```
npm run mobile:build:production
```
This runs webpack with `IS_CAPACITOR=1` and `cap sync`, which copies web assets and resolves native dependencies (Gradle version catalogs, CocoaPods, SPM packages).

**Android** — build from `mobile/android/`:
```
cd mobile/android && ./gradlew assembleDebug
```
The `air/` subdirectory is included as a Gradle subproject. The version catalog (`gradle/libs.versions.toml`) lives in `mobile/android/gradle/`.

**iOS** — build from `mobile/ios/` using the workspace:
```
cd mobile/ios && xcodebuild build -workspace App/App.xcworkspace -scheme MyTonWallet -destination 'generic/platform=iOS Simulator'
```
The workspace resolves SPM packages with correct versions.

**Quick single-module compile** — to verify a change without a full app build:
- **Android** — Air modules live at the Gradle path `:air:SubModules:<Module>`, not their display name, so `./gradlew :WalletCore:…` fails with "project 'WalletCore' not found". List the real paths with `./gradlew projects`. Example:
```
cd mobile/android && ./gradlew :air:SubModules:WalletCore:compileDebugKotlin
```
- **iOS** — `mobile/ios/Air` is a Swift Package. Its checked-in `MyTonWalletAir.xcodeproj` may be an empty generated shell (no `project.pbxproj`); `xcodebuild` then picks that shell over `Package.swift` and fails to read the project. Build a package scheme directly (move the shell aside first if it exists), e.g.:
```
cd mobile/ios/Air && xcodebuild build -scheme UIPortfolio -destination 'generic/platform=iOS Simulator' -skipMacroValidation -skipPackagePluginValidation
```

Claude MAY suggest running them, but MUST NOT fail a review solely because they were not run.

---

## 6) API Usage Guide (Context + Review Pitfalls)

### Overview
- Background API via `initApi` and `callApi` from `src/api/`
- Default transport is Web Worker provider (`src/api/providers/worker/connector.ts`)
- `callApi(methodName, ...args)` returns Promise (or value in direct mode)
- `callApi` may return `undefined` on transport errors. Handle `undefined`.

### Review must flag
- Missing handling of `undefined` (transport) and `{ error }` / union error branches
- Heavy API calls on keystrokes without debounce/gating
- Duplicate parallel calls with identical params (prefer centralization in global actions)

### Methods structure (context)
`src/api/methods/` grouped by domain: `auth.ts`, `accounts.ts`, `wallet.ts`, `transactions.ts`, `nfts.ts`, `domains.ts`, `staking.ts`, `tokens.ts`, `swap.ts`, `notifications.ts`, `prices.ts`, `dapps.ts`, `tonConnect.ts`, `polling.ts`

### Performance / global store pitfalls (review-critical)
- Avoid increasing global containers (`withGlobal`) inside loops (multiplies recomputation)
- Avoid loops inside `mapStateToProps`
- Avoid returning new arrays/objects from `mapStateToProps`

---

## 7) Multichain Architecture Guide (Review-Critical)

### Goal
Keep ~99% of the code chain-agnostic. Adding a new chain should not require mass refactors.

### Only allowed chain-specific declaration points
Unique per-chain data MUST exist only here:
1. `ApiChain` union — `src/api/types/misc.ts`
2. `CHAIN_CONFIG` — `src/util/chain.ts`
3. SCSS per-chain variables map `$byChain` — `src/styles/scssVariables.scss`
4. `ApiWalletByChain` mapping — `src/api/types/storage.ts`
5. chains registry — `src/api/chains/index.ts`
6. Font icon: `src/assets/font-icons/chain-<chain>.svg`
7. Optional: native token styles in `TOKEN_CUSTOM_STYLES` — `src/config.ts`

### SDK implementations
- Chain SDK code lives in `src/api/chains/<chain>/` implementing `ChainSdk<'chain'>`
- `methods/*` MUST talk to chains only through the `chains` registry
- Reverse imports are forbidden (except type-only imports)

### Unsupported features
- Interface parity required: add stubs for unsupported chains
- Do NOT rely on try/catch around API calls to detect unsupported features
- UI must not allow initiating unsupported actions; use `CHAIN_CONFIG` feature flags

### Review must flag
- New raw `if (chain === 'ton' | 'tron')` outside permitted zones
- Missing stubs for new `ChainSdk` methods
- Scattered chain-specific constants that belong in `CHAIN_CONFIG`
- UI that calls methods that are unsupported for the selected chain

---

## 8) PR Review Checklist (Multichain)
Before approving multichain-related PR:
- [ ] No new raw `if (chain === 'ton' | 'tron')` outside permitted zones
- [ ] New chain data only in allowed files
- [ ] `ChainSdk` method parity preserved
- [ ] Import directions respected (no reverse dependency)
- [ ] Unsupported features have uniform stub
- [ ] Config flags used instead of repeated branching
- [ ] Legacy areas not expanded
- [ ] UI does not depend on arbitrary key order like `...byChain` object keys

---

# Implementation Guidelines (ONLY when asked to change code)

The sections below apply ONLY when you are asked to implement changes or create code.
In PR reviews, do NOT comment on these unless they directly cause a bug, security issue, or measurable performance regression.

Follow the code style rules in **[CODESTYLE.md](./CODESTYLE.md)** — including the **[Commit Messages](./CODESTYLE.md#commit-messages)** section, which governs every commit message and PR title.

---

## 9) Explicitly Forbidden (All Modes)

- Formatting suggestions
- Renaming variables for style
- “Consider adding comments”
- “This could be cleaner”
- Any feedback that TypeScript/ESLint/Stylelint/Prettier would catch automatically (unless it indicates a real logic/security/perf issue)

---

## 10) Success Criteria

A good Claude review:
- finds issues a strong senior engineer would notice
- saves human reviewer time
- prevents costly regressions
- does not distract with trivialities

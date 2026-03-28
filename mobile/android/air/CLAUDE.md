# Claude Instructions - Android Air

This file supplements the root `CLAUDE.md` for work inside `mobile/android/air`.
Use [AI_CONTEXT.md](AI_CONTEXT.md) as the shared Android Air context.

## Scope
- Android Air is the implementation target for this subtree.
- Android Classic is reference-only unless a task explicitly says to modify it.

## Implementation Expectations
- Use Android Air patterns from the shared context file rather than generic Android defaults.
- Keep bridge, storage, navigation, and state changes aligned with existing stores and helpers instead of introducing parallel abstractions.

## High-Risk Areas
- Deeplink parsing and routing through `SplashVC`, `DeeplinkParser`, and `WalletContextManager`.
- Bridge calls, native bridge exposure, and data crossing `JSWebViewBridge`.
- Secure storage, global storage, cache storage, and account switching flows.
- Ledger/native-call paths and any device-permission or external-app interaction.
- Observer lifecycle, duplicate event subscriptions, and stale screen state after account/theme changes.

## Verification
- Use the verification commands from [AI_CONTEXT.md](AI_CONTEXT.md).

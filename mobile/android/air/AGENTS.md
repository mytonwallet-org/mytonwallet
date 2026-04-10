# AGENTS

Use [AI_CONTEXT.md](AI_CONTEXT.md) as the shared Android Air source of truth.

## Codex Notes
- Work inside Android Air unless the task explicitly targets Classic.
- If the task references Classic behavior, inspect Classic as a reference and implement the result in Air.
- Prefer existing Air primitives and stores over new abstractions.
- Keep native changes focused on UI, device APIs, navigation, and orchestration. Do not move wallet business logic out of the JS SDK without explicit reason.

## Build
- Follow the commands in [AI_CONTEXT.md](AI_CONTEXT.md).

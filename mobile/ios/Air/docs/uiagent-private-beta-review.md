# UIAgent Private Beta Review

Date: 2026-03-12

Scope: native iOS `UIAgent` screen, real backend integration, app tab integration.

## Current Assessment

Ready for a team-only private beta with known follow-ups.

## Resolved Since Review

### Transport concurrency safety

Files:
- `mobile/ios/Air/SubModules/UIAgent/AgentHTTPStreamingTransport.swift`
- `mobile/ios/Air/SubModules/UIAgent/AgentRealBackend.swift`

Problem:
- `AgentHTTPStreamRequestHandler` is marked `@unchecked Sendable`.
- Its mutable state is touched from `URLSession` delegate callbacks and from `AsyncThrowingStream.onTermination` / `cancel()`.
- `clearChat`, backend switching, or screen teardown during an active stream can race state mutation and `finish()`.

Resolution:
- Shared mutable transport state is now synchronized inside `AgentHTTPStreamingTransport`.
- Cancellation, delegate callbacks, and completion all go through the same locked state transitions.

Residual note:
- The transport still uses `@unchecked Sendable`, but it is now backed by explicit synchronization instead of unsafely sharing mutable state.

## Non-Blocking Issues / Follow-Ups

### Raw backend error bodies are shown in chat

Files:
- `mobile/ios/Air/SubModules/UIAgent/AgentHTTPStreamingTransport.swift`
- `mobile/ios/Air/SubModules/UIAgent/AgentRealBackend.swift`

Problem:
- Non-2xx HTTP response bodies are surfaced directly as user-visible system messages.

Risk:
- Proxy pages, HTML error responses, or server diagnostics can appear in the transcript.

Recommendation:
- Log the raw body, but show a generic user-facing error message in chat.

### Streaming markdown should be formatted incrementally

Files:
- `mobile/ios/Air/SubModules/UIAgent/AgentMessageTextRenderer.swift`
- `mobile/ios/Air/SubModules/UIAgent/AgentMessageCells.swift`

Current behavior:
- Final assistant messages render markdown.
- Streaming assistant messages stay plain until completion.

Desired improvement:
- Apply best-effort markdown formatting during streaming too, without waiting for the final chunk.

Suggested approach:
- Continue using a tolerant preprocessing step.
- Re-render partial assistant text as markdown on each chunk.
- When parsing fails due to incomplete syntax, fall back to the plain-text attributed renderer for that frame.

### Overlapping sends are allowed for now

Files:
- `mobile/ios/Air/SubModules/UIAgent/AgentVC.swift`
- `mobile/ios/Air/SubModules/UIAgent/AgentRealBackend.swift`

Decision:
- Allow multiple messages while a prior response is still streaming for the private beta.

Known risk:
- Assistant responses may interleave visually and server-side conversation state may become ambiguous.

Future fix:
- Either serialize sends per conversation or explicitly support a queue.

## Accepted Decisions

### Local initial greeting

Decision:
- Keep the local initial assistant greeting for the real backend.

Reason:
- It avoids an empty first-open state and is acceptable for the private beta.

# LottieKit Further Improvements

This document captures the next improvements that would materially increase correctness, performance, and integration quality after the current extraction pass.

## Highest Priority

- Add tests.
  Focus first on cache version invalidation, disk-budget pruning, async setup cancellation, and visibility-driven pause/resume. Those are the highest-risk behaviors for app integration.

- Replace the current ARGB frame cache format with a more space-efficient codec.
  The current cache is simple and maintainable, but disk-heavy. The next step is a Telegram-style intermediate format with compressed keyframes and deltas, introduced behind the existing cache versioning.

- Add cache metadata and integrity validation.
  Persist explicit metadata for format version, dimensions, frame count, fps, and loop semantics so corrupt or mismatched cache entries can be rejected cheaply before playback.

- Expose cache policy at the integration boundary, not only per view.
  The package already supports `disabled`, `automatic`, and `always`, but production integration will likely also want app-level policy decisions based on asset class, expected replay frequency, power state, or low-storage conditions.

## Playback And Scheduling

- Introduce explicit prewarming APIs.
  The current pipeline warms lazily from the view. Production code will likely want to prepare animations before they appear onscreen.

- Tighten visibility semantics.
  `externalShouldPlay` and effective UIKit visibility are enough for the extraction, but production integration may need view-controller visibility, app lifecycle, and scroll-based visibility thresholds.

- Add backpressure-aware startup.
  Setup is now off-main, but playback still starts as soon as preparation is ready. A stronger version would delay start until the renderer has enough buffered work to avoid a visibly bad first loop.

- Consolidate playback metrics into a reusable telemetry surface.
  The demo exposes FPS and prep timing, but the library itself should expose lightweight counters for dropped frames, cache hit rate, prepare duration, and active backend.

## Cache And Storage

- Add memory budgeting alongside disk budgeting.
  The disk cache now has a basic LRU policy, but in-memory reuse is still opportunistic. A real budget for decoded frame residency would make behavior more predictable under memory pressure.

- Add cache trimming hooks for system events.
  Respond to memory warnings, background transitions, and low-disk signals by dropping memory state and aggressively pruning disk state.

- Separate cache index data from frame payloads.
  A small manifest/index file would make LRU updates, validation, and pruning cheaper than relying only on filesystem timestamps.

## Rendering Path

- Revisit non-`UIImageView` presentation only if profiling shows it is needed.
  The current `UIImageView` path is simpler and adequate for the extracted demo. A move to `CVPixelBuffer` or a custom layer should be justified by measured Render Server or GPU wins in real integration scenarios.

- Add controlled frame dropping.
  If decode or presentation falls behind, the renderer should be able to skip stale frames intentionally instead of trying to catch up frame-by-frame.

## API And Packaging

- Add SwiftUI wrappers after the UIKit API stabilizes.
  That should be a thin layer over `LottieAnimationView`, not a separate playback implementation.

- Split the public package docs into “integration guide” and “architecture notes”.
  The current README is enough for extraction, but production adoption will benefit from a short getting-started guide and a separate technical architecture document.

- Remove leftover extraction artifacts as part of repo bootstrap.
  The nested repo metadata is intentionally removed in this pass, but the standalone repository should also get clean package-level CI, formatting, and release metadata.

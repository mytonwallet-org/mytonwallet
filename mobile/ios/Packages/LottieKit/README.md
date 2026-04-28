# LottieKit

`LottieKit` is a standalone RLottie-based Lottie renderer extracted from Telegram work. The public API is expressed in generic Lottie terms and the package is ready to move into its own repository.

## Public API

- `LottieAnimationView`: `UIImageView` subclass for still, once, and loop playback
- `LottieAnimationSource`: local file or in-memory source
- `LottieAnimationCache`: cache lifecycle entry point and store configuration surface
- `LottieAnimationCachePolicy`: per-animation cache policy (`disabled`, `automatic`, `always`)
- `LottieAnimationInfo`, `LottieAnimationRenderEvent`, `LottieAnimationPreparationEvent`

`LottieAnimationView.setAnimation` is async so file IO, gzip inflate, and metadata setup can happen off the main thread before the view installs the loaded animation.

## Internal Architecture

The render pipeline is intentionally split by responsibility:

- `AnimationFrameRenderer`: RLottie wrapper that renders raw ARGB frames
- `AnimationPipeline`: chooses between direct rendering and cache-backed playback
- `AnimationFrameCacheStore`: owns cache lookup, artifact lifetime, and build tasks
- `AnimationFrameCacheBuilder` + `AnimationFrameCacheWriter`: build on-disk frame caches from rendered frames
- `AnimationFrameCacheAsset`: memory-mapped cache reader used during playback
- `AnimationFrameBuffer` + `AnimationCompression`: frame storage and LZFSE helpers

That separation keeps the core data flow explicit:

1. source data is loaded and decompressed
2. RLottie renders frames directly for immediate display
3. optional cache warmup renders frames through the same renderer into the cache writer
4. once the cache exists, playback can decode cached frames instead of re-rendering them

## Package Layout

- `Package.swift`: Swift package manifest
- `Sources/LottieKit/Public`: public API surface
- `Sources/LottieKit/Internal`: render pipeline, cache, and support internals
- `Sources/RLottieBinding`: vendored RLottie bridge and rlottie sources
- `Sources/GZip`: gzip helper used by Telegram's Lottie path
- `Examples/GiftRendererDemoApp`: checked-in example app with a local package dependency

## Example App

Open:

- `Examples/GiftRendererDemoApp/GiftRendererDemoApp.xcodeproj`

The example project is checked in directly and does not depend on Bazel or project-generation tools.

## Scope

- The package follows Telegram's RLottie-backed `LottieComponent` path, not the sticker/emoji multi-animation pipeline.
- The current cache format is an LZFSE-compressed ARGB frame cache, optimized for clarity and reuse rather than Telegram's full production codec.
- Telegram-specific resource fetching and `lottie-ios` composition effects are still out of scope.

import Foundation

public enum LottieAnimationCache {
    public static func configure(_ options: LottieAnimationCacheOptions) async {
        await AnimationFrameCacheStore.shared.setOptions(options)
    }

    public static func currentOptions() async -> LottieAnimationCacheOptions {
        await AnimationFrameCacheStore.shared.currentOptions()
    }

    public static func clearAll() async {
        await AnimationFrameCacheStore.shared.clearAll()
    }
}

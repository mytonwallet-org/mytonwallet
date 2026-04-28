import Foundation

enum AnimationFrameCacheBuilder {
    static func buildAsset(
        outputURL: URL,
        info: LottieAnimationInfo,
        width: Int,
        height: Int,
        data: Data,
        cacheKey: String
    ) async -> AnimationFrameCacheAsset? {
        let renderer = AnimationFrameRenderer(data: data, cacheKey: cacheKey)
        guard let writer = AnimationFrameCacheWriter(
            outputURL: outputURL,
            frameCount: info.frameCount,
            frameRate: info.frameRate,
            width: width,
            height: height
        ) else {
            return nil
        }

        for frameIndex in 0 ..< info.frameCount {
            if Task.isCancelled {
                writer.cancel()
                return nil
            }
            guard let frameBuffer = await renderer.renderFrame(index: frameIndex, width: width, height: height) else {
                writer.cancel()
                return nil
            }
            guard writer.appendFrame(frameBuffer) else {
                writer.cancel()
                return nil
            }
        }

        if Task.isCancelled {
            writer.cancel()
            return nil
        }

        return writer.finish()
    }
}

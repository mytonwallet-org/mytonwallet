import Foundation
@preconcurrency import RLottieBinding

actor AnimationFrameRenderer {
    private let data: Data
    private let cacheKey: String

    private var animation: LottieInstance?

    init(data: Data, cacheKey: String) {
        self.data = data
        self.cacheKey = cacheKey
    }

    func renderFrame(index: Int, width: Int, height: Int) -> sending AnimationFrameBuffer? {
        let animation: LottieInstance
        if let existingAnimation = self.animation {
            animation = existingAnimation
        } else {
            guard let createdAnimation = LottieInstance(
                data: self.data,
                cacheKey: self.cacheKey
            ) else {
                return nil
            }
            self.animation = createdAnimation
            animation = createdAnimation
        }

        let bytesPerRow = AnimationCompression.alignUp(width * 4, to: 64)
        let frameBuffer = AnimationFrameBuffer(width: width, height: height, bytesPerRow: bytesPerRow)
        animation.renderFrame(
            with: Int32(index),
            into: frameBuffer.bytes,
            width: Int32(width),
            height: Int32(height),
            bytesPerRow: Int32(bytesPerRow)
        )
        return frameBuffer
    }
}

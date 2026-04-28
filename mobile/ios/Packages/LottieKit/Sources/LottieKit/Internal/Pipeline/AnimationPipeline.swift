import Foundation

struct AnimationRenderedFrame {
    let frameBuffer: AnimationFrameBuffer
    let backend: LottieAnimationPlaybackBackend
}

actor AnimationPipeline {
    private let info: LottieAnimationInfo
    private let cacheRequest: AnimationFrameCacheStore.Request
    private let renderer: AnimationFrameRenderer

    private var cacheAsset: AnimationFrameCacheAsset?
    private var prefetchedFrames: [Int: AnimationFrameBuffer] = [:]

    init(
        info: LottieAnimationInfo,
        cacheRequest: AnimationFrameCacheStore.Request,
        renderer: AnimationFrameRenderer
    ) {
        self.info = info
        self.cacheRequest = cacheRequest
        self.renderer = renderer
    }

    func renderFrame(at frameIndex: Int, allowCachedFrames: Bool) async -> sending AnimationRenderedFrame? {
        let normalizedFrameIndex = self.normalizeFrameIndex(frameIndex)

        if allowCachedFrames, let prefetchedFrame = self.prefetchedFrames.consumingValue(forKey: normalizedFrameIndex) {
            return AnimationRenderedFrame(frameBuffer: prefetchedFrame, backend: .cached)
        }

        let cacheAsset = await self.loadCacheIfNeeded(allowCachedFrames: allowCachedFrames)
        if let cacheAsset, let frameBuffer = cacheAsset.decodeFrame(index: normalizedFrameIndex) {
            return AnimationRenderedFrame(frameBuffer: frameBuffer, backend: .cached)
        }

        guard let frameBuffer = await self.renderer.renderFrame(
            index: normalizedFrameIndex,
            width: self.cacheRequest.width,
            height: self.cacheRequest.height
        ) else {
            return nil
        }

        return AnimationRenderedFrame(frameBuffer: frameBuffer, backend: .direct)
    }

    func prepareCache() async -> AnimationFrameCacheAsset? {
        if let cacheAsset = self.cacheAsset {
            return cacheAsset
        }

        if let cachedAsset = await AnimationFrameCacheStore.shared.cachedAsset(for: self.cacheRequest) {
            self.cacheAsset = cachedAsset
            return cachedAsset
        }

        let builtAsset = await AnimationFrameCacheStore.shared.buildAssetIfNeeded(
            request: self.cacheRequest,
            info: self.info
        )
        self.cacheAsset = builtAsset
        return builtAsset
    }

    func cacheStorageSizeBytes() async -> Int64 {
        await AnimationFrameCacheStore.shared.storageSizeBytes(for: self.cacheRequest)
    }

    func prefetch(after frameIndex: Int, count: Int = 3, allowCachedFrames: Bool) async {
        guard allowCachedFrames else {
            self.prefetchedFrames.removeAll()
            return
        }

        guard let cacheAsset = await self.loadCacheIfNeeded(allowCachedFrames: true) else {
            return
        }

        let prefetchCount = min(max(count, 0), self.info.frameCount)
        guard prefetchCount > 0 else {
            return
        }

        for step in 1 ... prefetchCount {
            let index = self.normalizeFrameIndex(frameIndex + step)
            guard self.prefetchedFrames[index] == nil else {
                continue
            }
            if let prefetchedFrame = cacheAsset.decodeFrame(index: index) {
                self.prefetchedFrames[index] = prefetchedFrame
            }
        }

        if self.prefetchedFrames.count > 4 {
            let retainedKeys = Set(self.prefetchedFrames.keys.sorted().suffix(4))
            self.prefetchedFrames = self.prefetchedFrames.filter { retainedKeys.contains($0.key) }
        }
    }

    private func loadCacheIfNeeded(allowCachedFrames: Bool) async -> AnimationFrameCacheAsset? {
        guard allowCachedFrames else {
            return nil
        }
        if self.cacheAsset == nil {
            self.cacheAsset = await AnimationFrameCacheStore.shared.cachedAsset(for: self.cacheRequest)
        }
        return self.cacheAsset
    }

    private func normalizeFrameIndex(_ frameIndex: Int) -> Int {
        let frameCount = max(self.info.frameCount, 1)
        let normalizedFrameIndex = frameIndex % frameCount
        if normalizedFrameIndex < 0 {
            return normalizedFrameIndex + frameCount
        } else {
            return normalizedFrameIndex
        }
    }
}

extension Dictionary {
    mutating func consumingValue(forKey key: Key) -> sending Value? {
        if let value = removeValue(forKey: key) {
            nonisolated(unsafe) let value = value
            return value
        }
        return nil
    }
}

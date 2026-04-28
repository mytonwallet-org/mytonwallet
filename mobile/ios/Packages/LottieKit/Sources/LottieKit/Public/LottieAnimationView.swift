import Foundation
import GZip
import QuartzCore
@preconcurrency import RLottieBinding
import UIKit

@MainActor
public final class LottieAnimationView: UIImageView {
    private struct LoadedSource: Sendable {
        let cacheKey: String
        let decompressedData: Data
        let info: LottieAnimationInfo
    }

    private struct RenderDescriptor: Equatable {
        let sessionID: Int
        let frameIndex: Int
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    public private(set) var animationInfo: LottieAnimationInfo?
    public private(set) var source: LottieAnimationSource?
    public private(set) var currentPlaybackBackend: LottieAnimationPlaybackBackend = .direct
    public private(set) var currentFrameIndex: Int?

    public var cachePolicy: LottieAnimationCachePolicy = .automatic {
        didSet {
            guard self.cachePolicy != oldValue else {
                return
            }
            self.handleCachePolicyChange()
        }
    }

    public var isCachingEnabled: Bool {
        get {
            self.cachePolicy != .disabled
        }
        set {
            self.cachePolicy = newValue ? .always : .disabled
        }
    }

    public var renderingScale: CGFloat = UIScreen.main.scale {
        didSet {
            guard self.renderingScale != oldValue else {
                return
            }
            self.handleRenderTargetChange()
        }
    }

    public var externalShouldPlay: Bool? {
        didSet {
            guard self.externalShouldPlay != oldValue else {
                return
            }
            self.updatePlaybackActivity(resetTiming: true)
        }
    }

    public var currentRenderPixelSize: CGSize {
        let renderSize = self.renderPixelSize()
        return CGSize(width: renderSize.width, height: renderSize.height)
    }

    public var onAnimationLoaded: ((LottieAnimationInfo) -> Void)?
    public var onFrameRendered: ((LottieAnimationRenderEvent) -> Void)?
    public var onPreparationUpdated: ((LottieAnimationPreparationEvent) -> Void)?
    public var onPlaybackBackendChanged: ((LottieAnimationPlaybackBackend) -> Void)?

    public private(set) var lastPreparationDuration: TimeInterval?
    public private(set) var currentCacheSizeBytes: Int64 = 0
    public private(set) var isPreparingPlaybackMetrics: Bool = false

    private var loadedSource: LoadedSource?
    private var animationFrameRange: Range<Int>?
    private var playbackMode: LottieAnimationPlaybackMode = .loop
    private var currentFrame: Int = 0
    private var playbackDirection: Int = 1
    private var segmentEndFrame: Int?
    private var accumulatedTime: CFTimeInterval = 0.0
    private var lastTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var pendingCompletion: (() -> Void)?
    private lazy var displayLinkProxy = DisplayLinkProxy(owner: self)

    private var currentPipeline: AnimationPipeline?
    private var currentRenderTargetPixelSize: (width: Int, height: Int)?
    private var renderSessionID: Int = 0
    private var currentRenderDescriptor: RenderDescriptor?
    private var pendingRenderDescriptor: RenderDescriptor?
    private var renderTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var loadTask: Task<LoadedSource, Error>?
    private var loadRequestID: Int = 0
    private var playbackStartPending = false
    private var preparationStartTimestamp: CFTimeInterval?

    private static let automaticCacheMinimumFrameCount = 60
    private static let automaticCacheMinimumPixelCount = 180 * 180

    public convenience init() {
        self.init(frame: .zero)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.contentMode = .scaleAspectFit
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isHidden: Bool {
        didSet {
            guard self.isHidden != oldValue else {
                return
            }
            self.updatePlaybackActivity(resetTiming: true)
        }
    }

    public override var alpha: CGFloat {
        didSet {
            guard self.alpha != oldValue else {
                return
            }
            self.updatePlaybackActivity(resetTiming: true)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updatePlaybackActivity(resetTiming: true)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.renderCurrentFrame(force: true)
        if self.playbackStartPending {
            self.preparePlaybackIfNeeded()
        }
    }

    public func setAnimation(
        source: LottieAnimationSource,
        playbackMode: LottieAnimationPlaybackMode = .loop,
        displayFirstFrameSynchronously: Bool = false
    ) async throws {
        self.cancelLoadTask()
        self.beginAnimationLoad()
        let requestID = self.loadRequestID

        let loadTask = Task.detached(priority: .userInitiated) {
            try Self.loadAnimationSource(source)
        }
        self.loadTask = loadTask

        let loadedSource: LoadedSource
        do {
            loadedSource = try await loadTask.value
        } catch {
            if requestID == self.loadRequestID {
                self.loadTask = nil
            }
            throw error
        }

        guard requestID == self.loadRequestID else {
            return
        }

        self.loadTask = nil
        self.applyLoadedSource(
            loadedSource,
            source: source,
            playbackMode: playbackMode,
            displayFirstFrameSynchronously: displayFirstFrameSynchronously
        )
        self.onAnimationLoaded?(loadedSource.info)
    }

    public func setAnimationSynchronously(
        source: LottieAnimationSource,
        playbackMode: LottieAnimationPlaybackMode = .loop,
        displayFirstFrameSynchronously: Bool = false
    ) throws {
        self.cancelLoadTask()
        self.beginAnimationLoad()
        let loadedSource = try Self.loadAnimationSource(source)
        self.applyLoadedSource(
            loadedSource,
            source: source,
            playbackMode: playbackMode,
            displayFirstFrameSynchronously: displayFirstFrameSynchronously
        )
        self.onAnimationLoaded?(loadedSource.info)
    }

    public func play() {
        guard self.loadedSource != nil else {
            return
        }
        self.playbackStartPending = true
        self.renderCurrentFrame(force: false)
        self.updatePlaybackActivity(resetTiming: true)
    }

    public func pause() {
        self.playbackStartPending = false
        self.cancelPreparationTask()
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.lastTimestamp = nil
        self.accumulatedTime = 0.0
    }

    public func reset() {
        self.cancelLoadTask()
        self.beginAnimationLoad()
    }

    public func playOnce(completion: (() -> Void)? = nil) {
        guard let animationFrameRange = self.animationFrameRange else {
            return
        }
        self.playbackMode = .once
        self.pendingCompletion = completion
        self.segmentEndFrame = nil
        self.playbackDirection = 1
        self.currentFrame = animationFrameRange.lowerBound
        self.currentFrameIndex = self.currentFrame
        self.renderCurrentFrame(force: true)
        self.play()
    }

    public func setPlaybackMode(_ playbackMode: LottieAnimationPlaybackMode) {
        self.playbackMode = playbackMode
        self.pendingCompletion = nil
        self.segmentEndFrame = nil
        self.playbackDirection = 1

        guard let animationFrameRange = self.animationFrameRange else {
            return
        }

        if case .still(let position) = playbackMode {
            self.currentFrame = Self.frameIndex(for: position, in: animationFrameRange)
            self.currentFrameIndex = self.currentFrame
            self.renderCurrentFrame(force: true)
        }
    }

    public func seek(to progress: Double) {
        guard let animationFrameRange = self.animationFrameRange else {
            return
        }
        let clampedProgress = min(max(progress, 0.0), 1.0)
        let frameCount = animationFrameRange.upperBound - animationFrameRange.lowerBound
        self.currentFrame = animationFrameRange.lowerBound + Int(floor(Double(frameCount - 1) * clampedProgress))
        self.currentFrameIndex = self.currentFrame
        self.segmentEndFrame = nil
        self.playbackDirection = 1
        self.renderCurrentFrame(force: true)
        if self.playbackStartPending {
            self.preparePlaybackIfNeeded()
        }
    }

    public func seek(to position: LottieAnimationStartingPosition) {
        guard let animationFrameRange = self.animationFrameRange else {
            return
        }
        self.currentFrame = Self.frameIndex(for: position, in: animationFrameRange)
        self.currentFrameIndex = self.currentFrame
        self.segmentEndFrame = nil
        self.playbackDirection = 1
        self.renderCurrentFrame(force: true)
        if self.playbackStartPending {
            self.preparePlaybackIfNeeded()
        }
    }

    public func playSegment(
        from startPosition: LottieAnimationStartingPosition,
        to endPosition: LottieAnimationStartingPosition,
        completion: (() -> Void)? = nil
    ) {
        guard let animationFrameRange = self.animationFrameRange else {
            return
        }

        let startFrame = Self.frameIndex(for: startPosition, in: animationFrameRange)
        let endFrame = Self.frameIndex(for: endPosition, in: animationFrameRange)

        self.playbackMode = .once
        self.pendingCompletion = completion
        self.playbackDirection = endFrame >= startFrame ? 1 : -1
        self.segmentEndFrame = endFrame
        self.currentFrame = startFrame
        self.currentFrameIndex = self.currentFrame
        self.renderCurrentFrame(force: true)
        self.play()
    }

    public func playTransition(
        to endPosition: LottieAnimationStartingPosition,
        completion: (() -> Void)? = nil
    ) {
        guard let animationFrameRange = self.animationFrameRange else {
            return
        }

        let startFrame = self.currentFrameIndex ?? Self.frameIndex(for: .begin, in: animationFrameRange)
        let endFrame = Self.frameIndex(for: endPosition, in: animationFrameRange)

        if startFrame == endFrame {
            self.pause()
            self.seek(to: endPosition)
            completion?()
            return
        }

        self.playbackMode = .once
        self.pendingCompletion = completion
        self.playbackDirection = endFrame >= startFrame ? 1 : -1
        self.segmentEndFrame = endFrame
        self.currentFrame = startFrame
        self.currentFrameIndex = self.currentFrame
        self.renderCurrentFrame(force: true)
        self.play()
    }

    fileprivate func displayLinkTick(_ displayLink: CADisplayLink) {
        guard let animationInfo = self.animationInfo, let animationFrameRange = self.animationFrameRange else {
            return
        }

        let timestamp = displayLink.timestamp
        if let lastTimestamp = self.lastTimestamp {
            self.accumulatedTime += timestamp - lastTimestamp
        }
        self.lastTimestamp = timestamp

        let secondsPerFrame = 1.0 / Double(max(animationInfo.frameRate, 1))
        if self.accumulatedTime < secondsPerFrame * 0.9 {
            return
        }

        let framesToAdvance = max(1, Int(self.accumulatedTime / secondsPerFrame))
        self.accumulatedTime -= Double(framesToAdvance) * secondsPerFrame
        self.currentFrame += framesToAdvance * self.playbackDirection

        switch self.playbackMode {
        case .still:
            self.pause()
        case .loop:
            if self.playbackDirection >= 0 {
                if self.currentFrame >= animationFrameRange.upperBound {
                    let relativeFrame = self.currentFrame - animationFrameRange.lowerBound
                    let wrappedFrame = relativeFrame % max(1, animationFrameRange.count)
                    self.currentFrame = animationFrameRange.lowerBound + wrappedFrame
                }
            } else if self.currentFrame < animationFrameRange.lowerBound {
                let relativeFrame = animationFrameRange.upperBound - 1 - self.currentFrame
                let wrappedFrame = relativeFrame % max(1, animationFrameRange.count)
                self.currentFrame = animationFrameRange.upperBound - 1 - wrappedFrame
            }
        case .once:
            if let segmentEndFrame = self.segmentEndFrame {
                let didReachEnd = self.playbackDirection >= 0
                    ? self.currentFrame >= segmentEndFrame
                    : self.currentFrame <= segmentEndFrame
                if didReachEnd {
                    self.currentFrame = segmentEndFrame
                    self.currentFrameIndex = self.currentFrame
                    self.segmentEndFrame = nil
                    self.playbackDirection = 1
                    self.renderCurrentFrame(force: true)
                    self.pause()
                    let completion = self.pendingCompletion
                    self.pendingCompletion = nil
                    completion?()
                    return
                }
            } else if self.currentFrame >= animationFrameRange.upperBound {
                self.currentFrame = animationFrameRange.upperBound - 1
                self.currentFrameIndex = self.currentFrame
                self.renderCurrentFrame(force: true)
                self.pause()
                let completion = self.pendingCompletion
                self.pendingCompletion = nil
                completion?()
                return
            }
        }

        self.currentFrameIndex = self.currentFrame
        self.renderCurrentFrame(force: false)
    }

    private func renderCurrentFrame(force: Bool) {
        guard let animationFrameRange = self.animationFrameRange else {
            return
        }

        let renderSize = self.renderPixelSize()
        guard renderSize.width > 0, renderSize.height > 0 else {
            return
        }

        self.updatePipelineIfNeeded(width: renderSize.width, height: renderSize.height)

        let effectiveFrame = max(animationFrameRange.lowerBound, min(animationFrameRange.upperBound - 1, self.currentFrame))
        self.currentFrameIndex = effectiveFrame
        let descriptor = RenderDescriptor(
            sessionID: self.renderSessionID,
            frameIndex: effectiveFrame,
            width: renderSize.width,
            height: renderSize.height,
            scale: max(self.renderingScale, 1.0)
        )

        if !force, descriptor == self.currentRenderDescriptor || descriptor == self.pendingRenderDescriptor {
            return
        }

        self.pendingRenderDescriptor = descriptor
        self.scheduleNextRenderIfNeeded()
    }

    private func renderCurrentFrameSynchronously() -> Bool {
        guard let animationFrameRange = self.animationFrameRange, let loadedSource = self.loadedSource else {
            return false
        }

        let renderSize = self.renderPixelSize()
        guard renderSize.width > 0, renderSize.height > 0 else {
            return false
        }

        self.updatePipelineIfNeeded(width: renderSize.width, height: renderSize.height)

        let effectiveFrame = max(animationFrameRange.lowerBound, min(animationFrameRange.upperBound - 1, self.currentFrame))
        self.currentFrameIndex = effectiveFrame

        let descriptor = RenderDescriptor(
            sessionID: self.renderSessionID,
            frameIndex: effectiveFrame,
            width: renderSize.width,
            height: renderSize.height,
            scale: max(self.renderingScale, 1.0)
        )

        guard let animationInstance = LottieInstance(
            data: loadedSource.decompressedData,
            cacheKey: loadedSource.cacheKey
        ) else {
            return false
        }

        let bytesPerRow = AnimationCompression.alignUp(renderSize.width * 4, to: 64)
        let frameBuffer = AnimationFrameBuffer(
            width: renderSize.width,
            height: renderSize.height,
            bytesPerRow: bytesPerRow
        )
        animationInstance.renderFrame(
            with: Int32(effectiveFrame),
            into: frameBuffer.bytes,
            width: Int32(renderSize.width),
            height: Int32(renderSize.height),
            bytesPerRow: Int32(bytesPerRow)
        )

        guard let image = frameBuffer.makeImage() else {
            return false
        }

        self.currentRenderDescriptor = descriptor
        self.pendingRenderDescriptor = nil
        self.setPlaybackBackend(.direct)
        self.image = UIImage(cgImage: image, scale: descriptor.scale, orientation: .up)
        self.onFrameRendered?(
            LottieAnimationRenderEvent(
                frameIndex: descriptor.frameIndex,
                renderSize: CGSize(width: descriptor.width, height: descriptor.height),
                timestamp: CACurrentMediaTime()
            )
        )
        self.emitPreparationUpdate()
        return true
    }

    private func updatePipelineIfNeeded(width: Int, height: Int) {
        if let currentRenderTargetPixelSize,
           currentRenderTargetPixelSize.width == width,
           currentRenderTargetPixelSize.height == height {
            return
        }

        self.currentRenderTargetPixelSize = (width, height)
        self.invalidatePendingRenderWork()
        self.cancelPreparationTask()
        self.currentPipeline = self.makePipeline(width: width, height: height)
        self.currentCacheSizeBytes = 0
        self.lastPreparationDuration = nil
        self.isPreparingPlaybackMetrics = false
        self.setPlaybackBackend(.direct)
        self.emitPreparationUpdate()
    }

    private func makePipeline(width: Int, height: Int) -> AnimationPipeline? {
        guard let loadedSource = self.loadedSource else {
            return nil
        }

        let cacheRequest = AnimationFrameCacheStore.makeRequest(
            cacheKey: loadedSource.cacheKey,
            data: loadedSource.decompressedData,
            width: width,
            height: height
        )
        let renderer = AnimationFrameRenderer(
            data: loadedSource.decompressedData,
            cacheKey: loadedSource.cacheKey
        )
        return AnimationPipeline(
            info: loadedSource.info,
            cacheRequest: cacheRequest,
            renderer: renderer
        )
    }

    private func scheduleNextRenderIfNeeded() {
        guard self.renderTask == nil, let descriptor = self.pendingRenderDescriptor, let currentPipeline = self.currentPipeline else {
            return
        }

        self.pendingRenderDescriptor = nil
        let allowCachedFrames = self.shouldUseFrameCache()
        self.renderTask = Task { [weak self] in
            guard let self else {
                return
            }

            let renderedFrame = await currentPipeline.renderFrame(
                at: descriptor.frameIndex,
                allowCachedFrames: allowCachedFrames
            )
            await currentPipeline.prefetch(
                after: descriptor.frameIndex,
                allowCachedFrames: allowCachedFrames
            )
            let cacheSizeBytes = await currentPipeline.cacheStorageSizeBytes()

            await MainActor.run {
                self.renderTask = nil
                self.currentCacheSizeBytes = cacheSizeBytes

                guard descriptor.sessionID == self.renderSessionID else {
                    self.scheduleNextRenderIfNeeded()
                    return
                }
                guard let renderedFrame, let image = renderedFrame.frameBuffer.makeImage() else {
                    self.scheduleNextRenderIfNeeded()
                    return
                }

                self.currentRenderDescriptor = descriptor
                self.setPlaybackBackend(renderedFrame.backend)
                self.image = UIImage(cgImage: image, scale: descriptor.scale, orientation: .up)
                self.onFrameRendered?(
                    LottieAnimationRenderEvent(
                        frameIndex: descriptor.frameIndex,
                        renderSize: CGSize(width: descriptor.width, height: descriptor.height),
                        timestamp: CACurrentMediaTime()
                    )
                )
                self.emitPreparationUpdate()
                self.scheduleNextRenderIfNeeded()
            }
        }
    }

    private func preparePlaybackIfNeeded() {
        guard self.shouldUseFrameCache() else {
            self.isPreparingPlaybackMetrics = false
            self.preparationStartTimestamp = nil
            self.emitPreparationUpdate()
            return
        }
        guard self.playbackStartPending, self.isEffectivelyVisible, let currentPipeline = self.currentPipeline else {
            return
        }
        guard self.preparationTask == nil else {
            return
        }

        self.isPreparingPlaybackMetrics = true
        self.preparationStartTimestamp = CACurrentMediaTime()
        self.emitPreparationUpdate()

        let sessionID = self.renderSessionID
        self.preparationTask = Task { [weak self] in
            guard let self else {
                return
            }

            let asset = await currentPipeline.prepareCache()
            let cacheSizeBytes = await currentPipeline.cacheStorageSizeBytes()

            await MainActor.run {
                self.preparationTask = nil
                guard sessionID == self.renderSessionID else {
                    return
                }

                self.currentCacheSizeBytes = cacheSizeBytes
                if let preparationStartTimestamp = self.preparationStartTimestamp {
                    self.lastPreparationDuration = CACurrentMediaTime() - preparationStartTimestamp
                }
                self.preparationStartTimestamp = nil
                self.isPreparingPlaybackMetrics = false
                if asset != nil {
                    self.setPlaybackBackend(.cached)
                }
                self.emitPreparationUpdate()
                self.renderCurrentFrame(force: true)
            }
        }
    }

    private func ensureDisplayLink() {
        guard self.displayLink == nil else {
            return
        }

        let displayLink = CADisplayLink(target: self.displayLinkProxy, selector: #selector(DisplayLinkProxy.handleTick(_:)))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 60.0, preferred: 60.0)
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func handleRenderTargetChange() {
        let renderSize = self.renderPixelSize()
        self.updatePipelineIfNeeded(width: renderSize.width, height: renderSize.height)
        self.renderCurrentFrame(force: true)
        self.updatePlaybackActivity(resetTiming: false)
    }

    private func handleCachePolicyChange() {
        self.cancelPreparationTask()
        self.setPlaybackBackend(.direct)
        self.renderCurrentFrame(force: true)
        self.updatePlaybackActivity(resetTiming: false)
        self.emitPreparationUpdate()
    }

    private func cancelPreparationTask() {
        self.preparationTask?.cancel()
        self.preparationTask = nil
        self.preparationStartTimestamp = nil
        self.isPreparingPlaybackMetrics = false
    }

    private func invalidatePendingRenderWork() {
        self.renderSessionID &+= 1
        self.currentRenderDescriptor = nil
        self.pendingRenderDescriptor = nil
        self.renderTask?.cancel()
        self.renderTask = nil
    }

    private func emitPreparationUpdate() {
        self.onPreparationUpdated?(
            LottieAnimationPreparationEvent(
                isPreparing: self.isPreparingPlaybackMetrics,
                duration: self.lastPreparationDuration,
                cacheSizeBytes: self.currentCacheSizeBytes
            )
        )
    }

    private func setPlaybackBackend(_ backend: LottieAnimationPlaybackBackend) {
        guard self.currentPlaybackBackend != backend else {
            return
        }
        self.currentPlaybackBackend = backend
        self.onPlaybackBackendChanged?(backend)
    }

    private var isEffectivelyVisible: Bool {
        guard self.window != nil else {
            return false
        }
        guard !self.isHidden, self.alpha > 0.01 else {
            return false
        }
        if let externalShouldPlay = self.externalShouldPlay, !externalShouldPlay {
            return false
        }
        return true
    }

    private func shouldUseFrameCache() -> Bool {
        guard let loadedSource = self.loadedSource else {
            return false
        }

        switch self.cachePolicy {
        case .disabled:
            return false
        case .always:
            return true
        case .automatic:
            guard case .loop = self.playbackMode else {
                return false
            }
            let pixelCount: Int
            if let currentRenderTargetPixelSize {
                pixelCount = currentRenderTargetPixelSize.width * currentRenderTargetPixelSize.height
            } else {
                pixelCount = Int(loadedSource.info.dimensions.width * loadedSource.info.dimensions.height)
            }
            guard pixelCount >= Self.automaticCacheMinimumPixelCount else {
                return false
            }
            return loadedSource.info.frameCount >= Self.automaticCacheMinimumFrameCount
        }
    }

    private func updatePlaybackActivity(resetTiming: Bool) {
        let shouldAnimate = self.playbackStartPending && self.isEffectivelyVisible

        if shouldAnimate {
            if resetTiming {
                self.lastTimestamp = nil
                self.accumulatedTime = 0.0
            }
            self.ensureDisplayLink()
            self.displayLink?.isPaused = false
            self.preparePlaybackIfNeeded()
        } else {
            self.displayLink?.isPaused = true
            self.cancelPreparationTask()
            self.emitPreparationUpdate()
        }
    }

    private func renderPixelSize() -> (width: Int, height: Int) {
        let scale = max(self.renderingScale, 1.0)
        let width = max(1, Int(round(self.bounds.width * scale)))
        let height = max(1, Int(round(self.bounds.height * scale)))
        return (width, height)
    }

    private static func frameIndex(
        for startingPosition: LottieAnimationStartingPosition,
        in frameRange: Range<Int>
    ) -> Int {
        switch startingPosition {
        case .begin:
            return frameRange.lowerBound
        case .end:
            return max(frameRange.lowerBound, frameRange.upperBound - 1)
        case let .fraction(progress):
            let clampedProgress = min(max(progress, 0.0), 1.0)
            let frameCount = frameRange.upperBound - frameRange.lowerBound
            return frameRange.lowerBound + Int(floor(Double(max(frameCount - 1, 0)) * clampedProgress))
        }
    }

    private func cancelLoadTask() {
        self.loadTask?.cancel()
        self.loadTask = nil
    }

    private func beginAnimationLoad() {
        self.pause()
        self.loadRequestID &+= 1
        self.source = nil
        self.loadedSource = nil
        self.animationInfo = nil
        self.animationFrameRange = nil
        self.pendingCompletion = nil
        self.currentRenderTargetPixelSize = nil
        self.lastPreparationDuration = nil
        self.currentCacheSizeBytes = 0
        self.isPreparingPlaybackMetrics = false
        self.image = nil
        self.currentPipeline = nil
        self.currentFrame = 0
        self.currentFrameIndex = nil
        self.segmentEndFrame = nil
        self.playbackDirection = 1
        self.accumulatedTime = 0.0
        self.lastTimestamp = nil
        self.setPlaybackBackend(.direct)
        self.invalidatePendingRenderWork()
        self.cancelPreparationTask()
        self.emitPreparationUpdate()
    }

    private func applyLoadedSource(
        _ loadedSource: LoadedSource,
        source: LottieAnimationSource,
        playbackMode: LottieAnimationPlaybackMode,
        displayFirstFrameSynchronously: Bool
    ) {
        self.source = source
        self.loadedSource = loadedSource
        self.animationInfo = loadedSource.info

        let frameCount = max(1, loadedSource.info.frameCount)
        let frameRange = 0 ..< frameCount
        self.animationFrameRange = frameRange
        self.playbackMode = playbackMode
        self.segmentEndFrame = nil
        self.playbackDirection = 1
        self.currentFrame = Self.frameIndex(
            for: playbackMode.startingPosition,
            in: frameRange
        )
        self.currentFrameIndex = self.currentFrame

        if !displayFirstFrameSynchronously || !self.renderCurrentFrameSynchronously() {
            self.renderCurrentFrame(force: true)
        }

        if playbackMode.shouldAutoplay {
            self.play()
        }
    }

    nonisolated private static func loadAnimationSource(_ source: LottieAnimationSource) throws -> LoadedSource {
        let loaded = try source.loadData()
        try Task.checkCancellation()

        let decompressedData = TGGUnzipData(loaded.data, 8 * 1024 * 1024) ?? loaded.data
        try Task.checkCancellation()

        guard let animationInstance = LottieInstance(
            data: decompressedData,
            cacheKey: loaded.cacheKey
        ) else {
            throw LottieAnimationError.failedToCreateAnimation
        }
        try Task.checkCancellation()

        let info = LottieAnimationInfo(
            frameCount: max(1, Int(animationInstance.frameCount)),
            frameRate: max(1, Int(animationInstance.frameRate)),
            dimensions: animationInstance.dimensions
        )

        return LoadedSource(
            cacheKey: loaded.cacheKey,
            decompressedData: decompressedData,
            info: info
        )
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var owner: LottieAnimationView?

    init(owner: LottieAnimationView) {
        self.owner = owner
    }

    @objc func handleTick(_ displayLink: CADisplayLink) {
        guard let owner = self.owner else {
            displayLink.invalidate()
            return
        }
        owner.displayLinkTick(displayLink)
    }
}

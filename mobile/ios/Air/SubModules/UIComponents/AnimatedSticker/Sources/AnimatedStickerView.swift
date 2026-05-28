import Foundation
import Compression
import RLottieBinding
import GZip
import UIKit
import Dispatch

public enum AnimatedStickerMode {
    case direct
}

public enum AnimatedStickerPlaybackPosition {
    case start
    case end
}

// for animations like (Password) which contain 2 states, `on` (50% of the animation) and `off` (seek to 0%)
public enum AnimatedStickerPlaybackToggle {
    case on
    case off
}

public enum AnimatedStickerPlaybackMode: Equatable {
    case once
    case loop
    case still(AnimatedStickerPlaybackPosition)
    // toggle mode let's animation player to make password animation possible
    case toggle(Bool)
}

private final class AnimatedStickerFrame {
    let data: Data
    let type: AnimationRendererFrameType
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let index: Int
    let isLastFrame: Bool
    
    init(data: Data, type: AnimationRendererFrameType, width: Int, height: Int, bytesPerRow: Int, index: Int, isLastFrame: Bool) {
        self.data = data
        self.type = type
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.index = index
        self.isLastFrame = isLastFrame
    }
}

private protocol AnimatedStickerFrameSource: AnyObject {
    var frameRate: Int { get }
    var frameCount: Int { get }
    var frameIndex: Int { get }
    // hold playback speed on frame source to make reverse playing possible
    var playbackSpeed: Int { get set }
    
    func takeFrame() -> AnimatedStickerFrame?
    func skipToEnd()
}

private final class AnimatedStickerDirectFrameSource: AnimatedStickerFrameSource {
    private let data: Data
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    let frameCount: Int
    let frameRate: Int
    private var currentFrame: Int
    private let animation: LottieInstance

    // hold frameIndex to handle toggle play mode
    var frameIndex: Int = 0
    var playbackSpeed = 1

    init?(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
        self.bytesPerRow = (4 * Int(width) + 15) & (~15)
        self.currentFrame = 0
        let rawData = TGGUnzipData(data, 8 * 1024 * 1024) ?? data
        guard let animation = LottieInstance(data: rawData, cacheKey: "") else {
            return nil
        }
        self.animation = animation
        self.frameCount = Int(animation.frameCount)
        self.frameRate = Int(animation.frameRate)
    }
    
    func takeFrame() -> AnimatedStickerFrame? {
        frameIndex = self.currentFrame % self.frameCount
        self.currentFrame += playbackSpeed
        var frameData = Data(count: self.bytesPerRow * self.height)
        frameData.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let bytes = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            memset(bytes, 0, self.bytesPerRow * self.height)
            self.animation.renderFrame(with: Int32(frameIndex), into: bytes, width: Int32(self.width), height: Int32(self.height), bytesPerRow: Int32(self.bytesPerRow))
        }
        return AnimatedStickerFrame(data: frameData, type: .argb, width: self.width, height: self.height, bytesPerRow: self.bytesPerRow, index: frameIndex, isLastFrame: frameIndex == self.frameCount - 1)
    }
    
    func skipToEnd() {
        self.currentFrame = self.frameCount - 1
    }
}

private final class AnimatedStickerFrameQueue {
    private let length: Int
    private let source: AnimatedStickerFrameSource
    private var frames: [AnimatedStickerFrame] = []
    
    init(length: Int, source: AnimatedStickerFrameSource) {
        self.length = length
        self.source = source
    }
    
    func take() -> AnimatedStickerFrame? {
        if self.frames.isEmpty {
            if let frame = self.source.takeFrame() {
                self.frames.append(frame)
            }
        }
        if !self.frames.isEmpty {
            let frame = self.frames.removeFirst()
            return frame
        } else {
            return nil
        }
    }
    
    func generateFramesIfNeeded() {
        if self.frames.isEmpty {
            if let frame = self.source.takeFrame() {
                self.frames.append(frame)
            }
        }
    }
}

public struct AnimatedStickerNodeLocalFileSource {
    public let path: String
    
    public init(path: String) {
        self.path = path
    }
}

final class AnimatedStickerNode: UIView {
    private let queue = DispatchQueue(label: "org.mytonwallet.animatedsticker.queue", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    
    public var automaticallyLoadFirstFrame: Bool = false
    public var playToCompletionOnStop: Bool = false
    
    public var started: () -> Void = {}
    private var reportedStarted = false
    
    private var frameSource: AnimatedStickerFrameSource?
    private var frameQueue: AnimatedStickerFrameQueue?
    
    private var directData: (Data, String, Int, Int)?
    
    private var renderer: (AnimationRenderer & UIView)?
    
    public var isPlaying: Bool = false
    private var canDisplayFirstFrame: Bool = false
    var playbackMode: AnimatedStickerPlaybackMode = .loop {
        didSet {
            guard let frameSource else {return}
            switch oldValue {
            case .toggle(let on):
                switch playbackMode {
                case .toggle(let newOn):
                    // reverse playback if makes transition to the desired state, faster.
                    if on != newOn {
                        if (newOn && frameSource.frameIndex > frameSource.frameCount / 2) ||
                            (!newOn && frameSource.frameIndex < frameSource.frameCount / 2) {
                            frameSource.playbackSpeed = -1
                        } else {
                            frameSource.playbackSpeed = 1
                        }
                    }
                    return
                default:
                    break
                }
            default:
                break
            }
            frameSource.playbackSpeed = 1
        }
    }
    
    public var visibility = false {
        didSet {
            if self.visibility != oldValue {
                self.updateIsPlaying()
            }
        }
    }
    
    private var isDisplaying = false {
        didSet {
            if self.isDisplaying != oldValue {
                self.updateIsPlaying()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        fatalError()
    }
    
    deinit {
        timer?.cancel()
        timer = nil
    }
    
    func didLoad() {
        #if targetEnvironment(simulator)
        self.renderer = SoftwareAnimationRenderer()
        #else
        self.renderer = SoftwareAnimationRenderer()
        //self.renderer = MetalAnimationRenderer()
        #endif
        self.renderer?.frame = CGRect(origin: CGPoint(), size: frame.size)
        self.addSubview(self.renderer!)
    }

    public func setup(source: AnimatedStickerNodeLocalFileSource,
                      width: Int,
                      height: Int,
                      playbackMode: AnimatedStickerPlaybackMode = .loop,
                      mode: AnimatedStickerMode) {
        if width < 2 || height < 2 {
            return
        }
        self.playbackMode = playbackMode
        guard mode == .direct else { return }
        let path = source.path
        if let directData = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedRead]) {
            self.directData = (directData, path, width, height)
        }
        if case let .still(position) = playbackMode {
            self.seekTo(position)
        } else if self.isPlaying {
            self.play()
        } else if self.canDisplayFirstFrame {
            self.play(firstFrame: true)
        }
    }
    
    public func reset() {
        timer?.cancel()
        timer = nil
        frameSource = nil
        frameQueue = nil
    }
    
    private func updateIsPlaying() {
        let isPlaying = self.visibility && self.isDisplaying
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
            if isPlaying {
                self.play()
            } else{
                self.pause()
            }
        }
        let canDisplayFirstFrame = self.automaticallyLoadFirstFrame && self.isDisplaying
        if self.canDisplayFirstFrame != canDisplayFirstFrame {
            self.canDisplayFirstFrame = canDisplayFirstFrame
            if canDisplayFirstFrame {
                self.play(firstFrame: true)
            }
        }
    }
    
    private var isSetUpForPlayback = false
    
    public func play(firstFrame: Bool = false) {
        if !self.isSetUpForPlayback {
            self.isSetUpForPlayback = true
        }
        startPlayback(firstFrame: firstFrame)
    }
    
    private func startPlayback(firstFrame: Bool) {
        guard let directData else {
            return
        }
        if frameSource == nil {
            frameSource = AnimatedStickerDirectFrameSource(data: directData.0, width: directData.2, height: directData.3)
        }
        guard let frameSource else {
            return
        }
        frameQueue = AnimatedStickerFrameQueue(length: 1, source: frameSource)
        timer?.cancel()
        timer = nil
        
        if firstFrame {
            if let frame = frameQueue?.take() {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.renderer?.render(queue: self.queue, width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow, data: frame.data, type: frame.type, completion: { [weak self] in
                        guard let self else { return }
                        if !self.reportedStarted {
                            self.reportedStarted = true
                            self.started()
                        }
                    })
                }
            }
            return
        }
        
        let frameRate = frameSource.frameRate
        let interval = frameRate > 0 ? 1.0 / Double(frameRate) : 0.033
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let frameQueue = self.frameQueue else { return }
            let frame = frameQueue.take()
            guard let frame else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.renderer?.render(queue: self.queue, width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow, data: frame.data, type: frame.type, completion: { [weak self] in
                    guard let self else { return }
                    if !self.reportedStarted {
                        self.reportedStarted = true
                        self.started()
                    }
                })
                
                if case .once = self.playbackMode, frame.isLastFrame {
                    self.stop()
                    self.isPlaying = false
                }
                if case .toggle(true) = self.playbackMode, frameSource.frameIndex == frameSource.frameCount / 2 {
                    self.pause()
                    self.isPlaying = false
                }
                if case .toggle(false) = self.playbackMode, frameSource.frameIndex == 1 {
                    self.pause()
                    self.isPlaying = false
                }
            }
            frameQueue.generateFramesIfNeeded()
        }
        self.timer = timer
        timer.resume()
    }
    
    public func pause() {
        timer?.cancel()
        timer = nil
    }
    
    public func stop() {
        self.isSetUpForPlayback = false
        self.reportedStarted = false
        timer?.cancel()
        timer = nil
        if self.playToCompletionOnStop {
            self.seekTo(.start)
        }
    }
    
    public func seekTo(_ position: AnimatedStickerPlaybackPosition) {
        self.isPlaying = false
        
        guard let directData else {
            return
        }
        frameSource = AnimatedStickerDirectFrameSource(data: directData.0, width: directData.2, height: directData.3)
        if position == .end {
            frameSource?.skipToEnd()
        }
        guard let frameSource else {
            return
        }
        frameQueue = AnimatedStickerFrameQueue(length: 1, source: frameSource)
        timer?.cancel()
        timer = nil
        
        if let frame = frameQueue?.take() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.renderer?.render(queue: self.queue, width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow, data: frame.data, type: frame.type, completion: { [weak self] in
                    guard let self else { return }
                    if !self.reportedStarted {
                        self.reportedStarted = true
                        self.started()
                    }
                })
            }
        }
    }
    
    public func playIfNeeded() -> Bool {
        if !self.isPlaying {
            self.isPlaying = true
            self.play()
            return true
        }
        return false
    }
    
    public func updateLayout(size: CGSize) {
        self.renderer?.frame = CGRect(origin: CGPoint(), size: size)
    }
}

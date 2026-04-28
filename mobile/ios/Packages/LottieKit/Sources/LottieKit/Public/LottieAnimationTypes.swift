import CoreGraphics
import Foundation

public enum LottieAnimationSource: Equatable, Sendable {
    case data(Data, cacheKey: String? = nil)
    case file(path: String)

    func loadData() throws -> (data: Data, cacheKey: String) {
        switch self {
        case let .data(data, cacheKey):
            return (data, cacheKey ?? "")
        case let .file(path):
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
            return (data, path)
        }
    }
}

public enum LottieAnimationStartingPosition: Equatable, Sendable {
    case begin
    case end
    case fraction(Double)
}

public enum LottieAnimationPlaybackMode: Equatable, Sendable {
    case still(position: LottieAnimationStartingPosition)
    case once
    case loop
}

public struct LottieAnimationInfo: Equatable, Sendable {
    public let frameCount: Int
    public let frameRate: Int
    public let dimensions: CGSize

    public var duration: Double {
        guard self.frameRate > 0 else {
            return 0.0
        }
        return Double(self.frameCount) / Double(self.frameRate)
    }

    public init(frameCount: Int, frameRate: Int, dimensions: CGSize) {
        self.frameCount = frameCount
        self.frameRate = frameRate
        self.dimensions = dimensions
    }
}

public struct LottieAnimationRenderEvent: Equatable, Sendable {
    public let frameIndex: Int
    public let renderSize: CGSize
    public let timestamp: CFTimeInterval

    public init(frameIndex: Int, renderSize: CGSize, timestamp: CFTimeInterval) {
        self.frameIndex = frameIndex
        self.renderSize = renderSize
        self.timestamp = timestamp
    }
}

public struct LottieAnimationPreparationEvent: Equatable, Sendable {
    public let isPreparing: Bool
    public let duration: TimeInterval?
    public let cacheSizeBytes: Int64

    public init(isPreparing: Bool, duration: TimeInterval?, cacheSizeBytes: Int64) {
        self.isPreparing = isPreparing
        self.duration = duration
        self.cacheSizeBytes = cacheSizeBytes
    }
}

public enum LottieAnimationPlaybackBackend: String, Equatable, Sendable {
    case direct = "direct"
    case cached = "cached"
}

public enum LottieAnimationCachePolicy: String, Equatable, Sendable {
    case disabled = "disabled"
    case automatic = "automatic"
    case always = "always"
}

public struct LottieAnimationCacheOptions: Equatable, Sendable {
    public var formatVersion: Int
    public var diskLimitBytes: Int64

    public init(
        formatVersion: Int = 2,
        diskLimitBytes: Int64 = 128 * 1024 * 1024
    ) {
        self.formatVersion = formatVersion
        self.diskLimitBytes = diskLimitBytes
    }
}

public enum LottieAnimationError: Error {
    case failedToCreateAnimation
}

extension LottieAnimationPlaybackMode {
    var startingPosition: LottieAnimationStartingPosition {
        switch self {
        case let .still(position):
            return position
        case .once, .loop:
            return .begin
        }
    }

    var shouldAutoplay: Bool {
        switch self {
        case .still:
            return false
        case .once, .loop:
            return true
        }
    }
}

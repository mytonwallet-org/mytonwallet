import UIKit

private let MAXIMUM_MEDIA_WAIT: TimeInterval = 2

public struct StoryPage {
    public let id: String
    public let title: String
    public let body: String
    public let buttonTitle: String?
    public let duration: TimeInterval
    public let image: UIImage?
    public let reducedMotionImage: UIImage?
    public let videoURL: URL?

    public init(id: String, title: String, body: String, buttonTitle: String? = nil,
                duration: TimeInterval = 10, image: UIImage? = nil, reducedMotionImage: UIImage? = nil, videoURL: URL? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.buttonTitle = buttonTitle
        self.duration = duration.isFinite && duration > 0 ? duration : 10
        self.image = image
        self.reducedMotionImage = reducedMotionImage
        self.videoURL = videoURL
    }
}

struct StoryPlaybackState {
    enum PauseReason: Hashable { case hidden, background, touch, scrolling, voiceOver, dismissal }
    enum Change: Equatable { case none, page, completed }

    private let durations: [TimeInterval]
    private(set) var index = 0
    private(set) var elapsed: TimeInterval = 0
    private var mediaWaitElapsed: TimeInterval = 0
    private var hasStartedProgress = false
    private(set) var isCompleted = false
    private(set) var pauseReasons: Set<PauseReason> = [.hidden]

    var isPaused: Bool { !pauseReasons.isEmpty || isCompleted || durations.isEmpty }
    var progress: CGFloat {
        guard durations.indices.contains(index) else { return 0 }
        return min(1, CGFloat(elapsed / durations[index]))
    }

    init(pages: [StoryPage]) { durations = pages.map(\.duration) }

    mutating func setPaused(_ paused: Bool, for reason: PauseReason) {
        if paused { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
    }

    mutating func advance(by interval: TimeInterval, isWaitingForMedia: Bool = false) -> Change {
        guard !isPaused, interval.isFinite, interval > 0 else { return .none }
        var progressInterval = interval
        if !hasStartedProgress, isWaitingForMedia {
            let wait = min(interval, max(0, MAXIMUM_MEDIA_WAIT - mediaWaitElapsed))
            mediaWaitElapsed += wait
            progressInterval -= wait
            guard mediaWaitElapsed >= MAXIMUM_MEDIA_WAIT else { return .none }
        }
        hasStartedProgress = true
        elapsed = min(durations[index], elapsed + progressInterval)
        return progress >= 1 ? next() : .none
    }

    mutating func next() -> Change {
        guard !isCompleted, !durations.isEmpty else { return .none }
        guard index + 1 < durations.count else {
            elapsed = durations[index]
            isCompleted = true
            return .completed
        }
        index += 1
        elapsed = 0
        mediaWaitElapsed = 0
        hasStartedProgress = false
        return .page
    }

    mutating func previous() -> Change {
        guard !isCompleted, !durations.isEmpty else { return .none }
        index = max(0, index - 1)
        elapsed = 0
        mediaWaitElapsed = 0
        hasStartedProgress = false
        return .page
    }
}

import UIComponents
import UIKit
import WalletCore

/// Telegram's path for a reaction that leaves its picker, `animateOutToReaction`'s: 0.2 s, linear in time, along a
/// parabola through the start, a point 30 pt above the start halfway across, and the end, so the reaction lifts a
/// little and drops fast onto its place. A move shorter than 5 pt both ways goes straight.
enum AgentReactionTrajectory {
    static let duration: TimeInterval = 0.2
    static let elevation: CGFloat = 30

    /// The point `progress` of the way along the parabola from `start` to `end`, which goes evenly across and passes
    /// `elevation` above `start` halfway across
    static func getPoint(
        from start: CGPoint,
        to end: CGPoint,
        progress: CGFloat,
        elevation: CGFloat = Self.elevation
    ) -> CGPoint {
        let x = start.x + (end.x - start.x) * progress
        guard abs(start.x - end.x) >= 5 || abs(start.y - end.y) >= 5 else {
            return CGPoint(x: x, y: start.y + (end.y - start.y) * progress)
        }
        // The parabola through the start, the raised middle and the end, as x goes evenly with the progress
        let middleY = start.y - elevation
        let y = start.y * (1 - progress) * (1 - 2 * progress)
            + middleY * 4 * progress * (1 - progress)
            + end.y * progress * (2 * progress - 1)
        return CGPoint(x: x, y: y)
    }
}

/// A reaction chosen in the menu's cloud flies to the answer's corner as Telegram's does: the chosen emoji leaves its
/// place on Telegram's trajectory, going from its size there to the corner's emoji's and from its drawing to the first
/// frame of Telegram's landing, the burst plays around the corner from 0.15 s, as Telegram's does, and on the hit,
/// with a light haptic, the corner's emoji takes it over in the same frame. It flies over the window, where nothing
/// clips it, and follows the corner wherever it shows.
@MainActor
final class AgentReactionFlight {
    /// When the burst starts around the corner, from the flight's start, as Telegram's does
    static let burstDelay: TimeInterval = 0.15

    /// The flying emoji, in the box of the corner's emoji
    let iconView = AgentReactionEmojiView(boxSize: AgentReactionEmojiMetrics.badgeBoxSize)
    private(set) var burst: AgentReactionEffect?
    /// When the flight started, when its burst started, and when it hit the corner
    let startTime: CFTimeInterval
    private(set) var burstStartTime: CFTimeInterval?
    private(set) var arrivalTime: CFTimeInterval?
    private let feedback: ApiAgentV2AnswerFeedback
    private let startCenter: CGPoint
    private let startScale: CGFloat
    private let getTargetFrame: () -> CGRect?
    private let onArrival: () -> Void
    private var lastTargetFrame: CGRect
    private var subscriptionID: UUID?

    /// Flies `feedback` from `source`, its icon in the cloud, which hides as it leaves, to the 22 pt icon frame that
    /// `getTargetFrame` gives, in `window`'s coordinates, and calls `onArrival` on the hit; a target that goes away
    /// keeps the last one
    @discardableResult
    static func start(
        feedback: ApiAgentV2AnswerFeedback,
        in window: UIWindow,
        from source: AgentReactionEmojiView,
        at getTargetFrame: @escaping () -> CGRect?,
        onArrival: @escaping () -> Void
    ) -> AgentReactionFlight? {
        let sourceFrame = source.presentedFrameInWindow
        let sourceDrawing = source.currentDrawing
        source.alpha = 0
        guard let sourceFrame, let target = getTargetFrame() else {
            onArrival()
            return nil
        }
        // The emoji fills the cloud's box as the 36 pt icon, and the corner's box as its 22 pt icon
        let sourceEmojiSize = sourceFrame.width * AgentFeedbackPillMetrics.iconSize / AgentReactionEmojiMetrics.cloudBoxSize
        let startScale = sourceEmojiSize / AgentReactionBadgeView.Metrics.iconSize
        let flight = AgentReactionFlight(
            feedback: feedback,
            startCenter: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
            startScale: startScale,
            target: target,
            getTargetFrame: getTargetFrame,
            onArrival: onArrival
        )
        let icon = flight.iconView
        icon.showStill(.center, of: feedback, at: .begin)
        if let sourceDrawing {
            icon.prepareCrossFade(to: sourceDrawing, side: sourceFrame.width / startScale)
            icon.setCrossFade(1)
        }
        window.addSubview(icon)
        flight.apply(center: flight.startCenter, scale: startScale)
        flight.subscriptionID = AgentDisplayLinkDriver.shared.add { [flight] in
            flight.step()
        }
        return flight
    }

    private init(
        feedback: ApiAgentV2AnswerFeedback,
        startCenter: CGPoint,
        startScale: CGFloat,
        target: CGRect,
        getTargetFrame: @escaping () -> CGRect?,
        onArrival: @escaping () -> Void
    ) {
        self.feedback = feedback
        self.startCenter = startCenter
        self.startScale = startScale
        self.getTargetFrame = getTargetFrame
        self.onArrival = onArrival
        lastTargetFrame = target
        startTime = CACurrentMediaTime()
        iconView.isUserInteractionEnabled = false
    }

    /// The flying emoji's scale at the corner, where it is as large as the corner's 22 pt icon of `targetFrame`
    static func getScale(toIconFrame targetFrame: CGRect) -> CGFloat {
        targetFrame.width / AgentReactionBadgeView.Metrics.iconSize
    }

    private func step() {
        // A window that goes away takes the flight with it
        guard let window = iconView.window else {
            finish(isHit: false)
            return
        }
        let now = CACurrentMediaTime()
        if let target = getTargetFrame() {
            lastTargetFrame = target
        }
        let elapsed = now - startTime
        if burst == nil, elapsed >= Self.burstDelay {
            startBurst(in: window, at: now)
        }
        let progress = CGFloat(min(max(elapsed / AgentReactionTrajectory.duration, 0), 1))
        let end = CGPoint(x: lastTargetFrame.midX, y: lastTargetFrame.midY)
        guard progress < 1 else {
            apply(center: end, scale: Self.getScale(toIconFrame: lastTargetFrame))
            finish(isHit: true)
            return
        }
        let endScale = Self.getScale(toIconFrame: lastTargetFrame)
        apply(
            center: AgentReactionTrajectory.getPoint(from: startCenter, to: end, progress: progress),
            scale: startScale + (endScale - startScale) * progress
        )
        iconView.setCrossFade(1 - progress)
    }

    private func apply(center: CGPoint, scale: CGFloat) {
        iconView.center = center
        iconView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    /// The burst around the corner, at the size Telegram's has around the corner's emoji, over everything
    private func startBurst(in window: UIWindow, at time: CFTimeInterval) {
        burstStartTime = time
        let getTargetFrame = getTargetFrame
        burst = AgentReactionEffect.play(
            .burst,
            of: feedback,
            size: AgentReactionEmojiMetrics.burstSize,
            in: window,
            center: { getTargetFrame().map { CGPoint(x: $0.midX, y: $0.midY) } }
        )
    }

    /// The hit: the corner's emoji takes the flying one over in the same frame, with a light haptic, and the burst,
    /// started now should the flight have skipped its time, plays on. A flight whose window went lands without them.
    private func finish(isHit: Bool) {
        guard let subscriptionID else { return }
        AgentDisplayLinkDriver.shared.remove(subscriptionID)
        self.subscriptionID = nil
        let now = CACurrentMediaTime()
        if isHit, burst == nil, let window = iconView.window {
            startBurst(in: window, at: now)
        }
        arrivalTime = now
        iconView.removeFromSuperview()
        if isHit {
            Haptics.play(.lightTap)
        }
        onArrival()
    }
}

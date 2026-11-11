import UIKit
import UIComponents

/// The typing row as an answer takes its place: pictures of its spinning top and its status, where they stood in the
/// view they were taken in, and the frame the two take up in the row
struct AgentTypingRowSource {
    let topPicture: UIView
    let topFrame: CGRect
    let statusPicture: UIView
    let statusFrame: CGRect
    let rowFrame: CGRect

    /// The source taken in `view`, with its frames in `container` as the two stand now
    func converted(from view: UIView, to container: UIView) -> AgentTypingRowSource {
        AgentTypingRowSource(
            topPicture: topPicture,
            topFrame: container.convert(topFrame, from: view),
            statusPicture: statusPicture,
            statusFrame: container.convert(statusFrame, from: view),
            rowFrame: container.convert(rowFrame, from: view)
        )
    }
}

/// The typing row turns into the answer that takes its place rather than swapping for it: the spinning top shrinks as
/// it moves away, the status dissolves into the answer's first characters as it moves onto them, and the answer's
/// bubble grows out of the row's frame into its own, following the bubble as the answer streams in, on Telegram's
/// 0.4 s curve. The pictures move with the bubble as the list lays it out elsewhere meanwhile.
@MainActor
final class AgentTypingAnswerMorph {
    static let duration: CFTimeInterval = 0.4
    /// The spinning top ends this small, this far toward the leading edge and up
    private static let topEndScale: CGFloat = 0.2
    private static let topTravel = CGPoint(x: -14, y: -10)
    private static let topDuration: TimeInterval = 0.3
    private static let statusDissolveDuration: CFTimeInterval = 0.3
    /// The answer's text comes into focus a moment after the status starts dissolving
    private static let contentDelay: CFTimeInterval = 0.06
    private static let bubbleFadeDuration: CFTimeInterval = 0.2
    static let bubbleFadeKey = "agentTypingAnswerMorphFade"
    /// The mask ends this far outside the bubble, its corners concentric with the bubble's, so the bubble's own shape
    /// shows by then
    private static let maskOutset: CGFloat = 8

    private weak var bubble: AgentBubbleBackgroundView?
    private weak var container: UIView?
    /// Where the bubble stood in the container as the morph started, and each picture's centre then
    private let bubbleStart: CGPoint
    private var pictureCenters: [ObjectIdentifier: CGPoint] = [:]
    private let maskLayer = CAShapeLayer()
    private let startRect: CGRect
    private let startTime = CACurrentMediaTime()
    private let curve = AgentComposerMetrics.makeTelegramCurve()
    /// The spinning top's picture and the status's
    private(set) var pictures: [UIView]
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] time in self?.step(at: time) }

    /// Morphs the typing row of `source` into `bubble`, the answer's bubble. The pictures go into `container`, which
    /// holds the source's frames. Nil with Reduce Motion, or when the bubble isn't laid out.
    static func start(
        from source: AgentTypingRowSource,
        into bubble: AgentBubbleBackgroundView,
        in container: UIView
    ) -> AgentTypingAnswerMorph? {
        guard !UIAccessibility.isReduceMotionEnabled, bubble.window != nil, !bubble.bounds.isEmpty else { return nil }
        let morph = AgentTypingAnswerMorph(
            startRect: container.convert(source.rowFrame, to: bubble),
            bubble: bubble,
            container: container,
            pictures: [source.topPicture, source.statusPicture]
        )
        morph.moveTopAway(source, in: container)
        morph.dissolveStatus(source, into: bubble, in: container)
        morph.growBubble()
        return morph
    }

    private init(startRect: CGRect, bubble: AgentBubbleBackgroundView, container: UIView, pictures: [UIView]) {
        self.startRect = startRect
        self.bubble = bubble
        self.container = container
        bubbleStart = Self.getOrigin(of: bubble, in: container)
        self.pictures = pictures
    }

    /// Ends the morph where it stands: the pictures go and the bubble shows whole
    func cancel() {
        for picture in pictures {
            picture.layer.removeAllAnimations()
            picture.removeFromSuperview()
        }
        pictures = []
        finish()
    }

    private func moveTopAway(_ source: AgentTypingRowSource, in container: UIView) {
        let top = source.topPicture
        top.frame = source.topFrame
        add(top, to: container)
        let direction: CGFloat = container.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let away = UIViewPropertyAnimator(
            duration: Self.topDuration,
            timingParameters: AgentComposerMetrics.makeTelegramCubicTiming()
        )
        away.addAnimations {
            top.transform = CGAffineTransform(translationX: Self.topTravel.x * direction, y: Self.topTravel.y)
                .scaledBy(x: Self.topEndScale, y: Self.topEndScale)
            top.alpha = 0
        }
        away.addCompletion { _ in top.removeFromSuperview() }
        away.startAnimation()
    }

    /// The status moves onto where the answer's first characters stand as it blurs away, while the answer's text comes
    /// into focus there
    private func dissolveStatus(_ source: AgentTypingRowSource, into bubble: AgentBubbleBackgroundView, in container: UIView) {
        let status = source.statusPicture
        status.frame = source.statusFrame
        add(status, to: container)
        let isRightToLeft = container.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let padding = CGPoint(x: AgentMessageCellMetrics.bodyHorizontalPadding, y: AgentMessageCellMetrics.bodyVerticalPadding)
        let textStart = bubble.convert(
            CGPoint(x: isRightToLeft ? bubble.bounds.width - padding.x : padding.x, y: padding.y),
            to: container
        )
        let offset = CGPoint(
            x: textStart.x - (isRightToLeft ? source.statusFrame.maxX : source.statusFrame.minX),
            y: textStart.y - source.statusFrame.minY
        )
        let move = UIViewPropertyAnimator(duration: Self.duration, timingParameters: AgentComposerMetrics.makeTelegramCubicTiming())
        move.addAnimations {
            status.transform = CGAffineTransform(translationX: offset.x, y: offset.y)
        }
        move.startAnimation()
        AgentBlurTransition.animateOut(status.layer, duration: Self.statusDissolveDuration) { [weak status] in
            status?.removeFromSuperview()
        }
        AgentBlurTransition.animateIn(bubble.contentView.layer, duration: Self.statusDissolveDuration, delay: Self.contentDelay)
    }

    /// The bubble shows within the row's frame at first, which grows into the bubble's frame
    private func growBubble() {
        guard let bubble else { return }
        maskLayer.actions = ["path": NSNull(), "frame": NSNull(), "bounds": NSNull(), "position": NSNull()]
        bubble.layer.mask = maskLayer
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Self.bubbleFadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bubble.layer.add(fade, forKey: Self.bubbleFadeKey)
        step(at: startTime)
        clock.start()
    }

    /// Follows the bubble's frame as it is now, so the growth keeps up with an answer that streams in meanwhile
    private func step(at time: CFTimeInterval) {
        guard let bubble, bubble.layer.mask === maskLayer else {
            finish()
            return
        }
        followBubble(bubble)
        let fraction = min(1, max(0, CGFloat((time - startTime) / Self.duration)))
        let progress = AgentLayerAnimationSampler.getEasedFraction(curve, at: fraction)
        let end = bubble.bounds.insetBy(dx: -Self.maskOutset, dy: -Self.maskOutset)
        let rect = CGRect(
            x: startRect.minX + (end.minX - startRect.minX) * progress,
            y: startRect.minY + (end.minY - startRect.minY) * progress,
            width: startRect.width + (end.width - startRect.width) * progress,
            height: startRect.height + (end.height - startRect.height) * progress
        )
        let bubbleRadius = AgentBubbleBackgroundView.CornerRadii.standAlone.topLeft
        let radius = min(bubbleRadius + Self.maskOutset * progress, rect.width / 2, rect.height / 2)
        maskLayer.frame = bubble.layer.bounds
        maskLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: max(0, radius)).cgPath
        if fraction >= 1 {
            finish()
        }
    }

    /// Where the bubble stands in the container as laid out. Not as shown: a reused row's layer shows its previous place
    /// until the pass that puts it in the answer's place is committed.
    private static func getOrigin(of bubble: UIView, in container: UIView) -> CGPoint {
        bubble.convert(bubble.bounds.origin, to: container)
    }

    /// Moves the pictures as far as the bubble has moved in the container since the start
    private func followBubble(_ bubble: AgentBubbleBackgroundView) {
        guard let container else { return }
        let origin = Self.getOrigin(of: bubble, in: container)
        for picture in pictures where picture.superview === container {
            guard let center = pictureCenters[ObjectIdentifier(picture)] else { continue }
            picture.center = CGPoint(x: center.x + origin.x - bubbleStart.x, y: center.y + origin.y - bubbleStart.y)
        }
    }

    private func finish() {
        clock.stop()
        if let bubble, bubble.layer.mask === maskLayer {
            bubble.layer.mask = nil
        }
    }

    private func add(_ picture: UIView, to container: UIView) {
        picture.isUserInteractionEnabled = false
        picture.isAccessibilityElement = false
        // Over the rows, which stand at their own layers in the list
        picture.layer.zPosition = 100
        container.addSubview(picture)
        pictureCenters[ObjectIdentifier(picture)] = picture.center
    }
}

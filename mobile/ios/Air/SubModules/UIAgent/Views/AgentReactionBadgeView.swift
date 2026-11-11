import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The reactions an answer takes, as the menu's cloud offers them and the bubble's corner shows them
extension ApiAgentV2AnswerFeedback {
    /// The cloud's order: the heart first, then the broken heart
    static let reactionOrder: [ApiAgentV2AnswerFeedback] = [.like, .dislike]

    /// The reaction's still icon, the first frame of Telegram's selection animation drawn as the cloud's icon, once per
    /// session
    @MainActor
    var reactionImage: UIImage {
        AgentReactionAnimations.getStill(
            .select,
            of: self,
            at: .begin,
            boxSize: AgentReactionEmojiMetrics.cloudBoxSize,
            size: AgentFeedbackPillMetrics.iconSize
        )
    }

    /// What the cloud's button does
    var reactionActionTitle: String {
        switch self {
        case .like: lang("Like")
        case .dislike: lang("Dislike")
        }
    }

    /// What the bubble says of its answer once it is rated
    var reactionStateTitle: String {
        switch self {
        case .like: lang("Liked")
        case .dislike: lang("Disliked")
        }
    }
}

/// An answer's reaction on its bubble, as Telegram's message shows one: the reaction's emoji alone, pinned to the
/// bubble's bottom trailing corner with its middle 3 pt inside the bubble's trailing edge, taking no room in the chat
final class AgentReactionBadgeView: UIView {
    enum Metrics {
        static let iconSize: CGFloat = 22
        /// How far the emoji's middle stands inside the bubble's trailing edge
        static let trailingInset: CGFloat = 3
        /// How far the emoji's bottom reaches below the bubble's bottom edge
        static let bottomOverhang: CGFloat = 3
        /// How far around the emoji a tap still reaches it
        static let touchOutset: CGFloat = 8
        static let size = CGSize(width: iconSize, height: iconSize)
    }

    /// The motion of the corner's emoji
    enum Motion {
        /// Telegram's swap of a message's reaction: the one that goes scales to 0.2 and fades out over 0.12 s
        static let swapScale: CGFloat = 0.2
        static let swapDuration: TimeInterval = 0.12
        /// With Reduce Motion the emoji fades in and out over 0.2 s
        static let fadeDuration: TimeInterval = 0.2
    }

    /// The emoji's frame in the coordinates of `bubbleFrame`, the bubble's
    static func getFrame(forBubble bubbleFrame: CGRect, isRightToLeft: Bool) -> CGRect {
        let midX = isRightToLeft
            ? bubbleFrame.minX + Metrics.trailingInset
            : bubbleFrame.maxX - Metrics.trailingInset
        let maxY = bubbleFrame.maxY + Metrics.bottomOverhang
        return CGRect(
            x: midX - Metrics.iconSize / 2,
            y: maxY - Metrics.iconSize,
            width: Metrics.iconSize,
            height: Metrics.iconSize
        )
    }

    /// The reaction the corner shows
    private(set) var feedback: ApiAgentV2AnswerFeedback?
    var onTap: (() -> Void)?

    /// The reaction's emoji, in twice the 22 pt icon's square, as Telegram's message reactions draw theirs
    let iconView = AgentReactionEmojiView(boxSize: AgentReactionEmojiMetrics.badgeBoxSize)
    /// A reaction's emoji that goes as another one lands, or as the reaction is withdrawn
    private var leavingViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isHidden = true
        addSubview(iconView)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.bounds = CGRect(x: 0, y: 0, width: iconView.boxSize, height: iconView.boxSize)
        iconView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Shows `feedback` at once, resting on the last frame of Telegram's landing, or no emoji without one
    func show(_ feedback: ApiAgentV2AnswerFeedback?) {
        removeLeavingViews()
        iconView.layer.removeAllAnimations()
        iconView.alpha = 1
        iconView.transform = .identity
        self.feedback = feedback
        isHidden = feedback == nil
        if let feedback {
            iconView.showStill(.center, of: feedback, at: .end)
        } else {
            iconView.clear()
        }
    }

    /// A chosen reaction reaches the corner: its emoji takes the flying one's place in the same frame and plays
    /// Telegram's landing from its first frame, while another reaction that showed there scales down and fades out
    func land(_ feedback: ApiAgentV2AnswerFeedback) {
        if !isHidden, self.feedback != nil, iconView.alpha > 0 {
            swapOut()
        }
        iconView.layer.removeAllAnimations()
        iconView.alpha = 1
        iconView.transform = .identity
        self.feedback = feedback
        isHidden = false
        if AgentReactionMotion.isReduced {
            iconView.showStill(.center, of: feedback, at: .end)
        } else {
            iconView.play(.center, of: feedback)
        }
    }

    /// Changes the corner's reaction in place, without a flight: a withdrawn one scales down and fades out as Telegram's
    /// does, and a new one lands. With Reduce Motion the emoji fades out or in instead.
    func animate(to feedback: ApiAgentV2AnswerFeedback?) {
        guard feedback != self.feedback || feedback != nil && isHidden else { return }
        guard AgentReactionMotion.isReduced else {
            if let feedback {
                land(feedback)
            } else {
                withdraw()
            }
            return
        }
        guard let feedback else {
            self.feedback = nil
            UIView.animate(withDuration: Motion.fadeDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.iconView.alpha = 0
            } completion: { _ in
                guard self.feedback == nil else { return }
                self.show(nil)
            }
            return
        }
        let wasShown = !isHidden && iconView.alpha > 0
        self.feedback = feedback
        isHidden = false
        iconView.layer.removeAllAnimations()
        iconView.transform = .identity
        guard wasShown else {
            iconView.showStill(.center, of: feedback, at: .end)
            iconView.alpha = 0
            UIView.animate(withDuration: Motion.fadeDuration, delay: 0, options: [.allowUserInteraction]) {
                self.iconView.alpha = 1
            }
            return
        }
        UIView.transition(with: iconView, duration: Motion.fadeDuration, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.iconView.showStill(.center, of: feedback, at: .end)
        }
    }

    /// The reaction is withdrawn: its emoji scales down and fades out as Telegram's does
    private func withdraw() {
        feedback = nil
        guard !isHidden else { return }
        UIView.animate(
            withDuration: Motion.swapDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn, .allowUserInteraction]
        ) {
            self.iconView.transform = CGAffineTransform(scaleX: Motion.swapScale, y: Motion.swapScale)
            self.iconView.alpha = 0
        } completion: { _ in
            guard self.feedback == nil else { return }
            self.show(nil)
        }
    }

    /// The emoji that shows goes, scaling down and fading out, while another one takes its place
    private func swapOut() {
        let leaving = UIImageView(image: iconView.currentDrawing)
        leaving.isUserInteractionEnabled = false
        leaving.bounds = iconView.bounds
        leaving.center = iconView.center
        leaving.transform = iconView.transform
        leaving.alpha = iconView.alpha
        insertSubview(leaving, belowSubview: iconView)
        leavingViews.append(leaving)
        UIView.animate(
            withDuration: Motion.swapDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn, .allowUserInteraction]
        ) {
            leaving.transform = CGAffineTransform(scaleX: Motion.swapScale, y: Motion.swapScale)
            leaving.alpha = 0
        } completion: { [weak self, weak leaving] _ in
            guard let leaving else { return }
            leaving.removeFromSuperview()
            self?.leavingViews.removeAll { $0 === leaving }
        }
    }

    private func removeLeavingViews() {
        leavingViews.forEach { $0.removeFromSuperview() }
        leavingViews.removeAll()
    }

    /// Where the 22 pt icon shows on screen now, as its row carries it, in the window's coordinates
    var presentedIconFrameInWindow: CGRect? {
        guard let window else { return nil }
        let presentedLayer = layer.presentation() ?? layer
        let rootLayer = window.layer.presentation() ?? window.layer
        return presentedLayer.convert(bounds, to: rootLayer)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, feedback != nil else { return false }
        return bounds.insetBy(dx: -Metrics.touchOutset, dy: -Metrics.touchOutset).contains(point)
    }

    @objc private func handleTap() {
        onTap?()
    }
}

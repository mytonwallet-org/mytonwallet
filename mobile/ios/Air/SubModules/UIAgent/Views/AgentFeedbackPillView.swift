import ContextMenuKit
import UIComponents
import UIKit
import WalletContext
import WalletCore

enum AgentFeedbackPillMetrics {
    static let bodySize = CGSize(width: 108, height: 56)
    static let iconSize: CGFloat = 36
    static let iconTop: CGFloat = 10
    /// The icons' leading edges in the capsule: the heart's, then the broken heart's
    static let iconLeadings: [CGFloat] = [12, 60]
    static let buttonWidth: CGFloat = 48
    static let selectionDiameter: CGFloat = 44
    /// The rating's circle, the same for every reaction, as Telegram's: the system's neutral fill, a soft grey on the
    /// cloud's glass in both themes
    static let selectionColor: UIColor = .tertiarySystemFill
    /// The thought bubble's tail: a 16 pt circle on the capsule's bottom edge and an 8 pt one under it, toward the
    /// trailing side, which go down beside the answer's top trailing corner
    static let largeTailCircle = CGRect(x: 65 - 8, y: 56 - 8, width: 16, height: 16)
    static let smallTailCircle = CGRect(x: 74 - 4, y: 70 - 4, width: 8, height: 8)
    static let size = CGSize(width: bodySize.width, height: smallTailCircle.maxY)
    /// The capsule's bottom stands this far above the answer's top
    static let answerSpacing: CGFloat = 6
    /// How far the capsule's trailing edge reaches past the answer's: the large circle's centre is 4 pt past it
    static let answerOverhang: CGFloat = bodySize.width - largeTailCircle.midX + 4
    /// Near the screen's side the capsule slides inward and keeps this far from it, its tail kept at the answer
    static let screenInset: CGFloat = 12
    /// The tail at the answer's corner keeps this far from the screen's side and its large circle's centre over the
    /// capsule; otherwise it hangs from the capsule as the design draws it, over the answer's top
    static let tailEdgeSpacing: CGFloat = 4
    /// Telegram's appearance of the rating's circle: it grows from 0.01 of its size on Telegram's spring, mass 5,
    /// stiffness 900 and damping 88, played over 0.4 s, and fades in over 0.2 s
    static let selectionAppearScale: CGFloat = 0.01
    static let selectionAppearDuration: TimeInterval = 0.4
    static let selectionAppearFadeDuration: TimeInterval = 0.2
    static let selectionSpringMass: CGFloat = 5
    static let selectionSpringStiffness: CGFloat = 900
    static let selectionSpringDamping: CGFloat = 88
    static let pressedScale: CGFloat = 0.85
}

/// The cloud of reactions that the menu of a complete answer shows over the answer, as Telegram's reactions panel: a
/// heart and a broken heart on a capsule of the menu panel's own material and shadow, with a thought bubble's tail down
/// to the answer's corner. The icons are Telegram's animated emoji, and the current rating has Telegram's neutral
/// circle behind it. A chosen icon leaves the cloud for the answer's corner as the cloud closes into its tail; a long
/// press on one chooses it as a tap does, on release.
final class AgentFeedbackPillView: UIView, ContextMenuAccessoryAnimating {
    /// A choice in the cloud: the new rating, nil when the chosen one is pressed again, its icon in the cloud, which
    /// leaves for the answer's corner, and where a part of the answer shows on the menu's replica of it
    struct Selection {
        let feedback: ApiAgentV2AnswerFeedback?
        var icon: AgentReactionEmojiView?
        var getSourceFrameOnScreen: (@MainActor (CGRect) -> CGRect?)?
    }

    /// Makes the menu accessory. `onSelect` gets the choice as the menu starts to close, and `onMenuDidClose` once the
    /// menu is gone and the answer shows in its place again.
    static func makeMenuAccessory(
        feedback: ApiAgentV2AnswerFeedback?,
        onSelect: @escaping @MainActor (Selection) -> Void,
        onMenuDidClose: @escaping @MainActor (Selection) -> Void
    ) -> ContextMenuAccessory {
        ContextMenuAccessory(
            size: AgentFeedbackPillMetrics.size,
            topTrailingOffset: CGVector(
                dx: AgentFeedbackPillMetrics.answerOverhang,
                dy: -AgentFeedbackPillMetrics.answerSpacing - AgentFeedbackPillMetrics.bodySize.height
            ),
            backgroundCapsules: [
                CGRect(origin: .zero, size: AgentFeedbackPillMetrics.bodySize),
                AgentFeedbackPillMetrics.largeTailCircle,
                AgentFeedbackPillMetrics.smallTailCircle,
            ],
            tail: ContextMenuAccessoryTail(
                capsuleIndices: [1, 2],
                screenInset: AgentFeedbackPillMetrics.screenInset,
                edgeSpacing: AgentFeedbackPillMetrics.tailEdgeSpacing
            ),
            motion: .thoughtBubble,
            // The cloud is the menu panel's material, with its tint and its shadow. The pill swells and stretches
            // under the finger as the system's glass does.
            isGlassInteractive: true
        ) { context in
            AgentFeedbackPillView(feedback: feedback) { selection in
                var selection = selection
                selection.getSourceFrameOnScreen = { context.getSourceFrameOnScreen($0) }
                onSelect(selection)
                context.dismiss {
                    onMenuDidClose(selection)
                }
            }
        }
    }

    private(set) var buttons: [AgentReactionButton] = []
    /// The reaction chosen in the cloud
    private(set) var chosenOption: ApiAgentV2AnswerFeedback?
    private let onSelect: @MainActor (Selection) -> Void

    init(feedback: ApiAgentV2AnswerFeedback?, onSelect: @escaping @MainActor (Selection) -> Void) {
        self.onSelect = onSelect
        super.init(frame: CGRect(origin: .zero, size: AgentFeedbackPillMetrics.size))
        backgroundColor = .clear
        buttons = ApiAgentV2AnswerFeedback.reactionOrder.map { option in
            let button = AgentReactionButton(option: option, isSelected: option == feedback)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                self.choose(button)
            }, for: .touchUpInside)
            addSubview(button)
            return button
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (button, iconLeading) in zip(buttons, AgentFeedbackPillMetrics.iconLeadings) {
            let iconMidX = iconLeading + AgentFeedbackPillMetrics.iconSize / 2
            let midX = isRightToLeft ? bounds.width - iconMidX : iconMidX
            button.bounds = CGRect(
                x: 0,
                y: 0,
                width: AgentFeedbackPillMetrics.buttonWidth,
                height: AgentFeedbackPillMetrics.bodySize.height
            )
            button.center = CGPoint(x: midX, y: AgentFeedbackPillMetrics.bodySize.height / 2)
        }
    }

    /// The answer's rating, which the cloud shows
    var ratedOption: ApiAgentV2AnswerFeedback? {
        buttons.first { $0.isSelected }?.option
    }

    func getButton(for feedback: ApiAgentV2AnswerFeedback) -> AgentReactionButton? {
        buttons.first { $0.option == feedback }
    }

    /// Rates with `button`'s reaction, or withdraws the rating it is; a chosen reaction's icon leaves the cloud for the
    /// answer's corner. As in Telegram, the choice itself plays no haptic: a reaction's tap comes as it hits the corner.
    private func choose(_ button: AgentReactionButton) {
        let isWithdrawal = button.isSelected
        chosenOption = isWithdrawal ? nil : button.option
        onSelect(Selection(feedback: chosenOption, icon: isWithdrawal ? nil : button.iconView))
    }

    // MARK: - ContextMenuAccessoryAnimating

    /// Each icon plays Telegram's appearance as the growing capsule reaches it, the one beside the tail first, and
    /// rests on the reaction's still, and the rating's circle appears with it as Telegram's does. With Reduce Motion the
    /// icons show their stills.
    func animateAccessoryAppearance(_ appearance: ContextMenuAccessoryAppearance) {
        layoutIfNeeded()
        guard !appearance.isReduced else { return }
        for button in buttons {
            let delay = appearance.getRevealDelay(forX: button.center.x)
            button.iconView.alpha = 0
            button.selectionView.alpha = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak button] in
                guard let button, button.iconView.alpha == 0 else { return }
                button.iconView.alpha = 1
                button.iconView.play(.appear, of: button.option)
                button.animateSelectionAppearance()
            }
        }
    }
}

/// A reaction in the cloud: its emoji, over Telegram's neutral circle while it is the answer's rating, which shrinks a
/// little under the finger and plays Telegram's selection there
final class AgentReactionButton: UIControl {
    let option: ApiAgentV2AnswerFeedback
    let selectionView = UIView()
    /// The emoji, in a box a little larger than the 36 pt icon
    let iconView = AgentReactionEmojiView(boxSize: AgentReactionEmojiMetrics.cloudBoxSize)

    init(option: ApiAgentV2AnswerFeedback, isSelected: Bool) {
        self.option = option
        super.init(frame: .zero)
        selectionView.isUserInteractionEnabled = false
        selectionView.backgroundColor = AgentFeedbackPillMetrics.selectionColor
        selectionView.isHidden = !isSelected
        addSubview(selectionView)
        iconView.showStill(.select, of: option, at: .begin)
        addSubview(iconView)
        self.isSelected = isSelected
        isAccessibilityElement = true
        accessibilityLabel = option.reactionActionTitle
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let scale = isHighlighted ? AgentFeedbackPillMetrics.pressedScale : 1
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.iconView.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
            if isHighlighted, iconView.alpha > 0, !AgentReactionMotion.isReduced {
                iconView.play(.select, of: option)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let diameter = AgentFeedbackPillMetrics.selectionDiameter
        // Through the bounds and the centre, which keep the circle's appearance transform out of it
        selectionView.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        selectionView.center = center
        selectionView.layer.cornerRadius = diameter / 2
        iconView.bounds = CGRect(x: 0, y: 0, width: iconView.boxSize, height: iconView.boxSize)
        iconView.center = center
    }

    /// The circle appears as Telegram's does: it grows from nothing on Telegram's spring over 0.4 s and fades in over
    /// 0.2 s
    func animateSelectionAppearance() {
        let layer = selectionView.layer
        selectionView.transform = .identity
        selectionView.alpha = 1
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.mass = AgentFeedbackPillMetrics.selectionSpringMass
        scale.stiffness = AgentFeedbackPillMetrics.selectionSpringStiffness
        scale.damping = AgentFeedbackPillMetrics.selectionSpringDamping
        scale.fromValue = AgentFeedbackPillMetrics.selectionAppearScale
        scale.toValue = 1
        scale.timingFunction = CAMediaTimingFunction(name: .linear)
        scale.duration = scale.settlingDuration
        scale.speed = Float(scale.settlingDuration / AgentFeedbackPillMetrics.selectionAppearDuration)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = AgentFeedbackPillMetrics.selectionAppearFadeDuration
        // Under UIKit's keys, so that the circle's own later motion takes over from where it shows
        layer.add(scale, forKey: "transform")
        layer.add(fade, forKey: "opacity")
    }

    /// The 36 pt icon, in the middle of the emoji's box, in the button's coordinates
    var iconFrame: CGRect {
        let size = AgentFeedbackPillMetrics.iconSize
        return CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
    }
}

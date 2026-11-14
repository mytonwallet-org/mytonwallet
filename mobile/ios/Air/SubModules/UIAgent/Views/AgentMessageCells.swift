import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

enum AgentContentLayout {
    static let maxContentWidth: CGFloat = 580
}

enum AgentMessageCellMetrics {
    /// Bubbles stand as far from the sides as News' cards do
    static let horizontalInset: CGFloat = 16
    static let outgoingOppositeInset: CGFloat = 72
    static let outgoingMaxWidthMultiplier: CGFloat = 0.8
    static let incomingTrailingInset: CGFloat = 16
    static let followupHorizontalInset: CGFloat = horizontalInset
    static let bubbleToButtonSpacing: CGFloat = 3
    static let actionBottomSpacing: CGFloat = 7
    static let minimumBubbleWidth: CGFloat = 44
    static let minimumBubbleHeight: CGFloat = 40
    static let bodyHorizontalPadding: CGFloat = 14
    static let bodyVerticalPadding: CGFloat = 10
    static let supplementaryErrorSpacing: CGFloat = 8
    static let typingIndicatorStatusSpacing: CGFloat = 8
    static let typingIndicatorDotsWidth: CGFloat = 36
    static let typingIndicatorDotsHeight: CGFloat = 12
    static let actionOuterPadding = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
    static let actionContainerInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    static let systemPreviewCornerRadius: CGFloat = 12
    static let systemPreviewInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    /// The author over an answer stands in from the bubble's edge and a little above it, as in Classic
    static let authorLeadingInset: CGFloat = 8
    static let authorSpacing: CGFloat = 6
}

private final class AgentMessageTextView: UITextView {
    var onURLTap: ((URL) -> Void)?
    private var linkMenu: AgentLinkMenu?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        linkMenu = AgentLinkMenu(source: self, linkAt: { [weak self] point in
            self?.linkValue(at: point) as? URL
        }, open: { [weak self] url in self?.onURLTap?(url) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeFirstResponder: Bool { false }

    override var selectedTextRange: UITextRange? {
        get { nil }
        set { }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return linkValue(at: point) != nil
    }

    private func linkValue(at point: CGPoint) -> Any? {
        guard textStorage.length > 0 else { return nil }

        let containerPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.contains(containerPoint) else { return nil }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }
}

/// An answer's bubble with its action rows, and its reaction's emoji on the bubble's bottom trailing corner, over the
/// action rows, which takes touches past the bubble's edge
private final class AgentBubbleStackView: UIStackView {
    let reactionBadgeView = AgentReactionBadgeView()
    weak var bubbleView: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let bubbleView else { return }
        bringSubviewToFront(reactionBadgeView)
        reactionBadgeView.frame = AgentReactionBadgeView.getFrame(
            forBubble: bubbleView.frame,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event)
            || reactionBadgeView.point(inside: convert(point, to: reactionBadgeView), with: event)
    }
}

protocol AgentContextMenuPresentingCell: UICollectionViewCell {
    var contextMenuCopyText: String? { get }
}

private extension UICollectionViewCell {
    func setupCenteredContentLayoutGuide(_ guide: UILayoutGuide) {
        contentView.addLayoutGuide(guide)

        let widthConstraint = guide.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        widthConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            guide.topAnchor.constraint(equalTo: contentView.topAnchor),
            guide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            guide.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            guide.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            guide.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            guide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            widthConstraint
        ])
    }
}

final class AgentFollowupView: UIStackView {
    private enum Metrics {
        static let horizontalInset = AgentMessageCellMetrics.followupHorizontalInset
        static let revealOffset: CGFloat = 8
        static let revealDuration: TimeInterval = 0.3
        static let revealStagger: TimeInterval = 0.15
        /// The placeholders' widths, as of suggestions of a line
        static let placeholderWidths: [CGFloat] = [230, 270, 200]
        /// How long a placeholder's pill takes to resize to its suggestion, on Telegram's curve
        static let fillDuration: CFTimeInterval = 0.36
        /// When the suggestion's title starts fading in as its pill resizes, and how long it takes
        static let fillTitleDelay: CFTimeInterval = 0.14
        static let fillTitleDuration: CFTimeInterval = 0.22
        /// How long the passing light takes to fade from a pill that got its suggestion
        static let fillLightFadeDuration: TimeInterval = 0.15
    }

    /// A suggestion's pill standing in for it while it loads, with the passing light inside
    private struct Placeholder {
        let button: AgentSuggestionButton
        let sizeConstraints: [NSLayoutConstraint]
    }

    /// A placeholder's pill resizing from `startFrame`, in its button, to the suggestion it got
    private struct PillFill {
        let button: AgentSuggestionButton
        let startFrame: CGRect
    }

    static let placeholderIdentifier = "agent_followup_placeholder"
    private static let fillCurve = AgentComposerMetrics.makeTelegramCurve()

    /// How long one suggestion takes to come in, and its curve, which the tail of the bubble it hangs from follows
    static let revealDuration = Metrics.revealDuration
    static func makeRevealTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeOut)
    }

    private weak var contentLayoutGuide: UILayoutGuide?
    private var buttonsByID: [String: AgentSuggestionButton] = [:]
    private var onControlTap: ((String) -> Void)?
    private var placeholders: [Placeholder] = []
    private var loadingRevealCompletedAt: CFTimeInterval?
    private var pillFills: [PillFill] = []
    private var pillFillStartTime: CFTimeInterval = 0
    private lazy var pillFillClock = GlassMotionClock(frameRateRange: nil) { [weak self] time in
        self?.stepPillFills(at: time)
    }

    /// Stands placeholders in for the suggestions: their pills, with the real pill's fill and border and the passing light
    /// only inside, which the suggestions fill once they come
    func showLoading() {
        guard placeholders.isEmpty else { return }
        reset()
        isHidden = false
        accessibilityLabel = lang("Loading...")
        for width in Metrics.placeholderWidths {
            let button = AgentSuggestionButton()
            button.configure(title: "")
            button.isUserInteractionEnabled = false
            button.isAccessibilityElement = false
            button.accessibilityIdentifier = Self.placeholderIdentifier
            // The placeholder's width holds the pill until a title sizes it
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let light = AgentMessagesSkeletonView(style: .suggestion)
            light.isAccessibilityElement = false
            button.pillOverlayView = light
            addArrangedSubview(button)
            let preferredWidth = button.widthAnchor.constraint(equalToConstant: width)
            preferredWidth.priority = .defaultHigh
            let height = button.heightAnchor.constraint(equalToConstant: AgentSuggestionButton.height)
            NSLayoutConstraint.activate([preferredWidth, height])
            constrainToColumn(button)
            placeholders.append(Placeholder(button: button, sizeConstraints: [preferredWidth, height]))
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        alignment = .leading
        spacing = AgentSuggestionButton.spacing
        isHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The suggestions continue the column of the bubble they hang from: the first stands as far below the bubble as
    /// the next ones below it
    func install(
        in contentView: UIView,
        below bubbleView: UIView,
        contentLayoutGuide: UILayoutGuide
    ) -> [NSLayoutConstraint] {
        self.contentLayoutGuide = contentLayoutGuide
        contentView.addSubview(self)
        return [
            topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: AgentSuggestionButton.spacing),
            leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: Metrics.horizontalInset),
            trailingAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.trailingAnchor, constant: -Metrics.horizontalInset),
            bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ]
    }

    func configure(
        controls: [AgentMessageControl],
        isVisible: Bool,
        animatesAppearance: Bool,
        onControlTap: ((String) -> Void)?
    ) {
        let controls = controls.filter { $0.kind == .followup }
        let isPlaceholderRevealDone = loadingRevealCompletedAt.map { CACurrentMediaTime() >= $0 } ?? false
        loadingRevealCompletedAt = nil
        // The placeholders keep their frames out of the arrangement, which the suggestions that fill them start from
        var placeholdersLeft = placeholders[...]
        placeholders.removeAll()
        for placeholder in placeholdersLeft {
            removeArrangedSubview(placeholder.button)
        }
        accessibilityLabel = nil
        let revealsFollowups = animatesAppearance && isVisible && isHidden
        isHidden = !isVisible
        self.onControlTap = controls.isEmpty ? nil : onControlTap
        for button in buttonsByID.values {
            removeArrangedSubview(button)
        }
        let controlIDs = Set(controls.map(\.id))
        for id in buttonsByID.keys.filter({ !controlIDs.contains($0) }) {
            buttonsByID.removeValue(forKey: id)?.removeFromSuperview()
        }
        var filledPlaceholders: [PillFill] = []
        var addedButtons: [AgentSuggestionButton] = []
        for control in controls {
            let button: AgentSuggestionButton
            if let existingButton = buttonsByID[control.id] {
                button = existingButton
            } else {
                if let placeholder = placeholdersLeft.popFirst() {
                    // The suggestion fills the placeholder's pill: only its title comes in, and the pill takes its size
                    button = placeholder.button
                    NSLayoutConstraint.deactivate(placeholder.sizeConstraints)
                    button.setContentHuggingPriority(.required, for: .horizontal)
                    button.isUserInteractionEnabled = true
                    button.isAccessibilityElement = true
                    filledPlaceholders.append(PillFill(button: button, startFrame: button.frame))
                } else {
                    button = AgentSuggestionButton()
                    addArrangedSubview(button)
                    constrainToColumn(button)
                    addedButtons.append(button)
                }
                button.accessibilityIdentifier = "agent_followup"
                button.maximumNumberOfLines = 0
                button.addAction(UIAction { [weak self] _ in
                    self?.onControlTap?(control.id)
                }, for: .touchUpInside)
                buttonsByID[control.id] = button
            }
            button.configure(title: control.title, showsArrow: true)
            button.preferredMaxLayoutWidth = maxWidth
            button.isEnabled = control.isEnabled
            addArrangedSubview(button)
        }
        for placeholder in placeholdersLeft {
            placeholder.button.removeFromSuperview()
        }
        guard !filledPlaceholders.isEmpty else {
            if revealsFollowups {
                animateAppearance()
            }
            return
        }
        guard !UIAccessibility.isReduceMotionEnabled, window != nil else {
            for fill in filledPlaceholders {
                fill.button.pillOverlayView = nil
            }
            return
        }
        layoutIfNeeded()
        fillPlaceholders(filledPlaceholders, revealing: addedButtons, isPlaceholderRevealDone: isPlaceholderRevealDone)
    }

    /// The placeholders' pills take the sizes of the suggestions that fill them on Telegram's curve, with no change of
    /// fill or border, as the titles fade in and the passing light fades out. While the placeholders still come in
    /// one by one, the titles follow them. The suggestions beyond the placeholders come in after the last title, one
    /// after another, as suggestions do.
    private func fillPlaceholders(
        _ fills: [PillFill],
        revealing addedButtons: [AgentSuggestionButton],
        isPlaceholderRevealDone: Bool
    ) {
        let now = CACurrentMediaTime()
        pillFills = fills.map { fill in
            PillFill(button: fill.button, startFrame: convert(fill.startFrame, to: fill.button))
        }
        var lastTitleDelay = Metrics.fillTitleDelay
        for (index, fill) in pillFills.enumerated() {
            fill.button.pillFrameOverride = fill.startFrame
            fill.button.layoutIfNeeded()
            let stagger = isPlaceholderRevealDone ? 0 : Metrics.revealStagger * Double(index)
            lastTitleDelay = Metrics.fillTitleDelay + stagger
            fill.button.animateContentAppearance(delay: lastTitleDelay, duration: Metrics.fillTitleDuration)
            guard let light = fill.button.pillOverlayView else { continue }
            UIView.animate(withDuration: Metrics.fillLightFadeDuration) {
                light.alpha = 0
            } completion: { [weak button = fill.button, weak light] _ in
                guard let button, let light, button.pillOverlayView === light else { return }
                button.pillOverlayView = nil
            }
        }
        revealSuggestions(addedButtons, startingAt: now + lastTitleDelay + Metrics.revealStagger)
        pillFillStartTime = CACurrentMediaTime()
        pillFillClock.start()
    }

    private func stepPillFills(at time: CFTimeInterval) {
        let fraction = min(1, max(0, (time - pillFillStartTime) / Metrics.fillDuration))
        let progress = AgentLayerAnimationSampler.getEasedFraction(Self.fillCurve, at: fraction)
        for fill in pillFills {
            fill.button.pillFrameOverride = fraction < 1 ? Self.interpolate(fill.startFrame, fill.button.bounds, progress) : nil
            fill.button.layoutIfNeeded()
        }
        guard fraction >= 1 else { return }
        finishPillFills()
    }

    private func finishPillFills() {
        pillFillClock.stop()
        for fill in pillFills {
            fill.button.pillFrameOverride = nil
        }
        pillFills.removeAll()
    }

    /// Whether placeholders' pills are resizing to the suggestions that fill them, which the chat's tests watch
    var isFillingPlaceholders: Bool {
        !pillFills.isEmpty
    }

    private static func interpolate(_ from: CGRect, _ to: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    /// Long suggestions wrap within the column instead of being cut off
    private func constrainToColumn(_ button: AgentSuggestionButton) {
        guard let contentLayoutGuide else { return }
        button.widthAnchor.constraint(
            lessThanOrEqualTo: contentLayoutGuide.widthAnchor,
            constant: -Metrics.horizontalInset * 2
        ).isActive = true
    }

    func reset() {
        loadingRevealCompletedAt = nil
        finishPillFills()
        for placeholder in placeholders {
            removeArrangedSubview(placeholder.button)
            placeholder.button.removeFromSuperview()
        }
        placeholders.removeAll()
        for button in buttonsByID.values {
            removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttonsByID.removeAll()
        onControlTap = nil
        isHidden = true
    }

    func getButton(controlID: String) -> AgentSuggestionButton? {
        buttonsByID[controlID].flatMap { $0.isHidden || isHidden ? nil : $0 }
    }

    func updateMaxWidth() {
        let maxWidth = maxWidth
        for button in buttonsByID.values {
            button.preferredMaxLayoutWidth = maxWidth
        }
    }

    private var maxWidth: CGFloat {
        (contentLayoutGuide?.layoutFrame.width ?? 0) - Metrics.horizontalInset * 2
    }

    /// The suggestions come in one after another, each out of a blur as it fades in and rises into place. The reveal
    /// adds to what each suggestion shows rather than setting it, so a suggestion enabled or disabled meanwhile ends as
    /// it is now, and it plays as well inside an update that runs without animation, as the chat's update of its rows.
    func animateAppearance(delay: TimeInterval = 0) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let now = CACurrentMediaTime() + delay
        if !placeholders.isEmpty {
            loadingRevealCompletedAt = now + Metrics.revealDuration
                + Metrics.revealStagger * Double(max(0, placeholders.count - 1))
        }
        revealSuggestions(arrangedSubviews, startingAt: now)
    }

    /// Each of `views` comes out of a blur as it fades in and rises into place, the first at `startTime` and each next
    /// one `Metrics.revealStagger` later
    private func revealSuggestions(_ views: [UIView], startingAt startTime: CFTimeInterval) {
        for (index, view) in views.enumerated() {
            let beginTime = view.layer.convertTime(startTime, from: nil) + Metrics.revealStagger * Double(index)
            view.layer.add(
                Self.makeRevealAnimation(keyPath: "opacity", from: -1, beginTime: beginTime),
                forKey: Self.revealOpacityKey
            )
            view.layer.add(
                Self.makeRevealAnimation(keyPath: "transform.translation.y", from: Metrics.revealOffset, beginTime: beginTime),
                forKey: Self.revealOffsetKey
            )
            Self.addRevealBlur(to: view.layer, beginTime: beginTime)
        }
    }

    /// Whether the suggestions are coming in now, which the chat's tests watch
    var isRevealing: Bool {
        arrangedSubviews.contains { $0.layer.animation(forKey: Self.revealBlurKey) != nil }
    }

    /// The suggestion comes into focus from `AgentBlurTransition.radius` of blur as it fades in
    private static func addRevealBlur(to layer: CALayer, beginTime: CFTimeInterval) {
        guard let blur = WBlurredContentView.makeGaussianBlurFilter() else { return }
        blur.setValue(0, forKey: "inputRadius")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.filters = [blur]
        CATransaction.setCompletionBlock { [weak layer] in
            // A later reveal keeps its own blur
            guard let layer, layer.animation(forKey: revealBlurKey) == nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.filters = nil
            CATransaction.commit()
        }
        let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
        animation.fromValue = AgentBlurTransition.radius
        animation.toValue = 0
        animation.duration = Metrics.revealDuration
        animation.beginTime = beginTime
        animation.fillMode = .backwards
        animation.timingFunction = makeRevealTimingFunction()
        layer.add(animation, forKey: revealBlurKey)
        CATransaction.commit()
    }

    /// From `from` added to the layer's own value back to that value: an opacity of 1 less shows nothing until then
    private static func makeRevealAnimation(keyPath: String, from: CGFloat, beginTime: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = 0
        animation.isAdditive = true
        animation.duration = Metrics.revealDuration
        animation.beginTime = beginTime
        animation.fillMode = .backwards
        animation.timingFunction = makeRevealTimingFunction()
        return animation
    }

    private static let revealOpacityKey = "agentFollowupRevealOpacity"
    private static let revealBlurKey = "agentFollowupRevealBlur"
    private static let revealOffsetKey = "agentFollowupRevealOffset"
}

final class AgentMessageCell: UICollectionViewCell, AgentContextMenuPresentingCell, UITextViewDelegate {
    private struct AssistantConfiguration {
        var message: AgentMessage
        let textColor: UIColor
        var hasStreaming: Bool
        var hadStreaming: Bool
        var blocks: [AgentMessageBlock]
        /// What the reveal view shows: the whole text, or while it streams, the text after its closed tables and code
        var streamingText: String
        /// How many of the text's lines went into `blocks` while it streams
        var settledLineCount = 0
    }

    private struct AppliedRichContent {
        let messageID: AgentItemID
        let blocks: [AgentMessageBlock]
        let layoutMaxWidth: CGFloat
        let renderingPolicy: AgentMessageRenderingPolicy
        let isStreaming: Bool
    }

    private struct AppliedSemanticContent {
        let messageID: AgentItemID
        let content: ApiAgentV2SemanticContent
        let localeIdentifier: String
    }

    var onPreferredHeightChanged: ((_ animated: Bool) -> Void)?
    var onStreamingRevealCompleted: (() -> Void)?
    var minimumHeightProvider: (() -> CGFloat)?
    /// Builds the message's menu when a tap or a long press on the bubble opens it, or returns `nil` to keep it closed
    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)?

    var isRevealingStreamedText: Bool {
        wasStreamingMessage
    }

    private let contentLayoutGuide = UILayoutGuide()
    /// The answer's author over it, in a chat an operator has joined
    private let authorView = AgentMessageAuthorView()
    private let bubbleStackView = AgentBubbleStackView()
    private let bubbleView = AgentBubbleBackgroundView()
    var skeletonRevealView: UIView { bubbleView }
    /// The bubble, which an answer grows out of the typing row with, and a question out of the suggestion tapped
    var bubbleBackgroundView: AgentBubbleBackgroundView { bubbleView }
    /// What appears as a sent question appears where it lands: the bubble with what hangs from it
    var sentAppearanceView: UIView { bubbleStackView }
    /// A sent question's text, which the text it was sent from lines up with
    var sentTextView: UIView { userMessageTextView }

    /// The suggestion of `controlID` under the answer, which turns into the question's bubble once tapped
    func getFollowupButton(controlID: String) -> AgentSuggestionButton? {
        followupView.getButton(controlID: controlID)
    }
    private let contentStackView = UIStackView()
    private let actionBackgroundView = AgentBubbleBackgroundView()
    private let userMessageTextView = AgentMessageTextView()
    private let assistantMessageTextView = AgentStreamingTextView()
    private let assistantRichMessageView = AgentRichMessageView()
    private let assistantSemanticContentView = AgentV2SemanticContentView(style: .embedded)
    private let assistantSupplementaryErrorLabel = UILabel()
    private let actionStackView = UIStackView()
    private let followupView = AgentFollowupView()
    private var followupConstraints: [NSLayoutConstraint] = []
    private var controlButtonsByID: [String: UIButton] = [:]
    private var configuredMessageID: AgentItemID?
    /// While the menu that changed the answer's rating closes, and while the reaction it chose flies to the corner, the
    /// corner keeps the menu's choice, whatever ratings the message brings meanwhile; then it takes the rating the
    /// message has by then
    private(set) var isFeedbackHeld = false
    private(set) var isReactionLanding = false
    /// The rating of the message the cell shows
    private var configuredFeedback: ApiAgentV2AnswerFeedback?
    /// The row's layer in the collection, and whether it shows an answer, which stands over the other rows there
    private var layoutZIndex = 0
    private var isAnswerRow = false {
        didSet { updateZPosition() }
    }
    /// The chosen reaction's flight to the corner
    private(set) weak var reactionFlight: AgentReactionFlight?
    /// The element VoiceOver reads the answer's reaction on, and the reaction it reads
    private weak var reactionAccessibilityElement: NSObject?
    private var appliedReactionAccessibilityValue: String?
    private var wasStreamingMessage = false
    /// The configured answer was written here in this session, rather than coming with the chat's history
    private var hasStreamedMessage = false
    /// The streaming answer's lines its closed tables and code took, which only grows while the answer streams
    private var streamingSettledLineCount = 0
    /// The settled lines the reveal view started its text after
    private var revealSettledLineCount = 0
    private var deferredShowsAction = false
    private var didShowDeferredAction = false
    private var deferredShowsSupplementaryError = false
    private var didShowDeferredSupplementaryError = false
    private var configuredControls: [AgentMessageControl] = []
    private var onControlTap: ((String) -> Void)?
    private var onURLTap: ((URL) -> Void)? {
        didSet { userMessageTextView.onURLTap = onURLTap }
    }
    private var lastAssistantConfiguration: AssistantConfiguration?
    private var lastAppliedRichContent: AppliedRichContent?
    private var lastAppliedSemanticContent: AppliedSemanticContent?
    private var lastAppliedTextLayoutMaxWidth: CGFloat = 0
    private var suppressesSizeCallbacks = false
    private lazy var longPressMenuInteraction = makeContextMenuInteraction()
    private lazy var menuAccessibilityAction = UIAccessibilityCustomAction(name: lang("More actions")) { [weak self] _ in
        guard let self, isMenuAvailable else { return false }
        longPressMenuInteraction.present()
        return true
    }
    /// An answer still being written has no menu and no reactions until it is complete
    private var isMenuAvailable = true {
        didSet {
            if isMenuAvailable != oldValue {
                setNeedsLayout()
            }
        }
    }

    private lazy var leadingConstraint = bubbleStackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset)
    private lazy var trailingConstraint = bubbleStackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -AgentMessageCellMetrics.horizontalInset)
    private lazy var outgoingLeadingLimitConstraint = bubbleStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.outgoingOppositeInset)
    private lazy var incomingTrailingLimitConstraint = bubbleStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.trailingAnchor, constant: -AgentMessageCellMetrics.incomingTrailingInset)
    private lazy var outgoingMaxWidthConstraint = bubbleStackView.widthAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.widthAnchor, multiplier: AgentMessageCellMetrics.outgoingMaxWidthMultiplier)
    private lazy var bubbleStackViewBottomConstraint = bubbleStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
    private lazy var bubbleTopConstraint = bubbleStackView.topAnchor.constraint(equalTo: contentView.topAnchor)
    private lazy var bubbleBelowAuthorConstraint = bubbleStackView.topAnchor.constraint(
        equalTo: authorView.bottomAnchor,
        constant: AgentMessageCellMetrics.authorSpacing
    )
    /// The bubble of an operator's reply has the green of support
    private var isOperatorBubble = false
    private lazy var bubbleMinimumWidthConstraint = bubbleView.widthAnchor.constraint(greaterThanOrEqualToConstant: AgentMessageCellMetrics.minimumBubbleWidth)
    private lazy var bubbleMinimumHeightConstraint = bubbleView.heightAnchor.constraint(greaterThanOrEqualToConstant: AgentMessageCellMetrics.minimumBubbleHeight)
    /// Holds a streaming answer's closed blocks at the text's full width, so the bubble keeps its width while the
    /// text after them starts revealing from its first letter. It outranks the reveal view's own width, which the
    /// bubble's stack would otherwise share with them.
    private lazy var assistantSettledBlocksWidthConstraint: NSLayoutConstraint = {
        let constraint = assistantRichMessageView.widthAnchor.constraint(equalToConstant: 1)
        constraint.priority = UILayoutPriority(999.5)
        return constraint
    }()
    private lazy var assistantSemanticContentWidthConstraint: NSLayoutConstraint = {
        let constraint = assistantSemanticContentView.widthAnchor.constraint(equalToConstant: 1)
        constraint.priority = UILayoutPriority(999)
        return constraint
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        with message: AgentMessage,
        onURLTap: @escaping (URL) -> Void,
        onControlTap: ((String) -> Void)? = nil
    ) {
        let isOutgoing = message.role == .user
        let messageIDChanged = configuredMessageID != message.id
        if messageIDChanged {
            isFeedbackHeld = false
            isReactionLanding = false
            wasStreamingMessage = false
            hasStreamedMessage = false
            streamingSettledLineCount = 0
            revealSettledLineCount = 0
            didShowDeferredAction = false
            didShowDeferredSupplementaryError = false
            lastAppliedRichContent = nil
            lastAppliedSemanticContent = nil
            lastAppliedTextLayoutMaxWidth = 0
        }
        let hasStreaming = message.role == .assistant && message.isStreaming
        isMenuAvailable = !hasStreaming
        let hasStructuredTable = message.answerBlocks?.contains(where: {
            if case .table = $0 { return true }
            return false
        }) == true
        if !hasStreaming, wasStreamingMessage, hasStructuredTable || isSettledTextBlank(message) {
            // Structured tables replace the reveal view immediately, as does the whole answer once nothing is left to
            // reveal after its closed blocks, so its completion callback cannot be responsible for releasing
            // follow-ups or trimming reserved scroll space.
            wasStreamingMessage = false
            assistantMessageTextView.prepareForReuse()
        }
        let hadStreaming = !messageIDChanged && wasStreamingMessage && !hasStreaming
        if hasStreaming {
            didShowDeferredSupplementaryError = false
        }

        let controls = message.controls
        let hasActionRows = !controls.isEmpty
        if !hasActionRows {
            didShowDeferredAction = false
        }
        deferredShowsAction = hasActionRows && !isOutgoing && !message.isStreaming
        configuredControls = controls
        let showsAction = hasActionRows
            && (didShowDeferredAction || (deferredShowsAction && !hasStreaming && !hadStreaming))
        let messageTextColor = isOutgoing ? tintColor.foregroundForTintedBackground : UIColor.label
        let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: isOutgoing)

        leadingConstraint.isActive = false
        trailingConstraint.isActive = false
        outgoingLeadingLimitConstraint.isActive = false
        incomingTrailingLimitConstraint.isActive = false
        outgoingMaxWidthConstraint.isActive = false
        if isOutgoing {
            NSLayoutConstraint.activate([trailingConstraint, outgoingLeadingLimitConstraint, outgoingMaxWidthConstraint])
        } else {
            NSLayoutConstraint.activate([leadingConstraint, incomingTrailingLimitConstraint])
        }

        configuredMessageID = message.id
        isAnswerRow = message.role == .assistant
        configureAuthor(of: message, isOutgoing: isOutgoing)
        configuredFeedback = message.role == .assistant ? message.feedback : nil
        if !isFeedbackHeld, !isReactionLanding {
            showFeedback(configuredFeedback)
        }
        // A streaming answer has its own id, so a test can wait for the answer to finish
        accessibilityIdentifier = isOutgoing
            ? "agent_message_user"
            : hasStreaming ? "agent_message_streaming" : "agent_message_assistant"
        self.onControlTap = controls.isEmpty ? nil : onControlTap
        self.onURLTap = !message.isPlainText && (message.renderingPolicy.allowsLinks || AgentTextLinks.containsLinks(message.text))
            ? onURLTap
            : nil

        let supplementaryErrorText = normalizedSupplementaryErrorText(from: message)
        deferredShowsSupplementaryError = supplementaryErrorText != nil
            && !isOutgoing
            && (hasStreaming || hadStreaming)
        if supplementaryErrorText == nil || isOutgoing {
            didShowDeferredSupplementaryError = false
        }
        configureSupplementaryError(
            supplementaryErrorText,
            isVisible: supplementaryErrorText != nil
                && !isOutgoing
                && (!deferredShowsSupplementaryError || didShowDeferredSupplementaryError)
        )

        userMessageTextView.isHidden = !isOutgoing
        if isOutgoing {
            assistantMessageTextView.isHidden = true
            assistantMessageTextView.isAccessibilityElement = false
            assistantMessageTextView.accessibilityIdentifier = nil
            assistantMessageTextView.accessibilityLabel = nil
            assistantRichMessageView.isHidden = true
            assistantSemanticContentView.isHidden = true
            assistantSemanticContentWidthConstraint.isActive = false
            assistantSettledBlocksWidthConstraint.isActive = false
            lastAssistantConfiguration = nil
            lastAppliedRichContent = nil
            lastAppliedSemanticContent = nil
        }

        userMessageTextView.setContentHuggingPriority(
            isOutgoing ? .required : .defaultLow,
            for: .horizontal
        )

        if isOutgoing {
            setUserMessageText(
                message.text,
                textColor: messageTextColor
            )
        } else {
            var configuration = AssistantConfiguration(
                message: message,
                textColor: messageTextColor,
                hasStreaming: hasStreaming,
                hadStreaming: hadStreaming,
                blocks: [],
                streamingText: message.text
            )
            if let answerBlocks = message.answerBlocks {
                configuration.blocks = Self.makeDisplayedBlocks(answerBlocks, of: message)
            } else if hasStreaming || hadStreaming {
                applyStreamingContent(to: &configuration)
            } else if let existing = lastAssistantConfiguration,
                      existing.message.id == message.id,
                      existing.message.text == message.text,
                      existing.message.answerBlocks == nil,
                      !existing.hasStreaming,
                      !existing.hadStreaming {
                configuration.blocks = existing.blocks
            } else {
                configuration.blocks = Self.makeDisplayedBlocks(AgentMessageBlockParser.parse(message.text), of: message)
            }
            lastAssistantConfiguration = configuration
            assistantMessageTextView.onURLTap = self.onURLTap
            assistantMessageTextView.onPreferredHeightChanged = { [weak self] animated in
                guard let self else { return }
                self.setNeedsLayout()
                self.contentView.layoutIfNeeded()
                self.bubbleView.setNeedsLayout()
                self.bubbleView.layoutIfNeeded()
                guard !self.suppressesSizeCallbacks else { return }
                if let collectionView = self.agentEnclosingCollectionView {
                    let visibleRect = collectionView.bounds.insetBy(dx: 0, dy: -64)
                    if !self.frame.intersects(visibleRect) {
                        return
                    }
                }
                self.onPreferredHeightChanged?(animated)
            }
            assistantMessageTextView.onRevealCompleted = { [weak self] in
                let switchedToFinalContent = self?.showFinalAssistantContentIfNeeded() == true
                let revealedSupplementaryError = self?.showDeferredSupplementaryErrorIfNeeded() == true
                self?.applyDeferredActionPresentation()
                if switchedToFinalContent || revealedSupplementaryError {
                    self?.onPreferredHeightChanged?(false)
                }
                self?.onStreamingRevealCompleted?()
            }
            withSizeCallbacksSuppressed {
                configureAssistantMessageContent(layoutMaxWidth: layoutMaxWidth)
            }
        }

        if hasStreaming {
            wasStreamingMessage = true
            hasStreamedMessage = true
        }
        let resolvedShowsAction = hasActionRows && (showsAction || didShowDeferredAction)
        // Suggestions come in only under an answer written in this session; those that come with the chat's history
        // show with it, as the history does
        applyActionPresentation(
            showsAction: resolvedShowsAction,
            controls: controls,
            isOutgoing: isOutgoing,
            showsTail: !resolvedShowsAction || !controls.contains { $0.kind == .action },
            animatesFollowups: !messageIDChanged && hasStreamedMessage,
            animatesTailBack: !messageIDChanged
        )
    }

    var messageID: AgentItemID? { configuredMessageID }
    var reactionBadgeView: AgentReactionBadgeView { bubbleStackView.reactionBadgeView }

    /// Keeps the corner's reaction while the menu that changes the rating closes, whatever ratings the message brings
    /// meanwhile
    func holdFeedback() {
        isFeedbackHeld = true
    }

    /// Flies `feedback`, chosen in the menu's cloud, from `source`, its icon there, to the bubble's corner on Telegram's
    /// path, where the corner's emoji takes it over in the frame it arrives and plays Telegram's landing, with the
    /// hit's haptic. `getFrameOnReplica` tells where a part of the bubble shows on the menu's replica of it while the
    /// menu has one. With Reduce Motion the corner's emoji fades in at once, with the hit's haptic, and off screen it
    /// changes without one. `onLanding` runs as the reaction lands: on the hit, or at once when nothing flies.
    func flyReaction(
        _ feedback: ApiAgentV2AnswerFeedback,
        from source: AgentReactionEmojiView?,
        getFrameOnReplica: (@MainActor (CGRect) -> CGRect?)? = nil,
        onLanding: (() -> Void)? = nil
    ) {
        guard !AgentReactionMotion.isReduced, let window, let source else {
            animateFeedback(feedback)
            if AgentReactionMotion.isReduced, window != nil {
                Haptics.play(.lightTap)
            }
            onLanding?()
            return
        }
        isReactionLanding = true
        let land = makeLanding(of: feedback)
        reactionFlight = AgentReactionFlight.start(
            feedback: feedback,
            in: window,
            from: source,
            at: makeBadgeIconFrameProvider(getFrameOnReplica: getFrameOnReplica),
            onArrival: {
                land()
                onLanding?()
            }
        )
    }

    /// What happens as a chosen reaction reaches the corner, while the cell shows the same message: the corner's emoji
    /// takes it over
    private func makeLanding(of feedback: ApiAgentV2AnswerFeedback) -> () -> Void {
        let messageID = messageID
        return { [weak self] in
            guard let self, self.messageID == messageID else { return }
            self.isReactionLanding = false
            self.reactionBadgeView.land(feedback)
            self.updateReactionAccessibility()
            self.updateHeldFeedback()
        }
    }

    /// Changes the corner's reaction to `feedback` in place, without a flight
    func animateFeedback(_ feedback: ApiAgentV2AnswerFeedback?) {
        reactionBadgeView.animate(to: feedback)
        updateReactionAccessibility()
    }

    /// Lets the message's ratings reach the corner again once the menu is gone
    func releaseFeedback() {
        isFeedbackHeld = false
        updateHeldFeedback()
    }

    /// Once nothing holds the corner's reaction, the corner takes the rating the message has by then, should the
    /// rating have failed meanwhile
    private func updateHeldFeedback() {
        guard !isFeedbackHeld, !isReactionLanding, reactionBadgeView.feedback != configuredFeedback else { return }
        animateFeedback(configuredFeedback)
    }

    /// Shows `feedback` at the corner at once
    private func showFeedback(_ feedback: ApiAgentV2AnswerFeedback?) {
        if reactionBadgeView.feedback != feedback || reactionBadgeView.isHidden != (feedback == nil) {
            reactionBadgeView.show(feedback)
        }
        updateReactionAccessibility()
    }

    /// VoiceOver reads the answer's reaction as the value of the bubble's first element, after its text
    private func updateReactionAccessibility() {
        let value = reactionBadgeView.feedback?.reactionStateTitle
        let element = value == nil ? nil : findFirstAccessibilityElement(in: contentStackView)
        if let previous = reactionAccessibilityElement, previous !== element || value == nil,
           previous.accessibilityValue == appliedReactionAccessibilityValue {
            previous.accessibilityValue = nil
        }
        reactionAccessibilityElement = element
        appliedReactionAccessibilityValue = element == nil ? nil : value
        if let element, element.accessibilityValue != value {
            element.accessibilityValue = value
        }
    }

    private func findFirstAccessibilityElement(in view: UIView) -> UIView? {
        guard !view.isHidden, !view.accessibilityElementsHidden else { return nil }
        if view.isAccessibilityElement {
            return view
        }
        return view.subviews.lazy.compactMap { self.findFirstAccessibilityElement(in: $0) }.first
    }

    func updateStreamingMessage(_ message: AgentMessage) {
        guard message.role == .assistant, message.isStreaming else { return }
        guard configuredMessageID == message.id, let existing = lastAssistantConfiguration else { return }

        var configuration = AssistantConfiguration(
            message: message,
            textColor: existing.textColor,
            hasStreaming: true,
            hadStreaming: false,
            blocks: [],
            streamingText: message.text
        )
        if message.answerBlocks == nil {
            applyStreamingContent(to: &configuration)
        }
        lastAssistantConfiguration = configuration
        configureAssistantMessageContent(layoutMaxWidth: currentTextLayoutMaxWidth(isOutgoing: false))
    }

    /// Puts a streaming answer's closed tables and code into `configuration`'s blocks and leaves the reveal view the
    /// text after them. They only grow while the answer streams; once it ends, the reveal finishes the text it has.
    private func applyStreamingContent(to configuration: inout AssistantConfiguration) {
        let message = configuration.message
        if configuration.hasStreaming {
            streamingSettledLineCount = max(
                streamingSettledLineCount,
                AgentMessageBlockParser.countSettledLines(in: message.text)
            )
        }
        guard streamingSettledLineCount > 0 else { return }
        let lines = message.text.components(separatedBy: "\n")
        let blocks = Self.makeDisplayedBlocks(
            AgentMessageBlockParser.parse(lines.prefix(streamingSettledLineCount).joined(separator: "\n")),
            of: message
        )
        guard blocks.contains(where: \.standsApart) else { return }
        configuration.blocks = blocks
        configuration.streamingText = lines.dropFirst(streamingSettledLineCount).joined(separator: "\n")
        configuration.settledLineCount = streamingSettledLineCount
    }

    /// Whether a streaming answer has nothing left to reveal after the closed tables and code it shows as blocks
    private func isSettledTextBlank(_ message: AgentMessage) -> Bool {
        guard let settledLineCount = lastAssistantConfiguration?.settledLineCount, settledLineCount > 0,
              message.answerBlocks == nil else { return false }
        return message.text.components(separatedBy: "\n").dropFirst(settledLineCount).allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuredMessageID = nil
        isFeedbackHeld = false
        isReactionLanding = false
        configuredFeedback = nil
        showFeedback(nil)
        wasStreamingMessage = false
        streamingSettledLineCount = 0
        revealSettledLineCount = 0
        deferredShowsAction = false
        didShowDeferredAction = false
        deferredShowsSupplementaryError = false
        didShowDeferredSupplementaryError = false
        configuredControls = []
        onControlTap = nil
        onURLTap = nil
        onPreferredHeightChanged = nil
        onStreamingRevealCompleted = nil
        minimumHeightProvider = nil
        contextMenuConfigurationProvider = nil
        userMessageTextView.layer.removeAllAnimations()
        userMessageTextView.attributedText = nil
        userMessageTextView.isSelectable = false
        userMessageTextView.isUserInteractionEnabled = false
        // A morph into the bubble, from the typing row or from a suggestion, ends with the message
        bubbleStackView.layer.removeAllAnimations()
        bubbleStackView.alpha = 1
        bubbleStackView.transform = .identity
        bubbleView.layer.mask = nil
        bubbleView.layer.removeAnimation(forKey: AgentTypingAnswerMorph.bubbleFadeKey)
        AgentBlurTransition.cancel(bubbleView.contentView.layer)
        assistantMessageTextView.prepareForReuse()
        assistantMessageTextView.isAccessibilityElement = false
        assistantMessageTextView.accessibilityIdentifier = nil
        assistantMessageTextView.accessibilityLabel = nil
        assistantRichMessageView.configure(
            blocks: [],
            textColor: .label,
            maximumContentWidth: 1,
            detectsLinks: false,
            markdownProfile: .legacy,
            onURLTap: nil
        )
        assistantRichMessageView.isHidden = true
        assistantSettledBlocksWidthConstraint.isActive = false
        assistantSemanticContentView.reset()
        assistantSemanticContentView.isHidden = true
        assistantSemanticContentWidthConstraint.isActive = false
        assistantSupplementaryErrorLabel.text = nil
        assistantSupplementaryErrorLabel.isHidden = true
        removeControlButtons()
        lastAssistantConfiguration = nil
        lastAppliedRichContent = nil
        lastAppliedSemanticContent = nil
        lastAppliedTextLayoutMaxWidth = 0
    }

    private func withSizeCallbacksSuppressed(_ body: () -> Void) {
        let previous = suppressesSizeCallbacks
        suppressesSizeCallbacks = true
        body()
        suppressesSizeCallbacks = previous
    }

    private var agentEnclosingCollectionView: UICollectionView? {
        var view: UIView? = superview
        while let current = view {
            if let collectionView = current as? UICollectionView {
                return collectionView
            }
            view = current.superview
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        offerMenuToAccessibility(in: bubbleStackView)
        updateReactionAccessibility()
        followupView.updateMaxWidth()
        guard userMessageTextView.isHidden, lastAssistantConfiguration != nil else { return }
        let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: false)
        guard abs(layoutMaxWidth - lastAppliedTextLayoutMaxWidth) > 0.5 else { return }
        lastAppliedTextLayoutMaxWidth = layoutMaxWidth
        withSizeCallbacksSuppressed {
            configureAssistantMessageContent(layoutMaxWidth: layoutMaxWidth)
        }
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        layoutZIndex = layoutAttributes.zIndex
        updateZPosition()
    }

    /// An answer's row stands over the other rows of its layer, so the reaction's emoji on its bubble's corner shows
    /// over the next row where it reaches into it
    private func updateZPosition() {
        layer.zPosition = CGFloat(layoutZIndex) + (isAnswerRow ? Self.answerZPositionLift : 0)
    }

    private static let answerZPositionLift: CGFloat = 0.5

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The collection fixes the row width. Fit its content at that width, not the previous
        // cell width or the compressed width returned by UIKit for a reused bubble.
        let targetWidth = layoutAttributes.size.width
        bounds.size.width = targetWidth
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size.width = targetWidth
        setNeedsLayout()
        layoutIfNeeded()
        if userMessageTextView.isHidden, lastAssistantConfiguration != nil {
            let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: false)
            if abs(layoutMaxWidth - lastAppliedTextLayoutMaxWidth) > 0.5 {
                withSizeCallbacksSuppressed {
                    configureAssistantMessageContent(layoutMaxWidth: layoutMaxWidth)
                }
                layoutIfNeeded()
            }
        }
        let targetSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let fittedSize = contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size.height = max(ceil(fittedSize.height), minimumHeightProvider?() ?? 0)
        return attributes
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false
        setupCenteredContentLayoutGuide(contentLayoutGuide)

        authorView.translatesAutoresizingMaskIntoConstraints = false
        authorView.isHidden = true
        contentView.addSubview(authorView)

        bubbleStackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStackView.axis = .vertical
        bubbleStackView.spacing = AgentMessageCellMetrics.bubbleToButtonSpacing
        bubbleStackView.alignment = .fill
        contentView.addSubview(bubbleStackView)

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStackView.addArrangedSubview(bubbleView)
        bubbleStackView.bubbleView = bubbleView
        bubbleStackView.addSubview(bubbleStackView.reactionBadgeView)
        // A tap on the reaction's emoji opens the answer's menu, as a long press on the bubble does
        bubbleStackView.reactionBadgeView.onTap = { [weak self] in
            guard let self, isMenuAvailable else { return }
            longPressMenuInteraction.present()
        }

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.spacing = 0
        contentStackView.alignment = .fill
        bubbleView.contentView.addSubview(contentStackView)

        actionBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStackView.addArrangedSubview(actionBackgroundView)
        actionBackgroundView.isHidden = true
        longPressMenuInteraction.attach(to: bubbleStackView)

        userMessageTextView.translatesAutoresizingMaskIntoConstraints = false
        userMessageTextView.backgroundColor = .clear
        userMessageTextView.font = AgentMessageTextRenderer.baseFont
        userMessageTextView.isEditable = false
        userMessageTextView.isScrollEnabled = false
        userMessageTextView.isSelectable = false
        userMessageTextView.isUserInteractionEnabled = false
        userMessageTextView.dataDetectorTypes = []
        userMessageTextView.textContainerInset = .zero
        userMessageTextView.textContainer.lineFragmentPadding = 0
        userMessageTextView.textContainer.maximumNumberOfLines = 0
        userMessageTextView.textContainer.lineBreakMode = .byWordWrapping
        userMessageTextView.textDragInteraction?.isEnabled = false
        userMessageTextView.delegate = self
        userMessageTextView.accessibilityIdentifier = "agent_message_text"
        userMessageTextView.setContentCompressionResistancePriority(.required, for: .vertical)
        userMessageTextView.setContentHuggingPriority(.required, for: .vertical)

        assistantMessageTextView.translatesAutoresizingMaskIntoConstraints = false
        assistantMessageTextView.isHidden = true
        assistantMessageTextView.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
        assistantMessageTextView.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)

        assistantRichMessageView.translatesAutoresizingMaskIntoConstraints = false
        assistantRichMessageView.isHidden = true
        assistantRichMessageView.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
        assistantRichMessageView.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)

        assistantSemanticContentView.translatesAutoresizingMaskIntoConstraints = false
        assistantSemanticContentView.isHidden = true
        assistantSemanticContentView.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
        assistantSemanticContentView.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)

        assistantSupplementaryErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        assistantSupplementaryErrorLabel.font = WTypography.uiFont(.footnote)
        assistantSupplementaryErrorLabel.textColor = UIColor.air.error
        assistantSupplementaryErrorLabel.numberOfLines = 0
        assistantSupplementaryErrorLabel.isHidden = true
        assistantSupplementaryErrorLabel.accessibilityIdentifier = "agent_message_error"
        assistantSupplementaryErrorLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        assistantSupplementaryErrorLabel.setContentHuggingPriority(.required, for: .vertical)
        // The error wraps only at the bubble's maximum width, widening the bubble past a shorter answer.
        assistantSupplementaryErrorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        actionStackView.translatesAutoresizingMaskIntoConstraints = false
        actionStackView.axis = .vertical
        actionStackView.alignment = .fill
        actionStackView.spacing = 0

        contentStackView.addArrangedSubview(userMessageTextView)
        // A streaming answer's closed tables and code stand above the text still arriving after them
        contentStackView.addArrangedSubview(assistantRichMessageView)
        contentStackView.addArrangedSubview(assistantMessageTextView)
        contentStackView.addArrangedSubview(assistantSemanticContentView)
        contentStackView.addArrangedSubview(assistantSupplementaryErrorLabel)
        contentStackView.setCustomSpacing(
            AgentMessageCellMetrics.supplementaryErrorSpacing,
            after: assistantMessageTextView
        )
        contentStackView.setCustomSpacing(
            AgentMessageCellMetrics.supplementaryErrorSpacing,
            after: assistantRichMessageView
        )
        contentStackView.setCustomSpacing(
            AgentMessageCellMetrics.supplementaryErrorSpacing,
            after: assistantSemanticContentView
        )

        actionBackgroundView.contentView.addSubview(actionStackView)

        followupConstraints = followupView.install(
            in: contentView,
            below: bubbleStackView,
            contentLayoutGuide: contentLayoutGuide
        )
        // The reaction's emoji on the bubble's corner shows over the suggestions under the bubble
        contentView.bringSubviewToFront(bubbleStackView)

        leadingConstraint.isActive = true
        incomingTrailingLimitConstraint.isActive = true

        NSLayoutConstraint.activate([
            bubbleTopConstraint,
            bubbleStackViewBottomConstraint,
            authorView.topAnchor.constraint(equalTo: contentView.topAnchor),
            authorView.leadingAnchor.constraint(
                equalTo: contentLayoutGuide.leadingAnchor,
                constant: AgentMessageCellMetrics.horizontalInset + AgentMessageCellMetrics.authorLeadingInset
            ),
            authorView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentMessageCellMetrics.horizontalInset
            ),
            bubbleMinimumWidthConstraint,
            bubbleMinimumHeightConstraint,

            contentStackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor, constant: AgentMessageCellMetrics.bodyVerticalPadding),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor, constant: AgentMessageCellMetrics.bodyHorizontalPadding),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor, constant: -AgentMessageCellMetrics.bodyHorizontalPadding),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor, constant: -AgentMessageCellMetrics.bodyVerticalPadding),

            actionStackView.topAnchor.constraint(equalTo: actionBackgroundView.contentView.topAnchor, constant: AgentMessageCellMetrics.actionContainerInsets.top),
            actionStackView.leadingAnchor.constraint(equalTo: actionBackgroundView.contentView.leadingAnchor, constant: AgentMessageCellMetrics.actionContainerInsets.left),
            actionStackView.trailingAnchor.constraint(equalTo: actionBackgroundView.contentView.trailingAnchor, constant: -AgentMessageCellMetrics.actionContainerInsets.right),
            actionStackView.bottomAnchor.constraint(equalTo: actionBackgroundView.contentView.bottomAnchor, constant: -AgentMessageCellMetrics.actionContainerInsets.bottom)
        ])
    }

    /// An answer shows its author over it in a chat an operator has joined, and an operator's reply has the green of
    /// support
    private func configureAuthor(of message: AgentMessage, isOutgoing: Bool) {
        if case .operator = message.author {
            isOperatorBubble = !isOutgoing
        } else {
            isOperatorBubble = false
        }
        let shouldShowAuthor = !isOutgoing && message.shouldShowAuthor
        authorView.isHidden = !shouldShowAuthor
        if shouldShowAuthor {
            authorView.configure(author: message.author)
            bubbleTopConstraint.isActive = false
            bubbleBelowAuthorConstraint.isActive = true
        } else {
            bubbleBelowAuthorConstraint.isActive = false
            bubbleTopConstraint.isActive = true
        }
    }

    private func renderedMessageText() -> String {
        if !assistantSemanticContentView.isHidden {
            return lastAssistantConfiguration?.message.text ?? ""
        }
        if !assistantRichMessageView.isHidden {
            return lastAssistantConfiguration.map { AgentTextLinks.copyText($0.message.text) }
                ?? assistantRichMessageView.displayText
        }
        if !assistantMessageTextView.isHidden {
            let hasAnswerLinks = lastAssistantConfiguration.map { AgentTextLinks.containsLinks($0.message.text) } ?? false
            return hasAnswerLinks ? assistantMessageTextView.copyText : assistantMessageTextView.displayText
        }
        return userMessageTextView.attributedText?.string ?? userMessageTextView.text ?? ""
    }

    private func normalizedSupplementaryErrorText(from message: AgentMessage) -> String? {
        let text = message.supplementaryErrorText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func configureSupplementaryError(_ text: String?, isVisible: Bool) {
        assistantSupplementaryErrorLabel.text = text
        assistantSupplementaryErrorLabel.isHidden = !isVisible
    }

    private func currentTextLayoutMaxWidth(isOutgoing: Bool) -> CGFloat {
        let layoutGuideWidth = contentLayoutGuide.layoutFrame.width
        let cellWidth = bounds.width
        let contentWidth: CGFloat
        if layoutGuideWidth >= 200 {
            contentWidth = layoutGuideWidth
        } else if cellWidth >= 200 {
            contentWidth = cellWidth
        } else {
            contentWidth = min(UIScreen.main.bounds.width, AgentContentLayout.maxContentWidth)
        }
        if isOutgoing { return Self.getOutgoingTextLayoutMaxWidth(contentWidth: contentWidth) }
        let bubbleWidth = contentWidth
            - AgentMessageCellMetrics.horizontalInset
            - AgentMessageCellMetrics.incomingTrailingInset
        return max(
            120,
            bubbleWidth - AgentMessageCellMetrics.bodyHorizontalPadding * 2
        )
    }

    private static func getOutgoingTextLayoutMaxWidth(contentWidth: CGFloat) -> CGFloat {
        let percentageCappedBubbleWidth = contentWidth * AgentMessageCellMetrics.outgoingMaxWidthMultiplier
        let marginCappedBubbleWidth = contentWidth
            - AgentMessageCellMetrics.horizontalInset
            - AgentMessageCellMetrics.outgoingOppositeInset
        let bubbleWidth = min(percentageCappedBubbleWidth, marginCappedBubbleWidth)
        return max(120, bubbleWidth - AgentMessageCellMetrics.bodyHorizontalPadding * 2)
    }

    /// The lines `text` takes in a question's bubble in a chat `chatWidth` wide, as the cell lays it out
    static func countQuestionLines(_ text: String, chatWidth: CGFloat) -> Int {
        let attributedText = AgentMessageTextRenderer.makeAttributedText(
            text,
            textColor: .white,
            rendersMarkdown: false,
            detectsLinks: false
        )
        guard attributedText.length > 0 else { return 0 }
        let contentWidth = min(chatWidth, AgentContentLayout.maxContentWidth)
        let textContainer = NSTextContainer(size: CGSize(
            width: getOutgoingTextLayoutMaxWidth(contentWidth: contentWidth),
            height: .greatestFiniteMagnitude
        ))
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage(attributedString: attributedText)
        textStorage.addLayoutManager(layoutManager)
        var lineCount = 0
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            lineCount += 1
        }
        return lineCount
    }

    private func configureAssistantMessageContent(layoutMaxWidth: CGFloat) {
        guard let configuration = lastAssistantConfiguration else { return }
        lastAppliedTextLayoutMaxWidth = layoutMaxWidth
        assistantSupplementaryErrorLabel.preferredMaxLayoutWidth = layoutMaxWidth
        if let semanticContent = configuration.message.semanticContent,
           !configuration.hasStreaming,
           !configuration.hadStreaming {
            assistantMessageTextView.isHidden = true
            assistantMessageTextView.isAccessibilityElement = false
            assistantMessageTextView.accessibilityIdentifier = nil
            assistantMessageTextView.accessibilityLabel = nil
            assistantRichMessageView.isHidden = true
            assistantSettledBlocksWidthConstraint.isActive = false
            assistantSemanticContentView.isHidden = false
            assistantSemanticContentWidthConstraint.constant = layoutMaxWidth
            assistantSemanticContentWidthConstraint.isActive = true
            lastAppliedRichContent = nil

            let appliedContent = AppliedSemanticContent(
                messageID: configuration.message.id,
                content: semanticContent,
                localeIdentifier: supportedMessageLanguageCode(configuration.message.responseLanguage)
                    ?? LocalizationSupport.shared.locale.identifier
            )
            if let previous = lastAppliedSemanticContent,
               previous.messageID == appliedContent.messageID,
               previous.content == appliedContent.content,
               previous.localeIdentifier == appliedContent.localeIdentifier {
                return
            }
            assistantSemanticContentView.configure(
                content: semanticContent,
                responseLanguage: configuration.message.responseLanguage
            )
            lastAppliedSemanticContent = appliedContent
            return
        }

        assistantSemanticContentView.isHidden = true
        assistantSemanticContentWidthConstraint.isActive = false
        lastAppliedSemanticContent = nil
        // An answer that failed before any text shows only its error.
        if configuration.message.text.isEmpty,
           !configuration.hasStreaming,
           !configuration.hadStreaming,
           normalizedSupplementaryErrorText(from: configuration.message) != nil {
            assistantMessageTextView.isHidden = true
            assistantMessageTextView.isAccessibilityElement = false
            assistantMessageTextView.accessibilityIdentifier = nil
            assistantMessageTextView.accessibilityLabel = nil
            assistantRichMessageView.isHidden = true
            assistantSettledBlocksWidthConstraint.isActive = false
            lastAppliedRichContent = nil
            return
        }
        let isRevealing = configuration.hasStreaming || configuration.hadStreaming
        let showsRichContent = configuration.blocks.contains(where: \.standsApart)
            && (configuration.message.answerBlocks != nil || !isRevealing)
        let showsSettledBlocks = !showsRichContent && configuration.settledLineCount > 0
        assistantMessageTextView.isHidden = showsRichContent
        assistantRichMessageView.isHidden = !showsRichContent && !showsSettledBlocks
        assistantSettledBlocksWidthConstraint.constant = layoutMaxWidth
        assistantSettledBlocksWidthConstraint.isActive = showsSettledBlocks

        if showsRichContent || showsSettledBlocks {
            // Closed blocks above the text still arriving have no marker waiting for its text
            applyRichContent(
                configuration,
                layoutMaxWidth: layoutMaxWidth,
                isStreaming: showsRichContent && configuration.hasStreaming
            )
        } else {
            lastAppliedRichContent = nil
        }
        if showsRichContent {
            assistantMessageTextView.isAccessibilityElement = false
            assistantMessageTextView.accessibilityIdentifier = nil
            assistantMessageTextView.accessibilityLabel = nil
            return
        }
        if configuration.hasStreaming, configuration.settledLineCount != revealSettledLineCount {
            revealSettledLineCount = configuration.settledLineCount
            assistantMessageTextView.startOver()
        }
        assistantMessageTextView.configure(
            text: configuration.streamingText,
            textColor: configuration.textColor,
            isStreaming: configuration.hasStreaming,
            hadStreaming: configuration.hadStreaming,
            rendersMarkdown: !configuration.message.isPlainText,
            markdownProfile: configuration.message.isPlainText ? .plainText : configuration.message.renderingPolicy.markdownProfile,
            allowsLinks: configuration.message.renderingPolicy.allowsLinks,
            layoutMaxWidth: layoutMaxWidth,
            streamingIdentity: configuration.message.id.uuidString
        )
        assistantMessageTextView.isAccessibilityElement = !configuration.message.text.isEmpty
        assistantMessageTextView.accessibilityIdentifier = configuration.message.renderingPolicy == .agentV2Safe
            ? "agent_message_text"
            : nil
        assistantMessageTextView.accessibilityLabel = assistantMessageTextView.displayText
    }

    private func applyRichContent(
        _ configuration: AssistantConfiguration,
        layoutMaxWidth: CGFloat,
        isStreaming: Bool
    ) {
        let appliedContent = AppliedRichContent(
            messageID: configuration.message.id,
            blocks: configuration.blocks,
            layoutMaxWidth: layoutMaxWidth,
            renderingPolicy: configuration.message.renderingPolicy,
            isStreaming: isStreaming
        )
        if let previous = lastAppliedRichContent,
           previous.messageID == appliedContent.messageID,
           previous.blocks == appliedContent.blocks,
           previous.renderingPolicy == appliedContent.renderingPolicy,
           previous.isStreaming == appliedContent.isStreaming,
           abs(previous.layoutMaxWidth - appliedContent.layoutMaxWidth) <= 0.5 {
            return
        }
        assistantRichMessageView.configure(
            blocks: configuration.blocks,
            textColor: configuration.textColor,
            maximumContentWidth: layoutMaxWidth,
            detectsLinks: configuration.message.renderingPolicy.allowsLinks,
            markdownProfile: configuration.message.renderingPolicy.markdownProfile,
            isStreaming: isStreaming,
            onURLTap: onURLTap
        )
        lastAppliedRichContent = appliedContent
    }

    private func showFinalAssistantContentIfNeeded() -> Bool {
        guard var configuration = lastAssistantConfiguration else { return false }
        configuration.hasStreaming = false
        configuration.hadStreaming = false
        configuration.blocks = Self.makeDisplayedBlocks(
            configuration.message.answerBlocks ?? AgentMessageBlockParser.parse(configuration.message.text),
            of: configuration.message
        )
        configuration.streamingText = configuration.message.text
        configuration.settledLineCount = 0
        lastAssistantConfiguration = configuration
        wasStreamingMessage = false
        streamingSettledLineCount = 0
        let hasFinalContent = configuration.message.semanticContent != nil
            || configuration.blocks.contains(where: \.standsApart)
        guard hasFinalContent else { return false }
        configureAssistantMessageContent(layoutMaxWidth: currentTextLayoutMaxWidth(isOutgoing: false))
        setNeedsLayout()
        return true
    }

    /// An answer's code blocks stand apart from its text, as its tables do
    private static func makeDisplayedBlocks(_ blocks: [AgentMessageBlock], of message: AgentMessage) -> [AgentMessageBlock] {
        if message.isPlainText { return [.text(message.text)] }
        return message.renderingPolicy.markdownProfile == .agentMarkdownV1 ? AgentMessageBlockParser.separatingCode(blocks) : blocks
    }

    private func showDeferredSupplementaryErrorIfNeeded() -> Bool {
        guard deferredShowsSupplementaryError,
              let configuration = lastAssistantConfiguration,
              let text = normalizedSupplementaryErrorText(from: configuration.message) else {
            return false
        }
        deferredShowsSupplementaryError = false
        didShowDeferredSupplementaryError = true
        configureSupplementaryError(text, isVisible: true)
        setNeedsLayout()
        return true
    }

    private func applyDeferredActionPresentation() {
        guard deferredShowsAction else { return }
        didShowDeferredAction = true
        applyActionPresentation(
            showsAction: true,
            controls: configuredControls,
            isOutgoing: false,
            showsTail: false,
            animatesFollowups: true,
            animatesTailBack: true
        )
        onPreferredHeightChanged?(false)
    }

    private func applyActionPresentation(
        showsAction: Bool,
        controls: [AgentMessageControl],
        isOutgoing: Bool,
        showsTail: Bool,
        animatesFollowups: Bool,
        animatesTailBack: Bool
    ) {
        let showsActionRows = showsAction && controls.contains { $0.kind == .action }
        let showsFollowups = showsAction && controls.contains { $0.kind == .followup }
        actionBackgroundView.isHidden = !showsActionRows
        bubbleStackViewBottomConstraint.isActive = !showsFollowups
        if showsFollowups {
            NSLayoutConstraint.activate(followupConstraints)
        } else {
            NSLayoutConstraint.deactivate(followupConstraints)
        }
        bubbleStackViewBottomConstraint.constant = showsActionRows
            ? -AgentMessageCellMetrics.actionBottomSpacing
            : 0
        configureActionRows(controls)
        followupView.configure(
            controls: controls,
            isVisible: showsFollowups,
            animatesAppearance: animatesFollowups,
            onControlTap: onControlTap
        )

        // An answer with suggestions under it has no tail: the suggestions hang from it. The tail goes into its corner
        // as they come in, in step with them, and comes back out of it as they go, under an answer of the chat's
        // history as well.
        let showsBubbleTail = !showsActionRows && !showsFollowups && showsTail
        let animatesTail = showsBubbleTail ? animatesTailBack : animatesFollowups
        bubbleView.configure(
            direction: isOutgoing ? .outgoing : .incoming,
            fillColor: isOutgoing ? .tintColor : isOperatorBubble ? AgentSupportColors.operatorBubbleFill : UIColor.air.agentBubbleFill,
            usesTintColor: isOutgoing,
            showsTail: showsBubbleTail,
            cornerRadii: showsActionRows ? .topActioned : .standAlone,
            shouldAnimateTail: animatesTail && window != nil
        )

        actionBackgroundView.configure(
            direction: .incoming,
            fillColor: .tintColor.withAlphaComponent(0.10),
            usesTintColor: true,
            showsTail: false,
            cornerRadii: .bottomAction
        )
    }

    private func configureActionRows(_ controls: [AgentMessageControl]) {
        let controls = controls.filter { $0.kind == .action }
        for button in controlButtonsByID.values {
            actionStackView.removeArrangedSubview(button)
        }

        let controlIDs = Set(controls.map(\.id))
        let removedControlIDs = controlButtonsByID.keys.filter { !controlIDs.contains($0) }
        for id in removedControlIDs {
            controlButtonsByID.removeValue(forKey: id)?.removeFromSuperview()
        }

        for control in controls {
            let button: UIButton
            if let existingButton = controlButtonsByID[control.id] {
                button = existingButton
            } else {
                button = makeControlButton(control)
                controlButtonsByID[control.id] = button
            }
            configureActionButton(button, title: control.title, isEnabled: control.isEnabled)
            actionStackView.addArrangedSubview(button)
        }
    }

    private func makeControlButton(_ control: AgentMessageControl) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = control.id == "retry-limit" ? "agent_retry" : "agent_action_button"
        button.addAction(UIAction { [weak self] _ in
            self?.onControlTap?(control.id)
        }, for: .touchUpInside)
        return button
    }

    private func configureActionButton(
        _ button: UIButton,
        title: String?,
        isEnabled: Bool
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = AgentMessageCellMetrics.actionOuterPadding
        configuration.title = title
        configuration.baseForegroundColor = .tintColor
        configuration.background = .clear()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WTypography.uiFont(.calloutEmphasized)
            return outgoing
        }
        button.configuration = configuration
        button.tintAdjustmentMode = .normal
        button.isEnabled = isEnabled
        button.accessibilityLabel = title
    }

    private func removeControlButtons() {
        for button in controlButtonsByID.values {
            actionStackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        controlButtonsByID.removeAll()
        followupView.reset()
    }

    private func setUserMessageText(_ text: String, textColor: UIColor) {
        let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: true)
        let resolvedTextColor = textColor.resolvedColor(with: traitCollection)
        let attributedText = NSMutableAttributedString(
            attributedString: AgentMessageTextRenderer.makeAttributedText(
                text,
                textColor: resolvedTextColor,
                rendersMarkdown: false,
                detectsLinks: false
            )
        )
        let naturalWidth = ceil(Self.measureTextWidth(attributedText, maxWidth: layoutMaxWidth))
        let minContentWidth = AgentMessageCellMetrics.minimumBubbleWidth
            - AgentMessageCellMetrics.bodyHorizontalPadding * 2
        let alignment: NSTextAlignment = naturalWidth + 0.5 < minContentWidth ? .center : .natural
        Self.applyTextAlignment(alignment, to: attributedText)
        userMessageTextView.textAlignment = alignment
        userMessageTextView.attributedText = attributedText
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateUserMessageColor()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateUserMessageColor()
    }

    private func updateUserMessageColor() {
        guard !userMessageTextView.isHidden,
              let text = userMessageTextView.attributedText?.string ?? userMessageTextView.text,
              !text.isEmpty else { return }
        setUserMessageText(text, textColor: tintColor.foregroundForTintedBackground)
    }

    private static func measureTextWidth(_ attributedText: NSAttributedString, maxWidth: CGFloat) -> CGFloat {
        guard attributedText.length > 0 else { return 0 }
        let rect = attributedText.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return rect.width
    }

    private static func applyTextAlignment(_ alignment: NSTextAlignment, to attributedText: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedText.length)
        guard fullRange.length > 0 else { return }
        attributedText.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let paragraphStyle = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
    }

    var contextMenuCopyText: String? {
        // An operator's reply is copied as they wrote it
        if let message = lastAssistantConfiguration?.message, message.isPlainText {
            return message.text.isEmpty ? nil : message.text
        }
        var parts: [String] = []
        let text = renderedMessageText()
        if !text.isEmpty {
            parts.append(text)
        }
        if let message = lastAssistantConfiguration?.message,
           let supplementaryErrorText = normalizedSupplementaryErrorText(from: message) {
            parts.append(supplementaryErrorText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// The message's menu opens on a long press only, as a news post's does. As in Telegram, the bubble squeezes in
    /// as the press builds up to the menu.
    private func makeContextMenuInteraction() -> ContextMenuInteraction {
        ContextMenuInteraction(
            triggers: .longPress,
            sourcePortal: ContextMenuSourcePortal(
                mask: .customAttachmentPath { [weak self] attachmentRect in
                    self?.bubblePath(in: attachmentRect) ?? CGPath(rect: attachmentRect, transform: nil)
                }
            ),
            pressAnimation: .default(transformMode: .sublayerTransform),
            activationHitTestProvider: { [weak self] sourceView, point in
                self?.canOpenMenu(at: point, in: sourceView) == true
            }
        ) { [weak self] _ in
            self?.contextMenuConfigurationProvider?()
        }
    }

    /// Where the corner's emoji shows on screen while the cell shows the same message: on the menu's replica of the
    /// bubble, through `getFrameOnReplica`, while the menu has one, and in the bubble once the menu is gone
    private func makeBadgeIconFrameProvider(getFrameOnReplica: (@MainActor (CGRect) -> CGRect?)? = nil) -> () -> CGRect? {
        let messageID = messageID
        return { [weak self] in
            guard let self, self.messageID == messageID else { return nil }
            let badge = self.reactionBadgeView
            return getFrameOnReplica?(badge.frame) ?? badge.presentedIconFrameInWindow
        }
    }

    /// A touch on a link keeps the link's own action, while a long press on a control in the bubble opens the menu. Link
    /// views take touches on links only.
    private func canOpenMenu(at point: CGPoint, in sourceView: UIView) -> Bool {
        guard isMenuAvailable else { return false }
        var view = sourceView.hitTest(point, with: nil)
        while let currentView = view, currentView !== sourceView {
            if currentView is UITextView || currentView is AgentStreamingTextView {
                return false
            }
            view = currentView.superview
        }
        return true
    }

    /// VoiceOver finds the message's menu as an action on every element in the bubble (text, tables, semantic content
    /// and action rows), as it did on the system context menu, while the message has one. Layout reaches the views rich
    /// content adds later.
    private func offerMenuToAccessibility(in view: UIView) {
        let actions = view.accessibilityCustomActions ?? []
        let hasMenuAction = actions.contains { $0 === menuAccessibilityAction }
        if isMenuAvailable, !hasMenuAction {
            view.accessibilityCustomActions = actions + [menuAccessibilityAction]
        } else if !isMenuAvailable, hasMenuAction {
            let remainingActions = actions.filter { $0 !== menuAccessibilityAction }
            view.accessibilityCustomActions = remainingActions.isEmpty ? nil : remainingActions
        }
        for subview in view.subviews {
            offerMenuToAccessibility(in: subview)
        }
    }

    /// The bubble with its action rows, in the coordinates of `attachmentRect`, which frames `bubbleStackView`
    private func bubblePath(in attachmentRect: CGRect) -> CGPath {
        bubbleStackView.layoutIfNeeded()

        let path = UIBezierPath()
        path.append(previewPath(for: bubbleView))
        if !actionBackgroundView.isHidden {
            path.append(previewPath(for: actionBackgroundView))
        }
        path.apply(CGAffineTransform(translationX: attachmentRect.minX, y: attachmentRect.minY))
        // The lifted answer keeps its reaction's emoji on its corner, and the square it plays its landing in, where a
        // reaction chosen in the menu lands
        let badge = bubbleStackView.reactionBadgeView
        let emojiInset = (badge.iconView.boxSize - AgentReactionBadgeView.Metrics.iconSize) / 2
        let emojiBox = badge.frame
            .insetBy(dx: -emojiInset, dy: -emojiInset)
            .offsetBy(dx: attachmentRect.minX, dy: attachmentRect.minY)
        return path.cgPath.union(CGPath(rect: emojiBox, transform: nil))
    }

    private func previewPath(for backgroundView: AgentBubbleBackgroundView) -> UIBezierPath {
        let path = backgroundView.previewPath()
        path.apply(
            CGAffineTransform(
                translationX: backgroundView.frame.minX,
                y: backgroundView.frame.minY
            )
        )
        return path
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard interaction == .invokeDefaultAction else { return false }
        onURLTap?(url)
        return false
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
        onURLTap?(url)
        return false
    }
}

final class AgentSystemMessageCell: UICollectionViewCell, AgentContextMenuPresentingCell, UITextViewDelegate {
    /// A failure's caption, as the design's "Network Error" frame shows it under the last message: 12 pt below the row's
    /// top, on 16 pt lines
    private enum CaptionMetrics {
        static let topInset: CGFloat = 12
        static let lineHeight: CGFloat = 16
    }

    /// A line about the chat's handover to support: a rounded gray pill in the middle of the chat, as in Classic
    private enum EventMetrics {
        static let verticalInset: CGFloat = 4
        static let sideInset: CGFloat = 24
        static let padding = UIEdgeInsets(top: 7, left: 13, bottom: 7, right: 13)
        static let cornerRadius: CGFloat = 14
        static let iconSize: CGFloat = 15
        static let spacing: CGFloat = 8
    }

    /// Builds the row's menu when a long press opens it
    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)?

    private let contentLayoutGuide = UILayoutGuide()
    private let label = UILabel()
    /// Shows a failure, with its controls as links after the text
    private let captionTextView = AgentMessageTextView()
    /// Shows a News day as Telegram's date bubble
    private let dayCapsule = AgentDateCapsuleView()
    private lazy var bottomConstraint = label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    private lazy var captionBottomConstraint = captionTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    private let eventView = UIView()
    private let eventIconView = UIImageView(image: AgentSupportIcon.makeImage(size: EventMetrics.iconSize))
    private let eventLabel = UILabel()
    private let eventTimeLabel = UILabel()
    private lazy var eventBottomConstraint = eventView.bottomAnchor.constraint(
        equalTo: contentView.bottomAnchor,
        constant: -EventMetrics.verticalInset
    )
    private lazy var dayCapsuleBottomConstraint = dayCapsule.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    private var configuredMessage: AgentMessage?
    private var onControlTap: ((String) -> Void)?
    private lazy var contextMenuInteraction = ContextMenuInteraction(
        triggers: .longPress,
        sourcePortal: ContextMenuSourcePortal(
            mask: .customAttachmentPath { [weak self] attachmentRect in
                self?.labelPath(in: attachmentRect) ?? CGPath(rect: attachmentRect, transform: nil)
            }
        )
    ) { [weak self] _ in
        self?.contextMenuConfigurationProvider?()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: AgentMessage, onControlTap: ((String) -> Void)? = nil) {
        configuredMessage = message
        self.onControlTap = onControlTap
        let isFailure = message.isFailureCaption
        let isEvent = message.supportEvent != nil && !isFailure
        let isDay = message.isDayCapsule
        label.isHidden = isFailure || isEvent || isDay
        captionTextView.isHidden = !isFailure
        eventView.isHidden = !isEvent
        dayCapsule.isHidden = !isDay
        NSLayoutConstraint.deactivate([
            bottomConstraint,
            captionBottomConstraint,
            eventBottomConstraint,
            dayCapsuleBottomConstraint,
        ])
        if isFailure {
            captionBottomConstraint.isActive = true
        } else if isEvent {
            eventBottomConstraint.isActive = true
        } else if isDay {
            dayCapsuleBottomConstraint.isActive = true
        } else {
            bottomConstraint.isActive = true
        }
        applyText(for: message)
    }

    /// Hides the day's capsule while the News feed shows it stuck under its header
    func setDayCapsuleHidden(_ isHidden: Bool) {
        dayCapsule.alpha = isHidden ? 0 : 1
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
              let configuredMessage else { return }
        applyText(for: configuredMessage)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuredMessage = nil
        contextMenuConfigurationProvider = nil
        onControlTap = nil
        label.attributedText = nil
        eventLabel.text = nil
        eventTimeLabel.text = nil
        captionTextView.attributedText = nil
        captionTextView.accessibilityCustomActions = nil
        dayCapsule.text = nil
        setDayCapsuleHidden(false)
    }

    var contextMenuCopyText: String? {
        let text: String
        if configuredMessage?.isFailureCaption == true || configuredMessage?.supportEvent != nil {
            text = configuredMessage?.text ?? ""
        } else if configuredMessage?.isDayCapsule == true {
            text = dayCapsule.text ?? ""
        } else {
            text = label.attributedText?.string ?? label.text ?? ""
        }
        return text.isEmpty ? nil : text
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if interaction == .invokeDefaultAction {
            performControl(linkedBy: url)
        }
        return false
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
        performControl(linkedBy: url)
        return false
    }

    /// A tap on a control's link performs the control
    private func performControl(linkedBy url: URL) {
        guard url.scheme == Self.controlLinkScheme else { return }
        onControlTap?(String(url.absoluteString.dropFirst(Self.controlLinkScheme.count + 1)))
    }

    private func applyText(for message: AgentMessage) {
        if message.supportEvent != nil, !message.isFailureCaption {
            eventLabel.text = message.text
            eventTimeLabel.text = AgentModel.formatChatDate(for: message.timestamp).time
            eventView.accessibilityLabel = [message.text, eventTimeLabel.text ?? ""].joined(separator: ", ")
            return
        }
        if message.isDayCapsule {
            dayCapsule.text = message.text
            return
        }
        guard message.isFailureCaption else {
            label.attributedText = makeAttributedText(for: message)
            label.accessibilityTraits = message.isDateLine ? [.staticText, .header] : .staticText
            return
        }
        captionTextView.attributedText = makeCaptionText(for: message)
        captionTextView.isSelectable = message.controls.contains { $0.isEnabled }
        captionTextView.accessibilityLabel = message.text
        captionTextView.accessibilityCustomActions = message.controls.filter(\.isEnabled).map { control in
            UIAccessibilityCustomAction(name: control.title) { [weak self] _ in
                self?.onControlTap?(control.id)
                return true
            }
        }
    }

    /// The failure's text in the date line's style, centred, and the controls it can perform now as accent links after
    /// it. A retry that a limit holds back doesn't show until the limit resets.
    private func makeCaptionText(for message: AgentMessage) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = CaptionMetrics.lineHeight
        paragraph.maximumLineHeight = CaptionMetrics.lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WTypography.uiFont(.caption2Emphasized),
            .foregroundColor: UIColor.air.secondaryLabel.resolvedColor(with: traitCollection),
            .paragraphStyle: paragraph
        ]
        let text = NSMutableAttributedString(string: message.text, attributes: attributes)
        for control in message.controls where control.isEnabled {
            guard let url = URL(string: "\(Self.controlLinkScheme):\(control.id)") else { continue }
            var controlAttributes = attributes
            controlAttributes[.link] = url
            text.append(NSAttributedString(string: " ", attributes: attributes))
            text.append(NSAttributedString(string: control.title, attributes: controlAttributes))
        }
        return text
    }

    private static let controlLinkScheme = "agent-control"

    /// The rounded label, or the day's capsule, in the coordinates of `attachmentRect`, which frames `contentView`
    private func labelPath(in attachmentRect: CGRect) -> CGPath {
        contentView.layoutIfNeeded()

        if !eventView.isHidden {
            return UIBezierPath(
                roundedRect: eventView.frame.offsetBy(dx: attachmentRect.minX, dy: attachmentRect.minY),
                cornerRadius: EventMetrics.cornerRadius
            ).cgPath
        }
        if configuredMessage?.isDayCapsule == true {
            let capsuleRect = dayCapsule.frame.offsetBy(dx: attachmentRect.minX, dy: attachmentRect.minY)
            return UIBezierPath(roundedRect: capsuleRect, cornerRadius: capsuleRect.height / 2).cgPath
        }
        let previewRect = label.frame.inset(
            by: UIEdgeInsets(
                top: -AgentMessageCellMetrics.systemPreviewInsets.top,
                left: -AgentMessageCellMetrics.systemPreviewInsets.left,
                bottom: -AgentMessageCellMetrics.systemPreviewInsets.bottom,
                right: -AgentMessageCellMetrics.systemPreviewInsets.right
            )
        ).offsetBy(dx: attachmentRect.minX, dy: attachmentRect.minY)
        return UIBezierPath(
            roundedRect: previewRect,
            cornerRadius: AgentMessageCellMetrics.systemPreviewCornerRadius
        ).cgPath
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetWidth = attributes.size.width
        bounds.size.width = targetWidth
        setNeedsLayout()
        layoutIfNeeded()
        let targetSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let fittedSize = contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size.height = ceil(fittedSize.height)
        return attributes
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setupCenteredContentLayoutGuide(contentLayoutGuide)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.applyTextStyle(.caption2Emphasized)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "agent_message_system"
        contentView.addSubview(label)

        captionTextView.translatesAutoresizingMaskIntoConstraints = false
        captionTextView.backgroundColor = .clear
        captionTextView.isEditable = false
        captionTextView.isScrollEnabled = false
        captionTextView.isSelectable = false
        captionTextView.textContainerInset = .zero
        captionTextView.textContainer.lineFragmentPadding = 0
        captionTextView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        captionTextView.textDragInteraction?.isEnabled = false
        captionTextView.delegate = self
        captionTextView.isHidden = true
        captionTextView.accessibilityIdentifier = "agent_message_failure"
        contentView.addSubview(captionTextView)
        setupEventView()
        dayCapsule.isHidden = true
        contentView.addSubview(dayCapsule)
        contextMenuInteraction.attach(to: contentView)
        // VoiceOver finds the row's menu as an action on its text, as it did on the system context menu
        let moreActions = UIAccessibilityCustomAction(name: lang("More actions")) { [weak self] _ in
            guard let self else { return false }
            contextMenuInteraction.present()
            return true
        }
        label.accessibilityCustomActions = [moreActions]
        eventView.accessibilityCustomActions = [moreActions]
        dayCapsule.label.accessibilityCustomActions = [moreActions]

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            bottomConstraint,
            label.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -40),
            captionTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: CaptionMetrics.topInset),
            captionTextView.leadingAnchor.constraint(
                equalTo: contentLayoutGuide.leadingAnchor,
                constant: AgentMessageCellMetrics.horizontalInset
            ),
            captionTextView.trailingAnchor.constraint(
                equalTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentMessageCellMetrics.horizontalInset
            ),
            dayCapsule.topAnchor.constraint(equalTo: contentView.topAnchor),
            dayCapsule.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            dayCapsule.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor,
                constant: AgentDateCapsuleView.minimumColumnInset
            ),
        ])
    }

    private func setupEventView() {
        eventView.translatesAutoresizingMaskIntoConstraints = false
        eventView.backgroundColor = .air.agentHintBackground
        eventView.layer.cornerRadius = EventMetrics.cornerRadius
        eventView.layer.cornerCurve = .continuous
        eventView.isHidden = true
        eventView.isAccessibilityElement = true
        eventView.accessibilityTraits = .staticText
        eventView.accessibilityIdentifier = "agent_message_support_event"
        contentView.addSubview(eventView)

        eventIconView.tintColor = .tintColor
        eventIconView.setContentHuggingPriority(.required, for: .horizontal)
        eventLabel.font = WTypography.uiFont(.caption2Emphasized)
        eventLabel.textColor = .air.secondaryLabel
        eventLabel.numberOfLines = 0
        eventLabel.textAlignment = .center
        eventTimeLabel.font = WTypography.uiFont(.caption2, content: .technical)
        eventTimeLabel.textColor = .air.secondaryLabel
        eventTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        eventTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stackView = UIStackView(arrangedSubviews: [eventIconView, eventLabel, eventTimeLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = EventMetrics.spacing
        eventView.addSubview(stackView)

        let padding = EventMetrics.padding
        NSLayoutConstraint.activate([
            eventView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: EventMetrics.verticalInset),
            eventView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            eventView.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor,
                constant: EventMetrics.sideInset
            ),
            eventView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentLayoutGuide.trailingAnchor,
                constant: -EventMetrics.sideInset
            ),
            stackView.topAnchor.constraint(equalTo: eventView.topAnchor, constant: padding.top),
            stackView.bottomAnchor.constraint(equalTo: eventView.bottomAnchor, constant: -padding.bottom),
            stackView.leadingAnchor.constraint(equalTo: eventView.leadingAnchor, constant: padding.left),
            stackView.trailingAnchor.constraint(equalTo: eventView.trailingAnchor, constant: -padding.right),
            eventIconView.widthAnchor.constraint(equalToConstant: EventMetrics.iconSize),
            eventIconView.heightAnchor.constraint(equalToConstant: EventMetrics.iconSize),
        ])
    }

    private func makeAttributedText(for message: AgentMessage) -> NSAttributedString {
        // Dates read in the text's own colour on every platform and theme
        let textColor = (message.isDateLine ? UIColor.label : UIColor.air.secondaryLabel)
            .resolvedColor(with: traitCollection)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WTypography.uiFont(.caption2Emphasized),
            .foregroundColor: textColor
        ]

        guard case .dateTime(let date, let time)? = message.systemStyle else {
            return NSAttributedString(string: message.text, attributes: attributes)
        }

        let attributedText = NSMutableAttributedString(string: date, attributes: attributes)
        attributedText.append(
            NSAttributedString(
                string: " \(time)",
                attributes: [
                    .font: WTypography.uiFont(.caption2, content: .technical),
                    .foregroundColor: textColor
                ]
            )
        )
        return attributedText
    }
}


final class AgentSpacerCell: UICollectionViewCell {
    var heightProvider: (() -> CGFloat)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size.height = max(0, heightProvider?() ?? 0)
        return attributes
    }
}

/// The Agent at work: its spinning top beside the current step, in the Agent's blue-to-purple gradient
final class AgentTypingIndicatorCell: UICollectionViewCell {
    /// The spinning top's size beside the step, which the consent sheet's title has beside it too
    static let spinningTopSize: CGFloat = Metrics.iconSize

    private enum Metrics {
        static let iconSize: CGFloat = 24
        static let iconLeading: CGFloat = 12
        static let textLeading: CGFloat = 40
        static let verticalPadding: CGFloat = 10
        static let minimumHeight: CGFloat = 40
    }

    private let contentLayoutGuide = UILayoutGuide()
    private let spinningTopView = AgentSpinningTopView()
    private let statusLabel = AgentGradientLabel()

    private lazy var leadingConstraint = spinningTopView.leadingAnchor.constraint(
        equalTo: contentLayoutGuide.leadingAnchor,
        constant: AgentMessageCellMetrics.horizontalInset + Metrics.iconLeading
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// How fast the status goes when the user stops the Agent
    static let stoppedStatusFadeDuration: TimeInterval = 0.15

    /// The user stopped the Agent while it thought: the status goes at once, and the row's top, no longer thinking,
    /// grows as a press grows it and is knocked as by a failure, wobbling while grown. With Reduce Motion the top
    /// neither grows nor is knocked.
    func showStop() {
        isStopped = true
        spinningTopView.agentState = .idle
        UIView.animate(
            withDuration: Self.stoppedStatusFadeDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.statusLabel.alpha = 0
        }
        spinningTopView.grow()
        spinningTopView.knock()
    }

    /// The stopped row's top eases back to its resting size, never under it, and back into its place in the row
    func releaseTop() {
        spinningTopView.release()
    }

    /// The row and its top fade away together, the top at its resting size in its place: a top still grown ends its
    /// growth at once rather than shrink away apart from the row
    func fadeAway(duration: CFTimeInterval, completion: @escaping () -> Void) {
        spinningTopView.endGrowth()
        AgentBlurTransition.animateOut(contentView.layer, duration: duration, completion: completion)
    }

    /// The row's top, which the chat's tests watch
    var topView: AgentSpinningTopView { spinningTopView }

    /// The row stays a moment after a Stop, its top no longer thinking
    private var isStopped = false

    @discardableResult
    func configure(statusText: String? = nil, accessibilityLabel: String? = nil) -> Bool {
        let normalizedStatusText = statusText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? lang("$agent_activity_analyzing_request")
        let textChanged = statusLabel.text != normalizedStatusText
        spinningTopView.isActive = true
        // The typing row shows while the Agent thinks
        spinningTopView.agentState = isStopped ? .idle : .thinking
        if textChanged {
            statusLabel.setText(normalizedStatusText, animated: window != nil)
        }
        isAccessibilityElement = accessibilityLabel != nil
        self.accessibilityLabel = accessibilityLabel
        return textChanged
    }

    /// Pictures of the spinning top and the status as they show now, where they stand in `container`, and the frame the
    /// two take up in the row, for the answer that takes the row's place to grow out of
    func makeAnswerMorphSource(in container: UIView) -> AgentTypingRowSource? {
        guard window != nil, !spinningTopView.bounds.isEmpty, !statusLabel.bounds.isEmpty,
              let topPicture = spinningTopView.snapshotView(afterScreenUpdates: false) else { return nil }
        let topFrame = spinningTopView.convert(spinningTopView.bounds, to: container)
        let statusFrame = statusLabel.convert(statusLabel.bounds, to: container)
        let content = topFrame.union(statusFrame)
        let rowFrame = convert(bounds, to: container)
        return AgentTypingRowSource(
            topPicture: topPicture,
            topFrame: topFrame,
            statusPicture: UIImageView(image: statusLabel.makeLayerImage()),
            statusFrame: statusFrame,
            rowFrame: CGRect(
                x: content.minX - Metrics.iconLeading,
                y: rowFrame.minY,
                width: content.width + 2 * Metrics.iconLeading,
                height: rowFrame.height
            )
        )
    }

    /// The status comes up from transparency as it first appears, its text coming into focus out of a blur
    func revealFromTransparency() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        AgentBlurTransition.animateIn(contentView.layer, duration: 0.35, drift: 6, shouldSkipBlur: true)
        AgentBlurTransition.animateIn(statusLabel.layer, duration: 0.4)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        AgentBlurTransition.cancel(contentView.layer)
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        statusLabel.setText(nil, animated: false)
        statusLabel.layer.removeAllAnimations()
        statusLabel.alpha = 1
        // A top grown for a Stop shrinks away, out of the window
        spinningTopView.dismiss()
        isAccessibilityElement = false
        accessibilityLabel = nil
        isStopped = false
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetWidth = attributes.size.width
        bounds.size.width = targetWidth
        setNeedsLayout()
        layoutIfNeeded()
        let targetSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let fittedSize = contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size.height = ceil(fittedSize.height)
        return attributes
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false
        setupCenteredContentLayoutGuide(contentLayoutGuide)

        spinningTopView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinningTopView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.isAccessibilityElement = false
        contentView.addSubview(statusLabel)
        accessibilityIdentifier = "agent_progress"

        // While the list measures the row again, its height can be briefly less than the status needs. The row's
        // height gives way then, never the top's square: squeezed for a frame, the top would draw tiny.
        let height = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumHeight)
            .withPriority(UILayoutPriority(999))
        NSLayoutConstraint.activate([
            height,
            leadingConstraint,
            spinningTopView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            spinningTopView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
            spinningTopView.centerYAnchor.constraint(equalTo: statusLabel.firstBaselineAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: spinningTopView.leadingAnchor, constant: Metrics.textLeading - Metrics.iconLeading),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentMessageCellMetrics.incomingTrailingInset
            ),
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.verticalPadding),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Metrics.verticalPadding)
                .withPriority(UILayoutPriority(999)),
        ])
    }
}

/// A label painted with the Agent's gradient, which slowly sweeps along the text while the Agent works
final class AgentGradientLabel: UILabel {
    /// The design's gradient spans one text width (blue, cyan at 39.5%, purple); the tile covers two widths and runs
    /// back to blue, so the sweep repeats seamlessly
    private static let colors = ["#0088FF", "#00BEFF", "#B656FF", "#00BEFF", "#0088FF"].map { UIColor(hex: $0).cgColor }
    private static let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 0.1977, 0.5, 0.8023, 1]
    )
    static let textFont = UIFont.systemFont(ofSize: 17, weight: .medium)
    /// A glint of whitish light passes across the text once each time it changes, as light runs over metal: it starts
    /// `glintDelay` after the change, as the new text comes into focus, and takes `glintDuration`
    static let glintDelay: CFTimeInterval = 0.3
    static let glintDuration: CFTimeInterval = 0.75
    /// Half the glint's width across, in points
    static let glintHalfWidth: CGFloat = 16
    /// The glint's opacity at its middle: a soft light rather than a white streak
    static let glintPeakAlpha: CGFloat = 0.4
    private static let glintGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: glintPeakAlpha), UIColor(white: 1, alpha: 0)]
            .map(\.cgColor) as CFArray,
        locations: [0, 0.5, 1]
    )
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.advance() }
    private var phase: CGFloat = 0
    /// How long the glint has been running, negative while it waits for the new text, or nil once it has passed
    private(set) var glintTime: CFTimeInterval?
    private var lastFrame: CFTimeInterval?

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = Self.textFont
        textColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ text: String?, animated: Bool) {
        if let text, text != self.text {
            glintTime = -Self.glintDelay
        } else if text == nil {
            glintTime = nil
        }
        changeText(animated: animated) {
            self.attributedText = text.map {
                NSAttributedString(string: $0, attributes: [.font: Self.textFont, .foregroundColor: UIColor.black])
            }
        }
    }

    /// The text a moment ago, leaving while the new one comes in
    private var outgoingTextView: UIView?

    /// Applies new text with `apply`. Animated, the old text blurs away as it drifts up, while the new one comes into
    /// focus from below, the two crossing in a blur.
    func changeText(animated: Bool, apply: () -> Void) {
        outgoingTextView?.removeFromSuperview()
        outgoingTextView = nil
        AgentBlurTransition.cancel(layer)
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        guard animated, window != nil, let superview, !bounds.isEmpty, (attributedText?.length ?? 0) > 0,
              !UIAccessibility.isReduceMotionEnabled else {
            apply()
            return
        }
        let outgoing = UIImageView(image: makeLayerImage())
        outgoing.frame = frame
        outgoing.isUserInteractionEnabled = false
        outgoing.isAccessibilityElement = false
        superview.insertSubview(outgoing, aboveSubview: self)
        outgoingTextView = outgoing
        apply()

        let drift: CGFloat = 5
        AgentBlurTransition.animateOut(outgoing.layer, duration: 0.25, drift: -drift) { [weak self, weak outgoing] in
            outgoing?.removeFromSuperview()
            if let self, outgoingTextView === outgoing { outgoingTextView = nil }
        }
        AgentBlurTransition.animateIn(layer, duration: 0.35, delay: 0.05, drift: drift)
    }

    override func drawText(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let gradient = Self.gradient else {
            super.drawText(in: rect)
            return
        }
        // The text is drawn as a shape and the gradient fills only that shape
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        super.drawText(in: rect)
        context.setBlendMode(.sourceIn)
        let width = max(1, bounds.width)
        let offset = Self.getSweepOffset(
            phase: phase,
            width: width,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        for start in [offset, offset + width * 2] {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: start, y: 0),
                end: CGPoint(x: start + width * 2, y: 0),
                options: []
            )
        }
        // The glint lights only the text, over its gradient, slanted as light on a polished surface
        if let glintTime, let centre = Self.getGlintCentre(
            time: glintTime,
            width: width,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        ), let glint = Self.glintGradient {
            context.setBlendMode(.sourceAtop)
            let slant = bounds.height * 0.35
            context.drawLinearGradient(
                glint,
                start: CGPoint(x: centre - Self.glintHalfWidth - slant, y: bounds.maxY),
                end: CGPoint(x: centre + Self.glintHalfWidth + slant, y: bounds.minY),
                options: []
            )
        }
        context.endTransparencyLayer()
    }

    /// Where the glint's middle crosses the text `time` seconds into the glint, or nil before or after it. It runs in
    /// the reading direction, from just before the text to just past it.
    static func getGlintCentre(time: CFTimeInterval, width: CGFloat, isRightToLeft: Bool) -> CGFloat? {
        let progress = time / glintDuration
        guard progress >= 0, progress <= 1 else { return nil }
        // Eased, so the light speeds up across the middle and lingers at the ends
        let eased = CGFloat(progress * progress * (3 - 2 * progress))
        let travel = width + 4 * glintHalfWidth
        let distance = -2 * glintHalfWidth + eased * travel
        return isRightToLeft ? width - distance : distance
    }

    /// Where the first of the two gradient tiles starts at `phase`. The sweep runs in the reading direction: rightward
    /// in left-to-right layouts, leftward in right-to-left ones. Either way the tiles cover the label.
    static func getSweepOffset(phase: CGFloat, width: CGFloat, isRightToLeft: Bool) -> CGFloat {
        isRightToLeft ? -phase * width * 2 : (phase - 1) * width * 2
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !UIAccessibility.isReduceMotionEnabled, !clock.isRunning {
            clock.start()
        } else if window == nil, clock.isRunning {
            clock.stop()
            lastFrame = nil
        }
    }

    private func advance() {
        let now = CACurrentMediaTime()
        let dt = lastFrame.map { min(0.05, now - $0) } ?? 0
        lastFrame = now
        step(by: dt)
    }

    /// Moves the sweep and the glint on by `dt` seconds
    func step(by dt: CFTimeInterval) {
        // One sweep every two seconds, so the text reads as alive without flickering
        phase = (phase + CGFloat(dt) / 2).truncatingRemainder(dividingBy: 1)
        if let glintTime {
            let time = glintTime + dt
            self.glintTime = time > Self.glintDuration ? nil : time
        }
        setNeedsDisplay()
    }
}

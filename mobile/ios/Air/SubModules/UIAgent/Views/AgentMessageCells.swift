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
    }

    private weak var contentLayoutGuide: UILayoutGuide?
    private var buttonsByID: [String: AgentSuggestionButton] = [:]
    private var onControlTap: ((String) -> Void)?
    private var loadingViews: [UIView] = []
    private var loadingRevealCompletedAt: CFTimeInterval?

    func showLoading() {
        guard loadingViews.isEmpty else { return }
        reset()
        isHidden = false
        accessibilityLabel = lang("Loading...")
        for width in [CGFloat(230), 270, 200] {
            let placeholder = AgentMessagesSkeletonView(style: .suggestion)
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            placeholder.isAccessibilityElement = false
            addArrangedSubview(placeholder)
            let preferred = placeholder.widthAnchor.constraint(equalToConstant: width)
            preferred.priority = .defaultHigh
            preferred.isActive = true
            placeholder.heightAnchor.constraint(equalToConstant: 40).isActive = true
            if let contentLayoutGuide {
                placeholder.widthAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.widthAnchor,
                                                  constant: -Metrics.horizontalInset * 2).isActive = true
            }
            loadingViews.append(placeholder)
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
        let loadingFrames = loadingViews.map(\.frame)
        let loadingAlreadyRevealed = loadingRevealCompletedAt.map { CACurrentMediaTime() >= $0 } ?? false
        loadingRevealCompletedAt = nil
        for view in loadingViews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        loadingViews.removeAll()
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
        for control in controls {
            let button: AgentSuggestionButton
            if let existingButton = buttonsByID[control.id] {
                button = existingButton
            } else {
                button = AgentSuggestionButton()
                button.accessibilityIdentifier = "agent_followup"
                button.maximumNumberOfLines = 0
                button.addAction(UIAction { [weak self] _ in
                    self?.onControlTap?(control.id)
                }, for: .touchUpInside)
                buttonsByID[control.id] = button
                addArrangedSubview(button)
                if let contentLayoutGuide {
                    button.widthAnchor.constraint(
                        lessThanOrEqualTo: contentLayoutGuide.widthAnchor,
                        constant: -Metrics.horizontalInset * 2
                    ).isActive = true
                }
            }
            button.configure(title: control.title, showsArrow: true)
            button.preferredMaxLayoutWidth = maxWidth
            button.isEnabled = control.isEnabled
            addArrangedSubview(button)
        }
        if !loadingFrames.isEmpty, !UIAccessibility.isReduceMotionEnabled {
            layoutIfNeeded()
            for (index, pair) in zip(arrangedSubviews, loadingFrames).enumerated() {
                let (button, source) = pair
                guard button.bounds.width > 0, button.bounds.height > 0 else { continue }
                let target = button.frame
                let cover = UIView(frame: button.bounds)
                cover.backgroundColor = .air.agentBubbleFill
                cover.layer.cornerRadius = 20
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.isUserInteractionEnabled = false
                button.addSubview(cover)
                let geometry = CABasicAnimation(keyPath: "transform")
                geometry.fromValue = CATransform3DConcat(
                    CATransform3DMakeScale(source.width / target.width, source.height / target.height, 1),
                    CATransform3DMakeTranslation(source.midX - target.midX, source.midY - target.midY, 0)
                )
                geometry.toValue = CATransform3DIdentity
                geometry.duration = 0.36
                geometry.timingFunction = AgentComposerMetrics.makeTelegramCurve()
                button.layer.add(geometry, forKey: "loadingReveal")
                cover.alpha = 0
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                let revealDelay = loadingAlreadyRevealed ? 0 : Metrics.revealStagger * Double(index)
                fade.beginTime = cover.layer.convertTime(CACurrentMediaTime(), from: nil) + 0.14 + revealDelay
                fade.duration = 0.22
                fade.fillMode = .backwards
                cover.layer.add(fade, forKey: "loadingReveal")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36 + revealDelay) { [weak cover] in
                    cover?.removeFromSuperview()
                }
            }
        } else if revealsFollowups {
            animateAppearance()
        }
    }

    func reset() {
        loadingRevealCompletedAt = nil
        for view in loadingViews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        loadingViews.removeAll()
        for button in buttonsByID.values {
            removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttonsByID.removeAll()
        onControlTap = nil
        isHidden = true
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

    /// The suggestions fade in and rise into place one after another. The reveal adds to what each suggestion shows
    /// rather than setting it, so a suggestion enabled or disabled meanwhile ends as it is now, and it plays as well
    /// inside an update that runs without animation, as the chat's update of its rows.
    func animateAppearance(delay: TimeInterval = 0) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let now = CACurrentMediaTime() + delay
        if !loadingViews.isEmpty {
            loadingRevealCompletedAt = now + Metrics.revealDuration
                + Metrics.revealStagger * Double(max(0, loadingViews.count - 1))
        }
        for (index, view) in arrangedSubviews.enumerated() {
            let beginTime = view.layer.convertTime(now, from: nil) + Metrics.revealStagger * Double(index)
            view.layer.add(
                Self.makeRevealAnimation(keyPath: "opacity", from: -1, beginTime: beginTime),
                forKey: Self.revealOpacityKey
            )
            view.layer.add(
                Self.makeRevealAnimation(keyPath: "transform.translation.y", from: Metrics.revealOffset, beginTime: beginTime),
                forKey: Self.revealOffsetKey
            )
        }
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
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    private static let revealOpacityKey = "agentFollowupRevealOpacity"
    private static let revealOffsetKey = "agentFollowupRevealOffset"
}

final class AgentMessageCell: UICollectionViewCell, AgentContextMenuPresentingCell, UITextViewDelegate {
    private struct AssistantConfiguration {
        var message: AgentMessage
        let textColor: UIColor
        var hasStreaming: Bool
        var hadStreaming: Bool
        var blocks: [AgentMessageBlock]
    }

    private struct AppliedRichContent {
        let messageID: AgentItemID
        let blocks: [AgentMessageBlock]
        let layoutMaxWidth: CGFloat
        let renderingPolicy: AgentMessageRenderingPolicy
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
    private let bubbleStackView = UIStackView()
    private let bubbleView = AgentBubbleBackgroundView()
    var skeletonRevealView: UIView { bubbleView }
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
    private var wasStreamingMessage = false
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
        guard let self else { return false }
        longPressMenuInteraction.present()
        return true
    }

    private lazy var leadingConstraint = bubbleStackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset)
    private lazy var trailingConstraint = bubbleStackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -AgentMessageCellMetrics.horizontalInset)
    private lazy var outgoingLeadingLimitConstraint = bubbleStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.outgoingOppositeInset)
    private lazy var incomingTrailingLimitConstraint = bubbleStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.trailingAnchor, constant: -AgentMessageCellMetrics.incomingTrailingInset)
    private lazy var outgoingMaxWidthConstraint = bubbleStackView.widthAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.widthAnchor, multiplier: AgentMessageCellMetrics.outgoingMaxWidthMultiplier)
    private lazy var bubbleStackViewBottomConstraint = bubbleStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
    private lazy var bubbleMinimumWidthConstraint = bubbleView.widthAnchor.constraint(greaterThanOrEqualToConstant: AgentMessageCellMetrics.minimumBubbleWidth)
    private lazy var bubbleMinimumHeightConstraint = bubbleView.heightAnchor.constraint(greaterThanOrEqualToConstant: AgentMessageCellMetrics.minimumBubbleHeight)
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
            wasStreamingMessage = false
            didShowDeferredAction = false
            didShowDeferredSupplementaryError = false
            lastAppliedRichContent = nil
            lastAppliedSemanticContent = nil
            lastAppliedTextLayoutMaxWidth = 0
        }
        let hasStreaming = message.role == .assistant && message.isStreaming
        if !hasStreaming, wasStreamingMessage, message.answerBlocks?.contains(where: {
            if case .table = $0 { return true }
            return false
        }) == true {
            // Structured tables replace the reveal view immediately, so its completion callback
            // cannot be responsible for releasing follow-ups or trimming reserved scroll space.
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
        // A streaming answer has its own id, so a test can wait for the answer to finish
        accessibilityIdentifier = isOutgoing
            ? "agent_message_user"
            : hasStreaming ? "agent_message_streaming" : "agent_message_assistant"
        self.onControlTap = controls.isEmpty ? nil : onControlTap
        self.onURLTap = message.renderingPolicy.allowsLinks || AgentTextLinks.containsLinks(message.text)
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
            let blocks: [AgentMessageBlock]
            if let answerBlocks = message.answerBlocks {
                blocks = answerBlocks
            } else if hasStreaming || hadStreaming {
                blocks = []
            } else if let existing = lastAssistantConfiguration,
                      existing.message.id == message.id,
                      existing.message.text == message.text,
                      existing.message.answerBlocks == nil {
                blocks = existing.blocks
            } else {
                blocks = AgentMessageBlockParser.parse(message.text)
            }
            lastAssistantConfiguration = AssistantConfiguration(
                message: message,
                textColor: messageTextColor,
                hasStreaming: hasStreaming,
                hadStreaming: hadStreaming,
                blocks: blocks
            )
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
        }
        let resolvedShowsAction = hasActionRows && (showsAction || didShowDeferredAction)
        applyActionPresentation(
            showsAction: resolvedShowsAction,
            controls: controls,
            isOutgoing: isOutgoing,
            showsTail: !resolvedShowsAction || !controls.contains { $0.kind == .action },
            animatesFollowups: !messageIDChanged
        )
    }

    func updateStreamingMessage(_ message: AgentMessage) {
        guard message.role == .assistant, message.isStreaming else { return }
        guard configuredMessageID == message.id, let existing = lastAssistantConfiguration else { return }

        lastAssistantConfiguration = AssistantConfiguration(
            message: message,
            textColor: existing.textColor,
            hasStreaming: true,
            hadStreaming: false,
            blocks: []
        )
        configureAssistantMessageContent(layoutMaxWidth: currentTextLayoutMaxWidth(isOutgoing: false))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuredMessageID = nil
        wasStreamingMessage = false
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
        followupView.updateMaxWidth()
        guard userMessageTextView.isHidden, lastAssistantConfiguration != nil else { return }
        let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: false)
        guard abs(layoutMaxWidth - lastAppliedTextLayoutMaxWidth) > 0.5 else { return }
        lastAppliedTextLayoutMaxWidth = layoutMaxWidth
        withSizeCallbacksSuppressed {
            configureAssistantMessageContent(layoutMaxWidth: layoutMaxWidth)
        }
    }

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

        bubbleStackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStackView.axis = .vertical
        bubbleStackView.spacing = AgentMessageCellMetrics.bubbleToButtonSpacing
        bubbleStackView.alignment = .fill
        contentView.addSubview(bubbleStackView)

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStackView.addArrangedSubview(bubbleView)

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
        contentStackView.addArrangedSubview(assistantMessageTextView)
        contentStackView.addArrangedSubview(assistantRichMessageView)
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

        leadingConstraint.isActive = true
        incomingTrailingLimitConstraint.isActive = true

        NSLayoutConstraint.activate([
            bubbleStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubbleStackViewBottomConstraint,
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
        let bubbleWidth: CGFloat
        if isOutgoing {
            let percentageCappedBubbleWidth = contentWidth * AgentMessageCellMetrics.outgoingMaxWidthMultiplier
            let marginCappedBubbleWidth = contentWidth
                - AgentMessageCellMetrics.horizontalInset
                - AgentMessageCellMetrics.outgoingOppositeInset
            bubbleWidth = min(percentageCappedBubbleWidth, marginCappedBubbleWidth)
        } else {
            bubbleWidth = contentWidth
                - AgentMessageCellMetrics.horizontalInset
                - AgentMessageCellMetrics.incomingTrailingInset
        }
        return max(
            120,
            bubbleWidth - AgentMessageCellMetrics.bodyHorizontalPadding * 2
        )
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
            lastAppliedRichContent = nil
            return
        }
        let containsTable = configuration.blocks.contains {
            if case .table = $0 { return true }
            return false
        }
        let showsRichContent = containsTable
            && (configuration.message.answerBlocks != nil || (!configuration.hasStreaming && !configuration.hadStreaming))
        assistantMessageTextView.isHidden = showsRichContent
        assistantRichMessageView.isHidden = !showsRichContent

        if showsRichContent {
            assistantMessageTextView.isAccessibilityElement = false
            assistantMessageTextView.accessibilityIdentifier = nil
            assistantMessageTextView.accessibilityLabel = nil
            let appliedContent = AppliedRichContent(
                messageID: configuration.message.id,
                blocks: configuration.blocks,
                layoutMaxWidth: layoutMaxWidth,
                renderingPolicy: configuration.message.renderingPolicy
            )
            if let previous = lastAppliedRichContent,
               previous.messageID == appliedContent.messageID,
               previous.blocks == appliedContent.blocks,
               previous.renderingPolicy == appliedContent.renderingPolicy,
               abs(previous.layoutMaxWidth - appliedContent.layoutMaxWidth) <= 0.5 {
                return
            }
            assistantRichMessageView.configure(
                blocks: configuration.blocks,
                textColor: configuration.textColor,
                maximumContentWidth: layoutMaxWidth,
                detectsLinks: configuration.message.renderingPolicy.allowsLinks,
                markdownProfile: configuration.message.renderingPolicy.markdownProfile,
                onURLTap: onURLTap
            )
            lastAppliedRichContent = appliedContent
            return
        }
        lastAppliedRichContent = nil
        assistantMessageTextView.configure(
            text: configuration.message.text,
            textColor: configuration.textColor,
            isStreaming: configuration.hasStreaming,
            hadStreaming: configuration.hadStreaming,
            rendersMarkdown: true,
            markdownProfile: configuration.message.renderingPolicy.markdownProfile,
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

    private func showFinalAssistantContentIfNeeded() -> Bool {
        guard var configuration = lastAssistantConfiguration else { return false }
        configuration.hasStreaming = false
        configuration.hadStreaming = false
        configuration.blocks = configuration.message.answerBlocks
            ?? AgentMessageBlockParser.parse(configuration.message.text)
        lastAssistantConfiguration = configuration
        wasStreamingMessage = false
        let hasFinalContent = configuration.message.semanticContent != nil || configuration.blocks.contains(where: {
            if case .table = $0 { return true }
            return false
        })
        guard hasFinalContent else { return false }
        configureAssistantMessageContent(layoutMaxWidth: currentTextLayoutMaxWidth(isOutgoing: false))
        setNeedsLayout()
        return true
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
            animatesFollowups: true
        )
        onPreferredHeightChanged?(false)
    }

    private func applyActionPresentation(
        showsAction: Bool,
        controls: [AgentMessageControl],
        isOutgoing: Bool,
        showsTail: Bool,
        animatesFollowups: Bool
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

        // An answer with suggestions under it has no tail: the suggestions hang from it. The tail comes back as they go.
        bubbleView.configure(
            direction: isOutgoing ? .outgoing : .incoming,
            fillColor: isOutgoing ? .tintColor : UIColor.air.agentBubbleFill,
            usesTintColor: isOutgoing,
            showsTail: !showsActionRows && !showsFollowups && showsTail,
            cornerRadii: showsActionRows ? .topActioned : .standAlone,
            shouldAnimateTail: animatesFollowups && window != nil
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

    /// A touch on a link keeps the link's own action, while a long press on a control in the bubble opens the menu. Link
    /// views take touches on links only.
    private func canOpenMenu(at point: CGPoint, in sourceView: UIView) -> Bool {
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
    /// and action rows), as it did on the system context menu. Layout reaches the views rich content adds later.
    private func offerMenuToAccessibility(in view: UIView) {
        let actions = view.accessibilityCustomActions ?? []
        if !actions.contains(where: { $0 === menuAccessibilityAction }) {
            view.accessibilityCustomActions = actions + [menuAccessibilityAction]
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
        return path.cgPath
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

    /// Builds the row's menu when a long press opens it
    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)?

    private let contentLayoutGuide = UILayoutGuide()
    private let label = UILabel()
    /// Shows a failure, with its controls as links after the text
    private let captionTextView = AgentMessageTextView()
    private lazy var bottomConstraint = label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    private lazy var captionBottomConstraint = captionTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
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
        label.isHidden = isFailure
        captionTextView.isHidden = !isFailure
        if isFailure {
            bottomConstraint.isActive = false
            captionBottomConstraint.isActive = true
        } else {
            captionBottomConstraint.isActive = false
            bottomConstraint.isActive = true
        }
        applyText(for: message)
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
        captionTextView.attributedText = nil
        captionTextView.accessibilityCustomActions = nil
    }

    var contextMenuCopyText: String? {
        let text = configuredMessage?.isFailureCaption == true
            ? configuredMessage?.text ?? ""
            : label.attributedText?.string ?? label.text ?? ""
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

    /// The rounded label, in the coordinates of `attachmentRect`, which frames `contentView`
    private func labelPath(in attachmentRect: CGRect) -> CGPath {
        contentView.layoutIfNeeded()

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
        contextMenuInteraction.attach(to: contentView)
        // VoiceOver finds the row's menu as an action on its text, as it did on the system context menu
        label.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: lang("More actions")) { [weak self] _ in
                guard let self else { return false }
                contextMenuInteraction.present()
                return true
            }
        ]

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
            )
        ])
    }

    private func makeAttributedText(for message: AgentMessage) -> NSAttributedString {
        let textColor = UIColor.air.secondaryLabel.resolvedColor(with: traitCollection)
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

    @discardableResult
    func configure(statusText: String? = nil, accessibilityLabel: String? = nil) -> Bool {
        let normalizedStatusText = statusText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? lang("$agent_activity_analyzing_request")
        let textChanged = statusLabel.text != normalizedStatusText
        spinningTopView.isActive = true
        if textChanged {
            statusLabel.setText(normalizedStatusText, animated: window != nil)
        }
        isAccessibilityElement = accessibilityLabel != nil
        self.accessibilityLabel = accessibilityLabel
        return textChanged
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
        isAccessibilityElement = false
        accessibilityLabel = nil
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
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.advance() }
    private var phase: CGFloat = 0
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
        context.endTransparencyLayer()
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
        // One sweep every two seconds, so the text reads as alive without flickering
        phase = (phase + CGFloat(dt) / 2).truncatingRemainder(dividingBy: 1)
        setNeedsDisplay()
    }
}

import UIKit
import UIComponents
import WalletContext
import WalletCore

enum AgentContentLayout {
    static let maxContentWidth: CGFloat = 580
}

private enum AgentMessageCellMetrics {
    static let horizontalInset: CGFloat = 16
    static let outgoingOppositeInset: CGFloat = 72
    static let outgoingMaxWidthMultiplier: CGFloat = 0.8
    static let incomingTrailingInset: CGFloat = 24
    static let followupHorizontalInset: CGFloat = 20
    static let followupRevealOffset: CGFloat = 8
    static let followupRevealDuration: TimeInterval = 0.3
    static let followupRevealStagger: TimeInterval = 0.06
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
    func contextMenuPreview() -> UITargetedPreview?
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

    var isRevealingStreamedText: Bool {
        wasStreamingMessage
    }

    private let contentLayoutGuide = UILayoutGuide()
    private let bubbleStackView = UIStackView()
    private let bubbleView = AgentBubbleBackgroundView()
    private let contentStackView = UIStackView()
    private let actionBackgroundView = AgentBubbleBackgroundView()
    private let userMessageTextView = AgentMessageTextView()
    private let assistantMessageTextView = AgentStreamingTextView()
    private let assistantRichMessageView = AgentRichMessageView()
    private let assistantSemanticContentView = AgentV2SemanticContentView(style: .embedded)
    private let assistantSupplementaryErrorLabel = UILabel()
    private let actionStackView = UIStackView()
    private let followupStackView = UIStackView()
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
    private var onURLTap: ((URL) -> Void)?
    private var lastAssistantConfiguration: AssistantConfiguration?
    private var lastAppliedRichContent: AppliedRichContent?
    private var lastAppliedSemanticContent: AppliedSemanticContent?
    private var lastAppliedTextLayoutMaxWidth: CGFloat = 0
    private var suppressesSizeCallbacks = false

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
        updateFollowupMaxWidth()
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

        followupStackView.translatesAutoresizingMaskIntoConstraints = false
        followupStackView.axis = .vertical
        followupStackView.alignment = .leading
        followupStackView.spacing = AgentSuggestionButton.spacing
        followupStackView.isHidden = true
        contentView.addSubview(followupStackView)
        followupConstraints = [
            followupStackView.topAnchor.constraint(equalTo: bubbleStackView.bottomAnchor, constant: 24),
            followupStackView.leadingAnchor.constraint(
                equalTo: contentLayoutGuide.leadingAnchor,
                constant: AgentMessageCellMetrics.followupHorizontalInset
            ),
            followupStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentMessageCellMetrics.followupHorizontalInset
            ),
            followupStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ]

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
            ? "agent-v2-answer"
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
        let revealsFollowups = animatesFollowups && showsFollowups && followupStackView.isHidden
        actionBackgroundView.isHidden = !showsActionRows
        followupStackView.isHidden = !showsFollowups
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
        if revealsFollowups {
            animateAppearance(of: followupStackView.arrangedSubviews)
        }

        bubbleView.configure(
            direction: isOutgoing ? .outgoing : .incoming,
            fillColor: isOutgoing ? .tintColor : UIColor.air.agentBubbleFill,
            usesTintColor: isOutgoing,
            showsTail: !showsActionRows && (showsTail || showsFollowups),
            cornerRadii: showsActionRows ? .topActioned : .standAlone
        )

        actionBackgroundView.configure(
            direction: .incoming,
            fillColor: .tintColor.withAlphaComponent(0.10),
            usesTintColor: true,
            showsTail: false,
            cornerRadii: .bottomAction
        )
    }

    private func animateAppearance(of views: [UIView]) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        for (index, view) in views.enumerated() {
            let alpha = view.alpha
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: AgentMessageCellMetrics.followupRevealOffset)
            UIView.animate(
                withDuration: AgentMessageCellMetrics.followupRevealDuration,
                delay: AgentMessageCellMetrics.followupRevealStagger * Double(index),
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                view.alpha = alpha
                view.transform = .identity
            }
        }
    }

    private var followupMaxWidth: CGFloat {
        contentLayoutGuide.layoutFrame.width - AgentMessageCellMetrics.followupHorizontalInset * 2
    }

    private func updateFollowupMaxWidth() {
        let maxWidth = followupMaxWidth
        for case let button as AgentSuggestionButton in followupStackView.arrangedSubviews {
            button.preferredMaxLayoutWidth = maxWidth
        }
    }

    private func configureActionRows(_ controls: [AgentMessageControl]) {
        for button in controlButtonsByID.values {
            actionStackView.removeArrangedSubview(button)
            followupStackView.removeArrangedSubview(button)
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
            if let suggestionButton = button as? AgentSuggestionButton {
                suggestionButton.configure(title: control.title, showsArrow: true)
                suggestionButton.preferredMaxLayoutWidth = followupMaxWidth
                suggestionButton.isEnabled = control.isEnabled
                followupStackView.addArrangedSubview(button)
            } else {
                configureActionButton(button, title: control.title, isEnabled: control.isEnabled)
                actionStackView.addArrangedSubview(button)
            }
        }
    }

    private func makeControlButton(_ control: AgentMessageControl) -> UIButton {
        let button: UIButton = control.kind == .followup ? AgentSuggestionButton() : UIButton(type: .system)
        button.addAction(UIAction { [weak self] _ in
            self?.onControlTap?(control.id)
        }, for: .touchUpInside)
        if let suggestionButton = button as? AgentSuggestionButton {
            suggestionButton.maximumNumberOfLines = 0
            followupStackView.addArrangedSubview(button)
            button.widthAnchor.constraint(
                lessThanOrEqualTo: contentLayoutGuide.widthAnchor,
                constant: -AgentMessageCellMetrics.followupHorizontalInset * 2
            ).isActive = true
        }
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
            followupStackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        controlButtonsByID.removeAll()
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

    func contextMenuPreview() -> UITargetedPreview? {
        layoutIfNeeded()
        bubbleStackView.layoutIfNeeded()

        let combinedPreviewPath = UIBezierPath()
        combinedPreviewPath.append(previewPath(for: bubbleView))

        if !actionBackgroundView.isHidden {
            combinedPreviewPath.append(previewPath(for: actionBackgroundView))
        }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = combinedPreviewPath
        return UITargetedPreview(view: bubbleStackView, parameters: parameters)
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
        onURLTap?(url)
        return false
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
        onURLTap?(url)
        return false
    }
}

final class AgentSystemMessageCell: UICollectionViewCell, AgentContextMenuPresentingCell {
    private let contentLayoutGuide = UILayoutGuide()
    private let label = UILabel()
    private lazy var bottomConstraint = label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    private var configuredMessage: AgentMessage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: AgentMessage) {
        configuredMessage = message
        label.attributedText = makeAttributedText(for: message)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
              let configuredMessage else { return }
        label.attributedText = makeAttributedText(for: configuredMessage)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuredMessage = nil
        label.attributedText = nil
    }

    var contextMenuCopyText: String? {
        let text = label.attributedText?.string ?? label.text ?? ""
        return text.isEmpty ? nil : text
    }

    func contextMenuPreview() -> UITargetedPreview? {
        layoutIfNeeded()

        let previewRect = label.frame.inset(
            by: UIEdgeInsets(
                top: -AgentMessageCellMetrics.systemPreviewInsets.top,
                left: -AgentMessageCellMetrics.systemPreviewInsets.left,
                bottom: -AgentMessageCellMetrics.systemPreviewInsets.bottom,
                right: -AgentMessageCellMetrics.systemPreviewInsets.right
            )
        )
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: previewRect,
            cornerRadius: AgentMessageCellMetrics.systemPreviewCornerRadius
        )
        return UITargetedPreview(view: contentView, parameters: parameters)
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
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            bottomConstraint,
            label.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -40)
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

final class AgentTypingIndicatorCell: UICollectionViewCell {
    private let contentLayoutGuide = UILayoutGuide()
    private let bubbleView = AgentBubbleBackgroundView()
    private let contentStackView = UIStackView()
    private let dotsView = AgentTypingDotsView()
    private let statusLabel = UILabel()

    private lazy var leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset)
    private lazy var trailingLimitConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.trailingAnchor, constant: -AgentMessageCellMetrics.incomingTrailingInset)
    private lazy var bottomConstraint = bubbleView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)

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
        let normalizedStatusText = statusText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let textChanged = statusLabel.text != normalizedStatusText
        bubbleView.configure(direction: .incoming, fillColor: UIColor.air.agentBubbleFill)
        dotsView.startAnimating()
        if textChanged {
            statusLabel.text = normalizedStatusText
            statusLabel.isHidden = normalizedStatusText?.isEmpty != false
        }
        isAccessibilityElement = accessibilityLabel != nil
        self.accessibilityLabel = accessibilityLabel
        return textChanged
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dotsView.stopAnimating()
        statusLabel.text = nil
        statusLabel.isHidden = true
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

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.spacing = AgentMessageCellMetrics.typingIndicatorStatusSpacing
        bubbleView.contentView.addSubview(contentStackView)

        dotsView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(dotsView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = WTypography.uiFont(.footnote)
        statusLabel.textColor = UIColor.air.secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.isAccessibilityElement = false
        contentStackView.addArrangedSubview(statusLabel)

        leadingConstraint.isActive = true
        trailingLimitConstraint.isActive = true

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bottomConstraint,

            contentStackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor, constant: AgentMessageCellMetrics.bodyHorizontalPadding),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor, constant: -AgentMessageCellMetrics.bodyHorizontalPadding),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor, constant: AgentMessageCellMetrics.bodyHorizontalPadding),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor, constant: -AgentMessageCellMetrics.bodyHorizontalPadding),

            dotsView.widthAnchor.constraint(
                equalToConstant: AgentMessageCellMetrics.typingIndicatorDotsWidth
            ),
            dotsView.heightAnchor.constraint(
                equalToConstant: AgentMessageCellMetrics.typingIndicatorDotsHeight
            )
        ])
    }
}

final class AgentTypingDotsView: UIView {
    private let stackView = UIStackView()
    private let dots = (0..<3).map { _ in UIView() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        for (index, dot) in dots.enumerated() {
            dot.backgroundColor = UIColor.air.secondaryLabel.resolvedColor(with: traitCollection)
            if dot.layer.animation(forKey: "typingScale") != nil {
                continue
            }

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.8, 1.0, 0.8]
            scale.keyTimes = [0, 0.5, 1]
            scale.duration = 0.9
            scale.beginTime = CACurrentMediaTime() + 0.15 * Double(index)
            scale.repeatCount = .infinity
            scale.isRemovedOnCompletion = false
            dot.layer.add(scale, forKey: "typingScale")

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.35, 1.0, 0.35]
            opacity.keyTimes = [0, 0.5, 1]
            opacity.duration = 0.9
            opacity.beginTime = scale.beginTime
            opacity.repeatCount = .infinity
            opacity.isRemovedOnCompletion = false
            dot.layer.add(opacity, forKey: "typingOpacity")
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        let color = UIColor.air.secondaryLabel.resolvedColor(with: traitCollection)
        for dot in dots {
            dot.backgroundColor = color
        }
    }

    func stopAnimating() {
        for dot in dots {
            dot.layer.removeAnimation(forKey: "typingScale")
            dot.layer.removeAnimation(forKey: "typingOpacity")
        }
    }

    private func setupViews() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .center
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for dot in dots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 4
            dot.backgroundColor = UIColor.air.secondaryLabel
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalTo: dot.widthAnchor)
            ])
            stackView.addArrangedSubview(dot)
        }
    }
}

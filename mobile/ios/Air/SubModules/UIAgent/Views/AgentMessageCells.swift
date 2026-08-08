import UIKit
import UIComponents

enum AgentContentLayout {
    static let maxContentWidth: CGFloat = 580
}

private enum AgentMessageCellMetrics {
    static let horizontalInset: CGFloat = 16
    static let outgoingOppositeInset: CGFloat = 72
    static let outgoingMaxWidthMultiplier: CGFloat = 0.8
    static let incomingTrailingInset: CGFloat = 24
    static let bubbleToButtonSpacing: CGFloat = 3
    static let actionBottomSpacing: CGFloat = 7
    static let minimumBubbleWidth: CGFloat = 44
    static let minimumBubbleHeight: CGFloat = 40
    static let bodyHorizontalPadding: CGFloat = 14
    static let bodyVerticalPadding: CGFloat = 10
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
    var onPreferredHeightChanged: ((_ animated: Bool) -> Void)?
    var onStreamingRevealCompleted: (() -> Void)?
    var minimumHeightProvider: (() -> CGFloat)?

    private let contentLayoutGuide = UILayoutGuide()
    private let bubbleStackView = UIStackView()
    private let bubbleView = AgentBubbleBackgroundView()
    private let contentStackView = UIStackView()
    private let actionBackgroundView = AgentBubbleBackgroundView()
    private let userMessageTextView = AgentMessageTextView()
    private let assistantMessageTextView = AgentStreamingTextView()
    private let actionButton = UIButton(type: .system)
    private var configuredMessageID: AgentItemID?
    private var wasStreamingMessage = false
    private var deferredShowsAction = false
    private var didShowDeferredAction = false
    private var configuredAction: AgentMessageAction?
    private var onActionTap: (() -> Void)?
    private var onURLTap: ((URL) -> Void)?
    private var lastAssistantConfiguration: (message: AgentMessage, textColor: UIColor, hasStreaming: Bool, hadStreaming: Bool)?
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
        onActionTap: @escaping () -> Void,
        onURLTap: @escaping (URL) -> Void
    ) {
        let isOutgoing = message.role == .user
        let messageIDChanged = configuredMessageID != message.id
        if messageIDChanged {
            wasStreamingMessage = false
            didShowDeferredAction = false
        }
        let hasStreaming = message.role == .assistant && message.isStreaming
        let hadStreaming = !messageIDChanged && wasStreamingMessage && !hasStreaming

        let action = message.action
        deferredShowsAction = action != nil && !isOutgoing && !message.isStreaming
        configuredAction = action
        let showsAction = didShowDeferredAction || (deferredShowsAction && !hasStreaming && !hadStreaming)
        let showsTail = !showsAction
        let messageTextColor = isOutgoing ? UIColor.white : UIColor.label
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
        self.onActionTap = action == nil ? nil : onActionTap
        self.onURLTap = onURLTap

        userMessageTextView.isHidden = !isOutgoing
        assistantMessageTextView.isHidden = isOutgoing

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
            lastAssistantConfiguration = (
                message: message,
                textColor: messageTextColor,
                hasStreaming: hasStreaming,
                hadStreaming: hadStreaming
            )
            assistantMessageTextView.onURLTap = { [weak self] url in
                self?.onURLTap?(url)
            }
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
                self?.applyDeferredActionPresentation()
                self?.onStreamingRevealCompleted?()
            }
            withSizeCallbacksSuppressed {
                configureAssistantMessageTextView(layoutMaxWidth: layoutMaxWidth)
            }
        }

        if hasStreaming {
            wasStreamingMessage = true
        }
        applyActionPresentation(showsAction: showsAction, action: action, isOutgoing: isOutgoing, showsTail: showsTail)
    }

    func updateStreamingMessage(_ message: AgentMessage) {
        guard message.role == .assistant, message.isStreaming else { return }
        guard configuredMessageID == message.id, let existing = lastAssistantConfiguration else { return }

        lastAssistantConfiguration = (
            message: message,
            textColor: existing.textColor,
            hasStreaming: true,
            hadStreaming: false
        )
        configureAssistantMessageTextView(layoutMaxWidth: currentTextLayoutMaxWidth(isOutgoing: false))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        deferredShowsAction = false
        configuredAction = nil
        onActionTap = nil
        onURLTap = nil
        onPreferredHeightChanged = nil
        onStreamingRevealCompleted = nil
        minimumHeightProvider = nil
        userMessageTextView.layer.removeAllAnimations()
        userMessageTextView.attributedText = nil
        userMessageTextView.isSelectable = false
        userMessageTextView.isUserInteractionEnabled = false
        assistantMessageTextView.prepareForReuse()
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
        guard !assistantMessageTextView.isHidden, lastAssistantConfiguration != nil else { return }
        let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: false)
        guard abs(layoutMaxWidth - lastAppliedTextLayoutMaxWidth) > 0.5 else { return }
        lastAppliedTextLayoutMaxWidth = layoutMaxWidth
        withSizeCallbacksSuppressed {
            configureAssistantMessageTextView(layoutMaxWidth: layoutMaxWidth)
        }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetWidth = attributes.size.width
        bounds.size.width = targetWidth
        setNeedsLayout()
        layoutIfNeeded()
        if !assistantMessageTextView.isHidden, lastAssistantConfiguration != nil {
            let layoutMaxWidth = currentTextLayoutMaxWidth(isOutgoing: false)
            lastAppliedTextLayoutMaxWidth = layoutMaxWidth
            withSizeCallbacksSuppressed {
                configureAssistantMessageTextView(layoutMaxWidth: layoutMaxWidth)
            }
            layoutIfNeeded()
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

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.contentInsets = AgentMessageCellMetrics.actionOuterPadding
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WTypography.uiFont(.calloutEmphasized)
            return outgoing
        }
        actionButton.configuration = buttonConfiguration
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.tintAdjustmentMode = .normal
        actionButton.addTarget(self, action: #selector(actionButtonPressed), for: .touchUpInside)

        contentStackView.addArrangedSubview(userMessageTextView)
        contentStackView.addArrangedSubview(assistantMessageTextView)

        actionBackgroundView.contentView.addSubview(actionButton)

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

            actionButton.topAnchor.constraint(equalTo: actionBackgroundView.contentView.topAnchor, constant: AgentMessageCellMetrics.actionContainerInsets.top),
            actionButton.leadingAnchor.constraint(equalTo: actionBackgroundView.contentView.leadingAnchor, constant: AgentMessageCellMetrics.actionContainerInsets.left),
            actionButton.trailingAnchor.constraint(equalTo: actionBackgroundView.contentView.trailingAnchor, constant: -AgentMessageCellMetrics.actionContainerInsets.right),
            actionButton.bottomAnchor.constraint(equalTo: actionBackgroundView.contentView.bottomAnchor, constant: -AgentMessageCellMetrics.actionContainerInsets.bottom)
        ])
    }

    @objc private func actionButtonPressed() {
        onActionTap?()
    }

    private func renderedMessageText() -> String {
        if !assistantMessageTextView.isHidden {
            return assistantMessageTextView.displayText
        }
        return userMessageTextView.attributedText?.string ?? userMessageTextView.text ?? ""
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

    private func configureAssistantMessageTextView(layoutMaxWidth: CGFloat) {
        guard let configuration = lastAssistantConfiguration else { return }
        assistantMessageTextView.configure(
            text: configuration.message.text,
            textColor: configuration.textColor,
            isStreaming: configuration.hasStreaming,
            hadStreaming: configuration.hadStreaming,
            rendersMarkdown: true,
            allowsLinks: true,
            layoutMaxWidth: layoutMaxWidth,
            streamingIdentity: configuration.message.id.uuidString
        )
    }

    private func applyDeferredActionPresentation() {
        guard deferredShowsAction else { return }
        didShowDeferredAction = true
        applyActionPresentation(
            showsAction: true,
            action: configuredAction,
            isOutgoing: false,
            showsTail: false
        )
        onPreferredHeightChanged?(false)
    }

    private func applyActionPresentation(
        showsAction: Bool,
        action: AgentMessageAction?,
        isOutgoing: Bool,
        showsTail: Bool
    ) {
        actionBackgroundView.isHidden = !showsAction
        bubbleStackViewBottomConstraint.constant = showsAction
            ? -AgentMessageCellMetrics.actionBottomSpacing
            : 0

        var buttonConfiguration = actionButton.configuration ?? .plain()
        buttonConfiguration.title = action?.title
        buttonConfiguration.baseForegroundColor = .tintColor
        buttonConfiguration.background = .clear()
        actionButton.configuration = buttonConfiguration

        bubbleView.configure(
            direction: isOutgoing ? .outgoing : .incoming,
            fillColor: isOutgoing ? .tintColor : UIColor.air.agentBubbleFill,
            usesTintColor: isOutgoing,
            showsTail: showsTail,
            cornerRadii: showsAction ? .topActioned : .standAlone
        )

        actionBackgroundView.configure(
            direction: .incoming,
            fillColor: .tintColor.withAlphaComponent(0.10),
            usesTintColor: true,
            showsTail: false,
            cornerRadii: .bottomAction
        )
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
        guard !userMessageTextView.isHidden,
              let text = userMessageTextView.attributedText?.string ?? userMessageTextView.text,
              !text.isEmpty else { return }
        setUserMessageText(text, textColor: .white)
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
        let text = renderedMessageText()
        return text.isEmpty ? nil : text
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
    private let dotsView = AgentTypingDotsView()

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

    func configure() {
        bubbleView.configure(direction: .incoming, fillColor: UIColor.air.agentBubbleFill)
        dotsView.startAnimating()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dotsView.stopAnimating()
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

        dotsView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.contentView.addSubview(dotsView)

        leadingConstraint.isActive = true
        trailingLimitConstraint.isActive = true

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bottomConstraint,

            dotsView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor, constant: AgentMessageCellMetrics.bodyHorizontalPadding),
            dotsView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor, constant: -AgentMessageCellMetrics.bodyHorizontalPadding),
            dotsView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor, constant: AgentMessageCellMetrics.bodyHorizontalPadding),
            dotsView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor, constant: -AgentMessageCellMetrics.bodyHorizontalPadding),
            dotsView.heightAnchor.constraint(equalToConstant: 12)
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

import UIKit
import WalletContext

private enum AgentMessageCellMetrics {
    static let horizontalInset: CGFloat = 16
    static let compactHorizontalLimit: CGFloat = 72
    static let maxWidthMultiplier: CGFloat = 0.8
    static let bubbleToButtonSpacing: CGFloat = 3
    static let actionBottomSpacing: CGFloat = 7
    static let minimumBubbleWidth: CGFloat = 44
    static let minimumBubbleHeight: CGFloat = 40
    static let bodyHorizontalPadding: CGFloat = 14
    static let bodyVerticalPadding: CGFloat = 10
    static let actionOuterPadding = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
    static let actionContainerInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    static let bubbleCornerRadius: CGFloat = 20
    static let groupedInnerCornerRadius: CGFloat = 8
    static let groupedBottomCornerRadius: CGFloat = 16
    static let buttonFont = UIFont.systemFont(ofSize: 16, weight: .medium)
    static let systemFont = UIFont.systemFont(ofSize: 11, weight: .medium)
    static let systemTimeFont = UIFont.systemFont(ofSize: 11, weight: .regular)
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

private extension NSAttributedString {
    var containsLinkAttribute: Bool {
        guard length > 0 else { return false }

        var containsLink = false
        enumerateAttribute(.link, in: NSRange(location: 0, length: length)) { value, _, stop in
            guard value != nil else { return }
            containsLink = true
            stop.pointee = true
        }
        return containsLink
    }
}

protocol AgentContextMenuPresentingCell: UICollectionViewCell {
    var contextMenuCopyText: String? { get }
    func contextMenuPreview() -> UITargetedPreview?
}

final class AgentMessageCell: UICollectionViewCell, AgentContextMenuPresentingCell, UITextViewDelegate {
    private let bubbleStackView = UIStackView()
    private let bubbleView = AgentBubbleBackgroundView()
    private let contentStackView = UIStackView()
    private let actionBackgroundView = AgentBubbleBackgroundView()
    private let messageTextView = AgentMessageTextView()
    private let actionButton = UIButton(type: .system)
    private var configuredMessageID: AgentItemID?
    private var onActionTap: (() -> Void)?
    private var onURLTap: ((URL) -> Void)?

    private lazy var leadingConstraint = bubbleStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset)
    private lazy var trailingConstraint = bubbleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AgentMessageCellMetrics.horizontalInset)
    private lazy var leadingLimitConstraint = bubbleStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: AgentMessageCellMetrics.compactHorizontalLimit)
    private lazy var trailingLimitConstraint = bubbleStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -AgentMessageCellMetrics.compactHorizontalLimit)
    private lazy var maxWidthConstraint = bubbleStackView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: AgentMessageCellMetrics.maxWidthMultiplier)
    private lazy var bubbleStackViewBottomConstraint = bubbleStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
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
        let action = message.action
        let showsAction = action != nil && !isOutgoing && !message.isStreaming
        let showsTail = !showsAction
        let previousText = renderedMessageText()
        let shouldAnimateText = configuredMessageID == message.id
            && message.role == .assistant
            && message.isStreaming
            && message.text.count > previousText.count
            && message.text.hasPrefix(previousText)
        let messageTextColor = isOutgoing ? UIColor.white : UIColor.label
        let rendersMarkdown = message.role == .assistant
        let allowsLinkInteraction = message.role == .assistant

        leadingConstraint.isActive = !isOutgoing
        trailingLimitConstraint.isActive = !isOutgoing
        trailingConstraint.isActive = isOutgoing
        leadingLimitConstraint.isActive = isOutgoing

        configuredMessageID = message.id
        self.onActionTap = action == nil ? nil : onActionTap
        self.onURLTap = allowsLinkInteraction ? onURLTap : nil
        setMessageText(
            message.text,
            textColor: messageTextColor,
            rendersMarkdown: rendersMarkdown,
            allowsLinkInteraction: allowsLinkInteraction,
            animated: shouldAnimateText
        )
        actionBackgroundView.isHidden = !showsAction
        bubbleStackViewBottomConstraint.constant = showsAction ? -AgentMessageCellMetrics.actionBottomSpacing : 0

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
            cornerRadii: showsAction
                ? .init(
                    topLeft: AgentMessageCellMetrics.bubbleCornerRadius,
                    topRight: AgentMessageCellMetrics.bubbleCornerRadius,
                    bottomRight: AgentMessageCellMetrics.groupedInnerCornerRadius,
                    bottomLeft: AgentMessageCellMetrics.groupedInnerCornerRadius
                )
                : .uniform(AgentMessageCellMetrics.bubbleCornerRadius)
        )
        actionBackgroundView.configure(
            direction: .incoming,
            fillColor: UIColor.tintColor.withAlphaComponent(0.10),
            usesTintColor: true,
            showsTail: false,
            cornerRadii: .init(
                topLeft: AgentMessageCellMetrics.groupedInnerCornerRadius,
                topRight: AgentMessageCellMetrics.groupedInnerCornerRadius,
                bottomRight: AgentMessageCellMetrics.groupedBottomCornerRadius,
                bottomLeft: AgentMessageCellMetrics.groupedBottomCornerRadius
            )
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuredMessageID = nil
        onActionTap = nil
        onURLTap = nil
        messageTextView.layer.removeAllAnimations()
        messageTextView.attributedText = nil
        messageTextView.isSelectable = false
        messageTextView.isUserInteractionEnabled = false
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

        messageTextView.translatesAutoresizingMaskIntoConstraints = false
        messageTextView.backgroundColor = .clear
        messageTextView.font = AgentMessageTextRenderer.baseFont
        messageTextView.isEditable = false
        messageTextView.isScrollEnabled = false
        messageTextView.isSelectable = false
        messageTextView.isUserInteractionEnabled = false
        messageTextView.dataDetectorTypes = []
        messageTextView.textContainerInset = .zero
        messageTextView.textContainer.lineFragmentPadding = 0
        messageTextView.textContainer.maximumNumberOfLines = 0
        messageTextView.textContainer.lineBreakMode = .byWordWrapping
        messageTextView.textDragInteraction?.isEnabled = false
        messageTextView.linkTextAttributes = [
            .foregroundColor: UIColor.tintColor
        ]
        messageTextView.delegate = self
        messageTextView.setContentCompressionResistancePriority(.required, for: .vertical)
        messageTextView.setContentHuggingPriority(.required, for: .vertical)

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.contentInsets = AgentMessageCellMetrics.actionOuterPadding
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = AgentMessageCellMetrics.buttonFont
            return outgoing
        }
        actionButton.configuration = buttonConfiguration
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.tintAdjustmentMode = .normal
        actionButton.addTarget(self, action: #selector(actionButtonPressed), for: .touchUpInside)

        contentStackView.addArrangedSubview(messageTextView)

        actionBackgroundView.contentView.addSubview(actionButton)

        leadingConstraint.isActive = true
        trailingLimitConstraint.isActive = true

        NSLayoutConstraint.activate([
            bubbleStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubbleStackViewBottomConstraint,
            maxWidthConstraint,
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
        messageTextView.attributedText?.string ?? messageTextView.text ?? ""
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

    private func setMessageText(
        _ text: String,
        textColor: UIColor,
        rendersMarkdown: Bool,
        allowsLinkInteraction: Bool,
        animated: Bool
    ) {
        let attributedText = AgentMessageTextRenderer.makeAttributedText(
            text,
            textColor: textColor,
            rendersMarkdown: rendersMarkdown
        )
        let hasInteractiveLinks = allowsLinkInteraction && attributedText.containsLinkAttribute
        messageTextView.isSelectable = hasInteractiveLinks
        messageTextView.isUserInteractionEnabled = hasInteractiveLinks

        guard animated else {
            messageTextView.attributedText = attributedText
            return
        }

        messageTextView.layer.removeAllAnimations()
        UIView.transition(
            with: messageTextView,
            duration: 0.16,
            options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]
        ) {
            self.messageTextView.attributedText = attributedText
        }
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
    private let label = UILabel()
    private lazy var bottomConstraint = label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: AgentMessage) {
        label.attributedText = makeAttributedText(for: message)
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

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AgentMessageCellMetrics.systemFont
        label.textAlignment = .center
        label.numberOfLines = 0
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            bottomConstraint,
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40)
        ])
    }

    private func makeAttributedText(for message: AgentMessage) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AgentMessageCellMetrics.systemFont,
            .foregroundColor: UIColor.air.secondaryLabel
        ]

        guard case .dateTime(let date, let time)? = message.systemStyle else {
            return NSAttributedString(string: message.text, attributes: attributes)
        }

        let attributedText = NSMutableAttributedString(string: date, attributes: attributes)
        attributedText.append(
            NSAttributedString(
                string: " \(time)",
                attributes: [
                    .font: AgentMessageCellMetrics.systemTimeFont,
                    .foregroundColor: UIColor.air.secondaryLabel
                ]
            )
        )
        return attributedText
    }
}

final class AgentTypingIndicatorCell: UICollectionViewCell {
    private let bubbleView = AgentBubbleBackgroundView()
    private let dotsView = AgentTypingDotsView()

    private lazy var leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset)
    private lazy var trailingLimitConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -AgentMessageCellMetrics.compactHorizontalLimit)
    private lazy var bottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)

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
            dot.backgroundColor = UIColor.air.secondaryLabel
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

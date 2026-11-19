import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// A daily digest of the News feed, in the Agent's tailed bubble as the news cards are, topped in the look of the Agent's
/// suggestions: its title, how many news it covers, its top headlines, each opening its news item's discussion, the time
/// it came, and the Discuss strip that opens the digest's own discussion. A long press on the bubble opens its menu, as
/// on a news card.
final class AgentNewsDigestCardCell: UICollectionViewCell, AgentNewsFlightSource {
    /// The card's top in the look of the suggestions, as on the other platforms: a light sheen and the Agent's gradient,
    /// melting into the bubble's fill toward the headlines, and the title in the suggestions' gradient
    fileprivate enum Appearance {
        static let glowHeight: CGFloat = 150
        static let glowColors = [
            color("#0088FF", light: 0.12, dark: 0.18),
            color("#00BEFF", light: 0.18, dark: 0.24),
            color("#B656FF", light: 0.14, dark: 0.2),
        ]
        static let glowLocations: [NSNumber] = [0, 0.48, 1]
        /// How much of the suggestions' gradient the news count takes, as much contrast as the grey has
        static let metaGradientAlpha: (light: CGFloat, dark: CGFloat) = (0.65, 0.9)
        /// Under the gradient, so that it stays clear over the bubble's grey; none in the dark
        static let sheenColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .clear : UIColor(white: 1, alpha: 0.7)
        }

        private static func color(_ hex: String, light: CGFloat, dark: CGFloat) -> UIColor {
            UIColor { traits in
                UIColor(hex: hex).withAlphaComponent(traits.userInterfaceStyle == .dark ? dark : light)
            }
        }
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 16
        static let headerInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16)
        static let headlinesInsets = NSDirectionalEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
        /// Over the time under the line of the news the card leaves out, as over a news card's time
        static let remainderTimeSpacing: CGFloat = 8
    }

    /// A tap on the headline of the news item with this event ID
    var headlineAction: ((Int) -> Void)? {
        get { headlinesView.headlineAction }
        set { headlinesView.headlineAction = newValue }
    }
    var discussionAction: (() -> Void)?
    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)?
    /// The card's height changed with the text size while it was on screen
    var onPreferredHeightChanged: (() -> Void)?

    let bubbleView = AgentBubbleBackgroundView()
    private let glowView = AgentNewsDigestGlowView()
    private let contentLayoutGuide = UILayoutGuide()
    private let stackView = UIStackView()
    private let headerStack = UIStackView()
    private let titleLabel = AgentNewsDigestGradientLabel()
    /// Muted to the grey's contrast
    private let metaLabel = AgentNewsDigestGradientLabel(
        lightAlpha: Appearance.metaGradientAlpha.light,
        darkAlpha: Appearance.metaGradientAlpha.dark
    )
    private let headlinesView = AgentNewsDigestHeadlinesView()
    private let headlinesContainer = UIStackView()
    /// The digest's time in the bubble's trailing corner, as on the news cards and on the digest's post
    private let metaView = AgentNewsMetaView()
    private let footerContainer = UIStackView()
    private let discussionStrip = AgentNewsDiscussionStrip()
    private lazy var contextMenuInteraction = ContextMenuInteraction(
        triggers: .longPress,
        sourcePortal: ContextMenuSourcePortal(mask: .customAttachmentPath { [weak self] attachmentRect in
            self?.bubbleView.makePreviewPath(in: attachmentRect) ?? CGPath(rect: attachmentRect, transform: nil)
        }),
        pressAnimation: .default(transformMode: .sublayerTransform),
        // A press on a headline or on Discuss keeps to it, as on a news card's Discuss
        activationHitTestProvider: { sourceView, point in
            var view = sourceView.hitTest(point, with: nil)
            while let current = view, current !== sourceView {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }
    ) { [weak self] _ in
        self?.contextMenuConfigurationProvider?()
    }
    private lazy var moreActionsAccessibilityAction = UIAccessibilityCustomAction(name: lang("More actions")) { [weak self] _ in
        self?.contextMenuInteraction.present()
        return true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headlineAction = nil
        headlinesView.prepareForReuse()
        discussionAction = nil
        contextMenuConfigurationProvider = nil
        onPreferredHeightChanged = nil
        bubbleView.alpha = 1
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The text wraps at the row's width, so lay the row out at that width before measuring it
        bounds.size.width = layoutAttributes.size.width
        layoutIfNeeded()
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    func configure(with digest: ApiAgentV2NewsFeedDigest, isInDigestsView: Bool = false) {
        accessibilityIdentifier = "AgentNewsDigest-\(digest.id)"
        let title = lang("$agent_digest_title")
        titleLabel.text = title
        metaLabel.text = L10n.agentDigestMeta(count: digest.total)
        let time = AgentNewsFeedCardCell.timeText(for: digest.deliveredAt)
        metaView.configure(time: time)
        headerStack.accessibilityLabel = [titleLabel.text, metaLabel.text, time].compactMap { $0 }.joined(separator: ", ")
        let remainder = digest.total - digest.top.count
        // The digests view has no news above the card, so its line only counts the rest
        let remainderText = isInDigestsView
            ? L10n.agentDigestMoreCount(count: remainder)
            : L10n.agentDigestMore(count: remainder)
        headlinesView.configure(
            headlines: digest.top,
            remainder: remainder > 0 ? remainderText : nil,
            date: AgentV2DateParser.date(digest.deliveredAt)
        )
        // The last headline's row already ends with its own room
        footerContainer.directionalLayoutMargins.top = remainder > 0 ? Metrics.remainderTimeSpacing : 0
        discussionStrip.configure(
            title: lang("$agent_news_discuss"),
            accessibilityLabel: "\(lang("$agent_news_discuss")), \(title)",
            accessibilityIdentifier: "AgentNewsDigestDiscussion-\(digest.id)",
            discussion: nil
        )
        accessibilityElements = [headerStack] + headlinesView.headlineButtons
            + (headlinesView.hasRemainder ? [headlinesView.remainderLabel] : []) + [discussionStrip.button]
    }

    func makeFlightSnapshot() -> (view: UIView, frame: CGRect)? {
        guard let window else { return nil }
        let body = bubbleView.bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: AgentBubbleBackgroundView.tailBottomOverflow, right: 0))
        guard let snapshot = bubbleView.resizableSnapshotView(from: body, afterScreenUpdates: false, withCapInsets: .zero) else {
            return nil
        }
        return (snapshot, bubbleView.convert(body, to: window))
    }

    func setFlightSourceHidden(_ isHidden: Bool) {
        bubbleView.alpha = isHidden ? 0 : 1
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addLayoutGuide(contentLayoutGuide)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.configure(direction: .incoming, fillColor: .air.agentBubbleFill, showsTail: true)
        contentView.addSubview(bubbleView)
        contextMenuInteraction.attach(to: bubbleView)

        titleLabel.applyTextStyle(.bodyStrong, scaling: .dynamic)
        titleLabel.numberOfLines = 0
        metaLabel.applyTextStyle(.footnote, scaling: .dynamic)
        metaLabel.numberOfLines = 0
        // The count's gradient runs across the title, so the two lines share its colours where they overlap
        metaLabel.gradientSource = titleLabel
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(metaLabel)
        headerStack.axis = .vertical
        headerStack.spacing = 2
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.insetsLayoutMarginsFromSafeArea = false
        headerStack.directionalLayoutMargins = Metrics.headerInsets
        headerStack.isAccessibilityElement = true
        headerStack.accessibilityTraits = .header
        headerStack.accessibilityCustomActions = [moreActionsAccessibilityAction]

        headlinesContainer.addArrangedSubview(headlinesView)
        headlinesContainer.isLayoutMarginsRelativeArrangement = true
        headlinesContainer.insetsLayoutMarginsFromSafeArea = false
        headlinesContainer.directionalLayoutMargins = Metrics.headlinesInsets

        let footerRow = UIView()
        metaView.translatesAutoresizingMaskIntoConstraints = false
        footerRow.addSubview(metaView)
        NSLayoutConstraint.activate([
            metaView.topAnchor.constraint(equalTo: footerRow.topAnchor),
            metaView.bottomAnchor.constraint(equalTo: footerRow.bottomAnchor),
            metaView.leadingAnchor.constraint(greaterThanOrEqualTo: footerRow.leadingAnchor),
            metaView.trailingAnchor.constraint(equalTo: footerRow.trailingAnchor, constant: -AgentNewsMetaView.trailingInset),
        ])
        footerContainer.addArrangedSubview(footerRow)
        footerContainer.isLayoutMarginsRelativeArrangement = true
        footerContainer.insetsLayoutMarginsFromSafeArea = false
        footerContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: Metrics.horizontalInset, bottom: AgentNewsMetaView.bottomInset, trailing: 0
        )

        discussionStrip.button.addAction(UIAction { [weak self] _ in self?.discussionAction?() }, for: .touchUpInside)

        for view in [headerStack, headlinesContainer, footerContainer, discussionStrip] { stackView.addArrangedSubview(view) }
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        glowView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.contentView.addSubview(glowView)
        bubbleView.contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentLayoutGuide.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            contentLayoutGuide.widthAnchor.constraint(equalTo: contentView.widthAnchor).withPriority(UILayoutPriority(999)),
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset),
            bubbleView.trailingAnchor.constraint(
                equalTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentMessageCellMetrics.incomingTrailingInset
            ),
            stackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor),
            glowView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            glowView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            glowView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            glowView.heightAnchor.constraint(lessThanOrEqualTo: bubbleView.contentView.heightAnchor),
            glowView.heightAnchor.constraint(equalToConstant: Appearance.glowHeight).withPriority(.defaultHigh),
        ])
        isAccessibilityElement = false
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: AgentNewsDigestCardCell, _) in
                cell.onPreferredHeightChanged?()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0) {
            guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
            onPreferredHeightChanged?()
        }
    }
}

/// The Agent's gradient over the top of a digest's card, as over a suggestion's pill, on a light sheen, melting into the
/// card's fill toward its headlines
private final class AgentNewsDigestGlowView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let fadeLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradientLayer.startPoint = .zero
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.locations = AgentNewsDigestCardCell.Appearance.glowLocations
        // Whole at the top, gone by the bottom, eased so that it leaves no edge
        fadeLayer.colors = [1, 0.55, 0].map { UIColor.black.withAlphaComponent($0).cgColor }
        fadeLayer.locations = [0, 0.45, 1]
        layer.mask = fadeLayer
        layer.addSublayer(gradientLayer)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        fadeLayer.frame = bounds
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateColors()
    }

    private func updateColors() {
        backgroundColor = AgentNewsDigestCardCell.Appearance.sheenColor
        gradientLayer.colors = AgentNewsDigestCardCell.Appearance.glowColors.map {
            $0.resolvedColor(with: traitCollection).cgColor
        }
    }
}

/// Text in the suggestions' gradient, which runs across its longest line as across a suggestion's title, at the
/// opacity given for the light and the dark appearance
private final class AgentNewsDigestGradientLabel: UILabel {
    private let lightAlpha: CGFloat
    private let darkAlpha: CGFloat
    /// The label above whose text the gradient runs across instead of this one's, so this line takes its colours at
    /// the same places, as the news count under the digest's title
    weak var gradientSource: AgentNewsDigestGradientLabel? {
        didSet {
            gradientSource?.gradientFollower = self
            setNeedsDisplay()
        }
    }
    private weak var gradientFollower: AgentNewsDigestGradientLabel?

    override var text: String? {
        didSet { gradientFollower?.setNeedsDisplay() }
    }

    override var bounds: CGRect {
        didSet {
            if bounds.size != oldValue.size { gradientFollower?.setNeedsDisplay() }
        }
    }

    init(lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            super.drawText(in: rect)
            return
        }
        let alpha = traitCollection.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
        let colors = AgentSuggestionAppearance.titleGradientColors(for: traitCollection).map {
            $0.copy(alpha: alpha) ?? $0
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: Self.gradientLocations
        ) else {
            super.drawText(in: rect)
            return
        }
        let widthSource = gradientSource ?? self
        let textWidth = widthSource.textRect(
            forBounds: widthSource.bounds, limitedToNumberOfLines: widthSource.numberOfLines
        ).width
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let start = isRightToLeft ? rect.maxX : rect.minX
        let end = start + (isRightToLeft ? -1 : 1) * textWidth * Self.gradientReach
        // The text is drawn as a shape and the gradient fills only that shape
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        super.drawText(in: rect)
        context.setBlendMode(.sourceIn)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: start, y: 0),
            end: CGPoint(x: end, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.endTransparencyLayer()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        setNeedsDisplay()
    }

    /// As `AgentSuggestionAppearance.configureTitleGradient` lays the suggestions' gradient over their titles
    private static let gradientLocations: [CGFloat] = [0, 0.39547, 1]
    private static let gradientReach: CGFloat = 1.28324
}

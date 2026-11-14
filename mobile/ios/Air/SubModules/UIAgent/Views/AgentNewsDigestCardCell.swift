import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// A daily digest of the News feed, in the Agent's tailed bubble as the news cards are: its title, how many news it
/// covers, its top headlines, each opening its news item's discussion, the time it came, and the Discuss strip that
/// opens the digest's own discussion. A long press on the bubble opens its menu, as on a news card.
final class AgentNewsDigestCardCell: UICollectionViewCell, AgentNewsFlightSource {
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
    private let contentLayoutGuide = UILayoutGuide()
    private let stackView = UIStackView()
    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
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
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        metaLabel.applyTextStyle(.footnote, scaling: .dynamic)
        metaLabel.textColor = .air.secondaryLabel
        metaLabel.numberOfLines = 0
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

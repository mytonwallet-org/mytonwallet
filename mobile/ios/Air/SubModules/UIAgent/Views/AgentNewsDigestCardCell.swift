import UIKit
import UIComponents
import WalletContext
import WalletCore

/// A daily digest of the News feed, in the Agent's tailed bubble as the news cards are: its title, how many news it
/// covers and when it came, its top headlines, each opening its news item's discussion, and the Discuss strip that opens
/// the digest's own discussion
final class AgentNewsDigestCardCell: UICollectionViewCell {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16
        static let headerInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16)
        static let headlineMinimumHeight: CGFloat = 44
        static let headlineVerticalInset: CGFloat = 10
        static let bulletSize: CGFloat = 6
        static let bulletSpacing: CGFloat = 10
        static let remainderInsets = NSDirectionalEdgeInsets(
            top: 4,
            leading: horizontalInset + bulletSize + bulletSpacing,
            bottom: 12,
            trailing: horizontalInset
        )
    }

    /// A tap on the headline of the news item with this event ID
    var headlineAction: ((Int) -> Void)?
    var discussionAction: (() -> Void)?
    /// The card's height changed with the text size while it was on screen
    var onPreferredHeightChanged: (() -> Void)?

    let bubbleView = AgentBubbleBackgroundView()
    private let contentLayoutGuide = UILayoutGuide()
    private let stackView = UIStackView()
    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let headlinesStack = UIStackView()
    private let remainderLabel = UILabel()
    private let remainderContainer = UIStackView()
    private let discussionStrip = AgentNewsDiscussionStrip()
    private var headlineButtons: [AgentNewsDimmingButton] = []

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
        discussionAction = nil
        onPreferredHeightChanged = nil
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The text wraps at the row's width, so lay the row out at that width before measuring it
        bounds.size.width = layoutAttributes.size.width
        layoutIfNeeded()
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    func configure(with digest: ApiAgentV2NewsFeedDigest) {
        accessibilityIdentifier = "AgentNewsDigest-\(digest.id)"
        let title = lang("$agent_digest_title")
        titleLabel.text = title
        metaLabel.text = L10n.agentDigestMeta(count: digest.total, time: AgentNewsFeedCardCell.timeText(for: digest.deliveredAt))
        headerStack.accessibilityLabel = [titleLabel.text, metaLabel.text].compactMap { $0 }.joined(separator: ", ")
        configureHeadlines(digest.top)
        let remainder = digest.total - digest.top.count
        remainderLabel.text = remainder > 0 ? L10n.agentDigestMore(count: remainder) : nil
        remainderContainer.isHidden = remainder <= 0
        discussionStrip.configure(
            title: lang("$agent_news_discuss"),
            accessibilityLabel: "\(lang("$agent_news_discuss")), \(title)",
            accessibilityIdentifier: "AgentNewsDigestDiscussion-\(digest.id)",
            discussion: nil
        )
        accessibilityElements = [headerStack] + headlineButtons + (remainder > 0 ? [remainderLabel] : []) + [discussionStrip.button]
    }

    /// One row for each headline, with a separator between rows
    private func configureHeadlines(_ headlines: [ApiAgentV2DigestHeadline]) {
        headlinesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headlineButtons = headlines.enumerated().map { index, headline in
            if index > 0 { headlinesStack.addArrangedSubview(makeSeparator()) }
            let button = makeHeadlineButton(headline)
            headlinesStack.addArrangedSubview(button)
            return button
        }
    }

    private func makeHeadlineButton(_ headline: ApiAgentV2DigestHeadline) -> AgentNewsDimmingButton {
        let bullet = UIView()
        bullet.backgroundColor = .tintColor
        bullet.layer.cornerRadius = Metrics.bulletSize / 2
        bullet.translatesAutoresizingMaskIntoConstraints = false
        let bulletBox = UIView()
        bulletBox.addSubview(bullet)
        let label = UILabel()
        label.applyTextStyle(.body, scaling: .dynamic)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = headline.headline
        let arrow = UIImageView(image: AgentNewsDiscussionStrip.arrowImage)
        arrow.tintColor = .tintColor
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [bulletBox, label, arrow])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Metrics.bulletSpacing
        row.setCustomSpacing(0, after: label)
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false

        let button = AgentNewsDimmingButton()
        button.addSubview(row)
        button.highlightedContentView = row
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.accessibilityLabel = headline.headline
        button.accessibilityIdentifier = "AgentNewsDigestHeadline-\(headline.eventId)"
        button.addAction(UIAction { [weak self] _ in self?.headlineAction?(headline.eventId) }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            bulletBox.widthAnchor.constraint(equalToConstant: Metrics.bulletSize),
            bullet.widthAnchor.constraint(equalToConstant: Metrics.bulletSize),
            bullet.heightAnchor.constraint(equalToConstant: Metrics.bulletSize),
            bullet.centerXAnchor.constraint(equalTo: bulletBox.centerXAnchor),
            // The bullet stands by the headline's first line
            bullet.centerYAnchor.constraint(equalTo: label.firstBaselineAnchor, constant: -label.font.xHeight / 2),
            bulletBox.heightAnchor.constraint(equalTo: row.heightAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.headlineMinimumHeight),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            row.topAnchor.constraint(equalTo: button.topAnchor, constant: Metrics.headlineVerticalInset),
            row.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -Metrics.headlineVerticalInset),
        ])
        return button
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .air.separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addLayoutGuide(contentLayoutGuide)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.configure(direction: .incoming, fillColor: .air.agentBubbleFill, showsTail: true)
        contentView.addSubview(bubbleView)

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

        headlinesStack.axis = .vertical
        headlinesStack.isLayoutMarginsRelativeArrangement = true
        headlinesStack.insetsLayoutMarginsFromSafeArea = false
        headlinesStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: Metrics.horizontalInset, bottom: 0, trailing: Metrics.horizontalInset
        )

        remainderLabel.applyTextStyle(.subheadline, scaling: .dynamic)
        remainderLabel.textColor = .air.secondaryLabel
        remainderLabel.numberOfLines = 0
        remainderContainer.addArrangedSubview(remainderLabel)
        remainderContainer.isLayoutMarginsRelativeArrangement = true
        remainderContainer.insetsLayoutMarginsFromSafeArea = false
        remainderContainer.directionalLayoutMargins = Metrics.remainderInsets

        discussionStrip.button.addAction(UIAction { [weak self] _ in self?.discussionAction?() }, for: .touchUpInside)

        for view in [headerStack, headlinesStack, remainderContainer, discussionStrip] { stackView.addArrangedSubview(view) }
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

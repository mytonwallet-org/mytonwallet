import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The strip under a card that opens its discussion, laid out like Telegram's comments button under a channel post: a
/// 30 pt avatar 13 pt from the edge, the title 11 pt after it, with 8 pt above and below the avatar
enum AgentNewsDiscussionMetrics {
    static let minimumHeight: CGFloat = 46
    static let leadingInset: CGFloat = 13
    static let avatarSize: CGFloat = 30
    static let iconSpacing: CGFloat = 11
    /// The arrow's 24 pt box ends this far from the card's trailing edge and starts right after the title
    static let arrowTrailingInset: CGFloat = 9
    static let arrowSpacing: CGFloat = 1
    static let arrowBoxSize = CGSize(width: 24, height: 24)
    /// The content is centered 1 pt above the strip's middle
    static let verticalOffset: CGFloat = -1
    static let minimumVerticalInset: CGFloat = 7
}

/// A news item of the News feed: the post the item's discussion starts with, ended by Telegram's comments strip that
/// opens the discussion
final class AgentNewsFeedCardCell: UICollectionViewCell, AgentNewsFlightSource {
    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)? {
        get { newsView.contextMenuConfigurationProvider }
        set { newsView.contextMenuConfigurationProvider = newValue }
    }
    var onPreferredHeightChanged: (() -> Void)? {
        get { newsView.onPreferredHeightChanged }
        set { newsView.onPreferredHeightChanged = newValue }
    }
    var openSourceAction: (() -> Void)? {
        get { newsView.openSourceAction }
        set { newsView.openSourceAction = newValue }
    }
    var onPictureTap: ((UIImageView) -> Void)? {
        get { newsView.onPictureTap }
        set { newsView.onPictureTap = newValue }
    }
    var discussionAction: (() -> Void)?

    let newsView = AgentNewsPostView()
    private let contentLayoutGuide = UILayoutGuide()
    private let discussionStrip = AgentNewsDiscussionStrip()

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
        newsView.prepareForReuse()
        discussionAction = nil
    }

    override func layoutSubviews() {
        newsView.updateTextMaxWidth(forBubbleWidth: AgentNewsPostCell.getBubbleWidth(forRowWidth: bounds.width))
        super.layoutSubviews()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The text wraps at the row's width, so lay the row out at that width before measuring it
        bounds.size.width = layoutAttributes.size.width
        newsView.updateTextMaxWidth(forBubbleWidth: AgentNewsPostCell.getBubbleWidth(forRowWidth: layoutAttributes.size.width))
        layoutIfNeeded()
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    /// `isDiscussionStarted`: the user has written in the item's discussion, which only then is continued
    func configure(with item: ApiAgentV2NewsFeedItem, isDiscussionStarted: Bool = true) {
        newsView.configure(with: Self.makeContent(for: item), isHeaderVisible: false)
        accessibilityIdentifier = "AgentNewsCard-\(item.eventId)"
        configureDiscussion(with: item, isStarted: isDiscussionStarted)
    }

    private func configureDiscussion(with item: ApiAgentV2NewsFeedItem, isStarted: Bool) {
        let discussion = isStarted ? item.discussion : nil
        discussionStrip.configure(
            title: lang(discussion != nil ? "$agent_news_continue_discussion" : "$agent_news_discuss"),
            accessibilityLabel: discussion != nil
                ? L10n.agentNewsContinueDiscussionAccessibility(headline: item.headline)
                : "\(lang("$agent_news_discuss")), \(item.headline)",
            accessibilityIdentifier: "AgentNewsDiscussion-\(item.eventId)",
            discussion: discussion
        )
    }

    func makeFlightSnapshot() -> (view: UIView, frame: CGRect)? {
        newsView.makeFlightSnapshot()
    }

    func setFlightSourceHidden(_ isHidden: Bool) {
        newsView.alpha = isHidden ? 0 : 1
    }

    @objc private func openDiscussion() {
        discussionAction?()
    }

    /// What the card shows of `item`: its time alone, whatever its date, under the day capsule that gives the date
    static func makeContent(for item: ApiAgentV2NewsFeedItem) -> AgentNewsPostView.Content {
        AgentNewsPostView.Content(item: item, time: timeText(for: item.deliveredAt))
    }

    /// The card's time, on the device's 12- or 24-hour clock as a chat's date lines show it
    static func timeText(
        for timestamp: String,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = LocalizationSupport.shared.locale,
        hourCycle: Locale.HourCycle = Locale.autoupdatingCurrent.hourCycle
    ) -> String {
        BaseAgentModel.formattedTime(
            AgentV2DateParser.date(timestamp),
            locale: locale,
            hourCycle: hourCycle,
            timeZone: timeZone
        )
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addLayoutGuide(contentLayoutGuide)
        contentView.addSubview(newsView)

        discussionStrip.button.addTarget(self, action: #selector(openDiscussion), for: .touchUpInside)
        newsView.setFooter(discussionStrip)

        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentLayoutGuide.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            contentLayoutGuide.widthAnchor.constraint(equalTo: contentView.widthAnchor).withPriority(UILayoutPriority(999)),
            newsView.topAnchor.constraint(equalTo: contentView.topAnchor),
            newsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            newsView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset),
            newsView.trailingAnchor.constraint(
                equalTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentMessageCellMetrics.incomingTrailingInset
            ),
        ])
        isAccessibilityElement = false
        accessibilityElements = [newsView.accessibilityContentElement, discussionStrip.button]
    }
}

/// Telegram's comments strip under a feed card, which opens its discussion: a separator over a button with the
/// discussion's icon, its title and a disclosure arrow
final class AgentNewsDiscussionStrip: UIStackView {
    /// Telegram's disclosure arrow: a 2 pt chevron in a 24 pt box
    static let arrowImage = AgentGlyph.makeImage(
        size: AgentNewsDiscussionMetrics.arrowBoxSize,
        lineWidth: 2,
        strokes: [[CGPoint(x: 10, y: 7), CGPoint(x: 15, y: 12), CGPoint(x: 10, y: 17)]]
    ).imageFlippedForRightToLeftLayoutDirection()

    let button = AgentNewsDimmingButton()
    private let iconView = UIView()
    private let avatarView = AgentThreadAvatarView()
    /// The Agent's mark in the accent color, like the button's title
    private let topView = UIImageView(image: AgentSpinningTopIcon.makeTemplateImage(size: 26))
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A `discussion` the user has written in shows its thread's avatar, the same as in the thread list; without one
    /// the strip shows the Agent's mark
    func configure(
        title: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        discussion: ApiAgentV2NewsFeedItem.Discussion?
    ) {
        label.text = title
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        if let discussion {
            avatarView.configure(seed: discussion.threadId, emoji: discussion.icon)
        }
        avatarView.isHidden = discussion == nil
        topView.isHidden = discussion != nil
    }

    private func configureViews() {
        let separator = UIView()
        separator.backgroundColor = .air.separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        label.applyTextStyle(.body, scaling: .dynamic)
        label.textColor = .tintColor
        label.numberOfLines = 0
        let arrow = UIImageView(image: Self.arrowImage)
        arrow.tintColor = .tintColor
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [avatarView, topView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            iconView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: iconView.trailingAnchor),
                view.topAnchor.constraint(equalTo: iconView.topAnchor),
                view.bottomAnchor.constraint(equalTo: iconView.bottomAnchor),
            ])
        }
        // The mark keeps its own size inside the avatar's box, as Telegram's comment icon does
        topView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: AgentNewsDiscussionMetrics.avatarSize),
            iconView.heightAnchor.constraint(equalToConstant: AgentNewsDiscussionMetrics.avatarSize),
        ])
        let row = UIStackView(arrangedSubviews: [iconView, label, arrow])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AgentNewsDiscussionMetrics.iconSpacing
        row.setCustomSpacing(AgentNewsDiscussionMetrics.arrowSpacing, after: label)
        row.isUserInteractionEnabled = false
        row.accessibilityElementsHidden = true
        button.addSubview(row)
        button.highlightedContentView = row
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: AgentNewsDiscussionMetrics.minimumHeight),
            // The strip is as short as its row allows, or a card measured against a taller height would stretch it
            button.heightAnchor.constraint(equalToConstant: AgentNewsDiscussionMetrics.minimumHeight)
                .withPriority(.defaultLow),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: AgentNewsDiscussionMetrics.leadingInset),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -AgentNewsDiscussionMetrics.arrowTrailingInset),
            row.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: AgentNewsDiscussionMetrics.verticalOffset),
            row.topAnchor.constraint(
                greaterThanOrEqualTo: button.topAnchor,
                constant: AgentNewsDiscussionMetrics.minimumVerticalInset
            ),
            row.bottomAnchor.constraint(
                lessThanOrEqualTo: button.bottomAnchor,
                constant: -AgentNewsDiscussionMetrics.minimumVerticalInset
            ),
        ])
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        axis = .vertical
        addArrangedSubview(separator)
        addArrangedSubview(button)
    }
}

/// Dims its content the moment it is pressed and brightens it back over 0.2 s, as Telegram's comments button does
final class AgentNewsDimmingButton: UIButton {
    private static let highlightedAlpha: CGFloat = 0.4
    private static let unhighlightDuration: TimeInterval = 0.2

    weak var highlightedContentView: UIView?

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue, let highlightedContentView else { return }
            highlightedContentView.layer.removeAllAnimations()
            if isHighlighted {
                highlightedContentView.alpha = Self.highlightedAlpha
            } else {
                UIView.animate(withDuration: Self.unhighlightDuration, delay: 0, options: [.allowUserInteraction]) {
                    highlightedContentView.alpha = 1
                }
            }
        }
    }
}

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
final class AgentNewsFeedCardCell: UICollectionViewCell {
    private static let timeFormatter = DateFormatter()
    private static var timeFormattingLocale: Locale?
    private static var timeFormattingCalendar: Calendar?

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
    private let discussionStrip = UIStackView()
    private let discussionButton = AgentNewsDiscussionButton()
    private let discussionIconView = UIView()
    private let discussionAvatarView = AgentThreadAvatarView()
    /// The Agent's mark in the accent color, like the button's title
    private let discussionTopView = UIImageView(image: AgentSpinningTopIcon.makeTemplateImage(size: 26))
    private let discussionLabel = UILabel()

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
        let hasDiscussion = item.discussion != nil && isStarted
        discussionLabel.text = lang(hasDiscussion ? "$agent_news_continue_discussion" : "$agent_news_discuss")
        discussionButton.accessibilityLabel = hasDiscussion
            ? L10n.agentNewsContinueDiscussionAccessibility(headline: item.headline)
            : "\(lang("$agent_news_discuss")), \(item.headline)"
        discussionButton.accessibilityIdentifier = "AgentNewsDiscussion-\(item.eventId)"
        // A discussion shows its thread's avatar, the same as in the thread list; a new one the Agent's mark
        if hasDiscussion, let discussion = item.discussion {
            discussionAvatarView.configure(seed: discussion.threadId, emoji: discussion.icon)
        }
        discussionAvatarView.isHidden = !hasDiscussion
        discussionTopView.isHidden = hasDiscussion
    }

    /// A picture of the card and its frame in the window, for the post that flies into the new discussion. The picture
    /// leaves out the card's tail, which the post shows as the card lands on it.
    func makeFlightSnapshot() -> (view: UIView, frame: CGRect)? {
        newsView.makeFlightSnapshot()
    }

    /// Hides the card while its picture flies into the new discussion, so the feed does not show it twice
    func setFlightSourceHidden(_ isHidden: Bool) {
        newsView.alpha = isHidden ? 0 : 1
    }

    /// Telegram's disclosure arrow: a 2 pt chevron in a 24 pt box
    private static let discussionArrowImage = AgentGlyph.makeImage(
        size: AgentNewsDiscussionMetrics.arrowBoxSize,
        lineWidth: 2,
        strokes: [[CGPoint(x: 10, y: 7), CGPoint(x: 15, y: 12), CGPoint(x: 10, y: 17)]]
    ).imageFlippedForRightToLeftLayoutDirection()

    @objc private func openDiscussion() {
        discussionAction?()
    }

    /// What the card shows of `item`: its time alone, under the day line that gives its date
    static func makeContent(for item: ApiAgentV2NewsFeedItem) -> AgentNewsPostView.Content {
        AgentNewsPostView.Content(item: item, time: timeText(for: item.deliveredAt))
    }

    static func timeText(
        for timestamp: String,
        calendar: Calendar = .current,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        if timeFormattingLocale != locale || timeFormattingCalendar != calendar {
            timeFormatter.calendar = calendar
            timeFormatter.locale = locale
            timeFormatter.timeZone = calendar.timeZone
            timeFormatter.setLocalizedDateFormatFromTemplate("jmm")
            timeFormattingLocale = locale
            timeFormattingCalendar = calendar
        }
        return timeFormatter.string(from: AgentV2DateParser.date(timestamp))
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addLayoutGuide(contentLayoutGuide)
        contentView.addSubview(newsView)

        let separator = UIView()
        separator.backgroundColor = .air.separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        discussionButton.addTarget(self, action: #selector(openDiscussion), for: .touchUpInside)
        discussionLabel.applyTextStyle(.body, scaling: .dynamic)
        discussionLabel.textColor = .tintColor
        discussionLabel.numberOfLines = 0
        let arrow = UIImageView(image: Self.discussionArrowImage)
        arrow.tintColor = .tintColor
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [discussionAvatarView, discussionTopView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            discussionIconView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: discussionIconView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: discussionIconView.trailingAnchor),
                view.topAnchor.constraint(equalTo: discussionIconView.topAnchor),
                view.bottomAnchor.constraint(equalTo: discussionIconView.bottomAnchor),
            ])
        }
        // The mark keeps its own size inside the avatar's box, as Telegram's comment icon does
        discussionTopView.contentMode = .center
        discussionIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            discussionIconView.widthAnchor.constraint(equalToConstant: AgentNewsDiscussionMetrics.avatarSize),
            discussionIconView.heightAnchor.constraint(equalToConstant: AgentNewsDiscussionMetrics.avatarSize),
        ])
        let discussionRow = UIStackView(arrangedSubviews: [discussionIconView, discussionLabel, arrow])
        discussionRow.translatesAutoresizingMaskIntoConstraints = false
        discussionRow.axis = .horizontal
        discussionRow.alignment = .center
        discussionRow.spacing = AgentNewsDiscussionMetrics.iconSpacing
        discussionRow.setCustomSpacing(AgentNewsDiscussionMetrics.arrowSpacing, after: discussionLabel)
        discussionRow.isUserInteractionEnabled = false
        discussionRow.accessibilityElementsHidden = true
        discussionButton.addSubview(discussionRow)
        discussionButton.highlightedContentView = discussionRow
        NSLayoutConstraint.activate([
            discussionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AgentNewsDiscussionMetrics.minimumHeight),
            // The strip is as short as its row allows, or a card measured against a taller height would stretch it
            discussionButton.heightAnchor.constraint(equalToConstant: AgentNewsDiscussionMetrics.minimumHeight)
                .withPriority(.defaultLow),
            discussionRow.leadingAnchor.constraint(equalTo: discussionButton.leadingAnchor, constant: AgentNewsDiscussionMetrics.leadingInset),
            discussionRow.trailingAnchor.constraint(equalTo: discussionButton.trailingAnchor, constant: -AgentNewsDiscussionMetrics.arrowTrailingInset),
            discussionRow.centerYAnchor.constraint(equalTo: discussionButton.centerYAnchor, constant: AgentNewsDiscussionMetrics.verticalOffset),
            discussionRow.topAnchor.constraint(
                greaterThanOrEqualTo: discussionButton.topAnchor,
                constant: AgentNewsDiscussionMetrics.minimumVerticalInset
            ),
            discussionRow.bottomAnchor.constraint(
                lessThanOrEqualTo: discussionButton.bottomAnchor,
                constant: -AgentNewsDiscussionMetrics.minimumVerticalInset
            ),
        ])
        discussionStrip.axis = .vertical
        discussionStrip.addArrangedSubview(separator)
        discussionStrip.addArrangedSubview(discussionButton)
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
        discussionButton.isAccessibilityElement = true
        discussionButton.accessibilityTraits = .button
        accessibilityElements = [newsView.accessibilityContentElement, discussionButton]
    }
}

/// Dims its content the moment it is pressed and brightens it back over 0.2 s, as Telegram's comments button does
private final class AgentNewsDiscussionButton: UIButton {
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

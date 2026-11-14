import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The news post a discussion starts with: the feed's post headed by "News", with the discussion's follow-ups under it
final class AgentNewsPostCell: UICollectionViewCell, AgentContextMenuPresentingCell {
    private enum Metrics {
        /// As News' cards
        static let leadingInset: CGFloat = AgentMessageCellMetrics.horizontalInset
        static let trailingInset: CGFloat = AgentMessageCellMetrics.incomingTrailingInset
    }

    /// How long the suggestions may take before placeholders stand in for them. Suggestions that come sooner come in
    /// on their own, without placeholders flashing up just before them.
    static let followupPlaceholderDelay: TimeInterval = 1

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
    var onDigestHeadlineTap: ((Int) -> Void)? {
        get { newsView.onDigestHeadlineTap }
        set { newsView.onDigestHeadlineTap = newValue }
    }
    var onFollowupTap: ((String) -> Void)?

    var contextMenuCopyText: String? {
        newsView.content?.copyText
    }

    let newsView = AgentNewsPostView()
    private let contentLayoutGuide = UILayoutGuide()
    private let followupView = AgentFollowupView()

    /// The suggestion of `controlID` under the post, which turns into the question's bubble once tapped
    func getFollowupButton(controlID: String) -> AgentSuggestionButton? {
        followupView.getButton(controlID: controlID)
    }
    private var followupConstraints: [NSLayoutConstraint] = []
    private var followupTitles: [String] = []
    private var isLoadingFollowups = false
    private var followupsExpired = false
    private var followupsTimeout: DispatchWorkItem?
    /// Shows the placeholders once the suggestions have taken `followupPlaceholderDelay`
    private var followupPlaceholderTimer: DispatchWorkItem?
    private var arePlaceholdersDue = false
    private var hasConfiguredFollowups = false
    private lazy var newsBottomConstraint = newsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)

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
        followupsTimeout?.cancel()
        followupsTimeout = nil
        followupsExpired = false
        followupPlaceholderTimer?.cancel()
        followupPlaceholderTimer = nil
        arePlaceholdersDue = false
        newsView.prepareForReuse()
        onFollowupTap = nil
        contentView.alpha = 1
        hasConfiguredFollowups = false
        configureFollowups([])
        hasConfiguredFollowups = false
    }

    override func layoutSubviews() {
        updateTextMaxWidths(forRowWidth: bounds.width)
        super.layoutSubviews()
        updateFollowupMaxWidth()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The headline, the body and the suggestions wrap at the row's width, so lay the row out at that width
        // before measuring it: measured at its natural width, a two-line headline would get one line's height
        bounds.size.width = layoutAttributes.size.width
        updateTextMaxWidths(forRowWidth: layoutAttributes.size.width)
        layoutIfNeeded()
        updateFollowupMaxWidth()
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    /// The width the post's bubble has in a row `width` wide
    static func getBubbleWidth(forRowWidth width: CGFloat) -> CGFloat {
        min(width, AgentContentLayout.maxContentWidth) - Metrics.leadingInset - Metrics.trailingInset
    }

    private func updateTextMaxWidths(forRowWidth width: CGFloat) {
        newsView.updateTextMaxWidth(forBubbleWidth: Self.getBubbleWidth(forRowWidth: width))
    }

    /// The post as it appears in the chat, for a transition that flies the post in from the news feed
    var postView: UIView { newsView.bubbleView }

    /// How far the post's tail hangs below the bubble's body
    var postTailOverflow: CGFloat { newsView.tailOverflow }

    /// The suggestions appear under the post as under an answer, once a card flown in from the news feed lands on it
    func revealFollowups() {
        followupView.animateAppearance()
    }

    /// A copy of `post` that flies in its place has a tail when the post has one
    func matchTail(of post: AgentNewsPostCell) {
        newsView.setHasTail(post.newsView.hasTail, shouldAnimate: false)
    }

    func configure(with news: ApiAgentV2ThreadNewsCard) {
        configure(with: AgentNewsPostView.Content(news: news))
    }

    /// A news post or a digest's
    func configure(with content: AgentNewsPostView.Content) {
        newsView.configure(with: content, isHeaderVisible: true)
    }

    /// Topical suggestions under the post. They scroll with it, without the Agent's mark above them, and hang from it as
    /// from an answer.
    ///
    /// While they load, placeholders stand in for them, but only once they have taken `followupPlaceholderDelay`.
    func configureFollowups(_ controls: [AgentMessageControl], isLoading: Bool = false) {
        let followups = controls.filter { $0.kind == .followup }
        let isWaiting = isLoading && followups.isEmpty && !followupsExpired
        schedulePlaceholders(isWaiting: isWaiting)
        let shouldLoad = isWaiting && arePlaceholdersDue
        let titles = followups.map(\.title)
        let isShownHeightChanging = hasConfiguredFollowups && (titles != followupTitles || shouldLoad != isLoadingFollowups)
        isLoadingFollowups = shouldLoad
        followupTitles = titles
        hasConfiguredFollowups = true
        let hasFollowups = !followups.isEmpty || shouldLoad
        if isWaiting, followupsTimeout == nil {
            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.followupsExpired = true
                self.configureFollowups([])
            }
            followupsTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
        }
        if shouldLoad {
            followupView.showLoading()
        } else {
            if !isWaiting {
                followupsTimeout?.cancel()
                followupsTimeout = nil
            }
            followupView.configure(controls: followups, isVisible: hasFollowups, animatesAppearance: isShownHeightChanging) { [weak self] id in
                self?.onFollowupTap?(id)
            }
        }
        newsView.setHasTail(!hasFollowups, shouldAnimate: isShownHeightChanging)
        newsBottomConstraint.isActive = !hasFollowups
        if hasFollowups {
            NSLayoutConstraint.activate(followupConstraints)
        } else {
            NSLayoutConstraint.deactivate(followupConstraints)
        }
        updateFollowupMaxWidth()
        // Follow-ups that arrive for a post already on screen change its row's height, which the chat measures again
        guard isShownHeightChanging else { return }
        invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.newsView.content != nil else { return }
            self.contentView.setNeedsLayout()
            self.onPreferredHeightChanged?()
        }
    }

    /// Starts the placeholders' delay as the suggestions start loading, and drops it once they stop: suggestions that
    /// arrive, a failure or a post no longer waiting for them never get placeholders
    private func schedulePlaceholders(isWaiting: Bool) {
        guard isWaiting else {
            followupPlaceholderTimer?.cancel()
            followupPlaceholderTimer = nil
            arePlaceholdersDue = false
            return
        }
        guard followupPlaceholderTimer == nil, !arePlaceholdersDue else { return }
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.followupPlaceholderTimer = nil
            self.arePlaceholdersDue = true
            self.configureFollowups([], isLoading: true)
            // The placeholders come in as the suggestions do, one by one out of a blur
            self.followupView.animateAppearance()
        }
        followupPlaceholderTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.followupPlaceholderDelay, execute: timer)
    }

    /// Whether placeholders stand in for the suggestions, which the chat's tests watch
    var showsFollowupPlaceholders: Bool { isLoadingFollowups }

    /// Long suggestions wrap within the column instead of being cut off
    private func updateFollowupMaxWidth() {
        guard contentLayoutGuide.layoutFrame.width > 2 * AgentMessageCellMetrics.followupHorizontalInset else { return }
        followupView.updateMaxWidth()
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addLayoutGuide(contentLayoutGuide)
        contentView.addSubview(newsView)

        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentLayoutGuide.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            contentLayoutGuide.widthAnchor.constraint(equalTo: contentView.widthAnchor).withPriority(UILayoutPriority(999)),
            newsView.topAnchor.constraint(equalTo: contentView.topAnchor),
            newsBottomConstraint,
            newsView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: Metrics.leadingInset),
            newsView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -Metrics.trailingInset),
        ])
        followupConstraints = followupView.install(
            in: contentView,
            below: newsView,
            contentLayoutGuide: contentLayoutGuide
        )
        // Suggestions that come for a post on screen hang below the row until the chat measures it again, rather than
        // squeezing the post into the row's old height for a frame
        followupConstraints.first { $0.firstAttribute == .bottom }?.priority = UILayoutPriority(999)
        isAccessibilityElement = false
        accessibilityElements = [newsView.accessibilityContentElement, followupView]
    }
}

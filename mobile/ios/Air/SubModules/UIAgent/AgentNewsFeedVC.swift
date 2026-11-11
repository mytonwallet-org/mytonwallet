import ContextMenuKit
import Perception
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public final class AgentNewsFeedVC: WViewController, WalletCoreData.EventsObserver {
    /// Telegram's stuck date header (`ListView.updateHeaderItemsFlashing`, `ChatMessageDateHeaderNodeImpl`): it shows
    /// while the list is dragged or decelerates from a drag and for 0.3 s after, fading in over 0.3 s and out over
    /// 0.4 s, and stays while it stands less than half a header from its own place
    private enum StickyDayMetrics {
        static let holdDuration: TimeInterval = 0.3
        static let fadeInDuration: TimeInterval = 0.3
        static let fadeOutDuration: TimeInterval = 0.4
        static let hidingDistanceFactor: CGFloat = 0.5
        static let headerHeight = AgentDateCapsuleView.height + 2 * AgentDateCapsuleView.verticalSpacing
    }

    /// Older news load as the user scrolls up with at most this many rows, day lines and the "New" line among them,
    /// wholly above the part of the feed under the header, as Android's `AGENT_HISTORY_LOAD_THRESHOLD` counts them
    static let loadOlderRowThreshold = 5

    enum ItemID: Hashable {
        case day(Date)
        case unread
        case news(Int)
        case digest(String)
        /// The chat's failure line with Retry, after the news shown when the feed failed to refresh
        case failure
    }

    private let model: AgentNewsFeedModel
    private let preloader: AgentPreloader
    private let openInBrowser: (URL) -> Void
    private let openTelegramURL: (URL) -> Void
    private let showLinkError: (DisplayError) -> Void
    private let makeNewsChatViewController: (ApiAgentV2NewsFeedItem, String, @escaping (ApiAgentV2ThreadSummary) -> Void) -> UIViewController
    /// The discussion of a news item the feed hasn't loaded, from a digest's headline
    private let loadNewsChatViewController: (Int) async throws -> UIViewController
    /// The discussion of the digest with this ID, which it starts on its first visit
    private let makeDigestChatViewController: (String) -> UIViewController
    private let presentDigestSettings: (UIViewController) -> Void
    private let titleView = AgentChatTitleView()
    /// The chat's column: as wide as the screen up to the content's maximum width, centred
    private let contentLayoutGuide = UILayoutGuide()
    /// Where a chat's field rests above the bottom edge. The feed has no field, so what a chat keeps above its field the
    /// feed keeps above this line: the latest news and the scroll button.
    private let fieldLineGuide = UILayoutGuide()
    private lazy var fieldLineConstraint = fieldLineGuide.topAnchor.constraint(equalTo: view.bottomAnchor)
    private var navigationBarBackground: UIView?
    /// Stands in for the feed until its first page loads
    private let skeletonView = AgentMessagesSkeletonView(style: .newsCards)
    private let backSwipe = AgentChatBackSwipe()
    /// The card whose picture flies into a new discussion, hidden until the feed is off screen
    private weak var flightSourceCell: AgentNewsFeedCardCell?
    /// Clips the stuck day capsule at the header's edge, which it slides under as the next day's capsule pushes it up
    private let stickyDayContainer = UIView()
    /// The capsule of the day at the feed's top, stuck under the header while that day's news scroll under it
    let stickyDayCapsule = AgentDateCapsuleView(isBlurred: true)
    private lazy var stickyDayTopConstraint = stickyDayCapsule.topAnchor.constraint(equalTo: stickyDayContainer.topAnchor)
    /// The day whose capsule stands stuck under the header, which its own row in the list leaves to it
    private var stuckDay: Date?
    /// How far the stuck capsule stands from its own place in the list, in date headers, as Telegram measures it
    private var stuckDayDistanceFactor: CGFloat = 0
    /// The feed's days, oldest first
    private var days: [Date] = []
    private var isDraggingList = false
    private var isDeceleratingAfterDrag = false
    /// The list's offset at its last scroll, which tells which way it moves
    private var lastContentOffsetY: CGFloat = 0
    /// Keeps the stuck capsule shown a moment after the list stops
    private var stickyDayHold: DispatchWorkItem?
    /// Rows that take their own heights as they come into view move the capsules in the list without a scroll
    private var contentSizeObservation: NSKeyValueObservation?
    /// The failure with Retry for a feed that has nothing to show, or its message when it loaded without news
    private let loadErrorView = AgentLoadErrorView()
    let scrollToBottomButton = AgentScrollToBottomButton()
    let collectionView: AgentCollectionView = {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(180))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        // A chat's rows: as far apart and as far under the header
        section.interGroupSpacing = AgentVCLayout.rowSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: AgentVCLayout.sectionTopInset, leading: 0, bottom: 0, trailing: 0)
        return AgentCollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
    }()
    lazy var listScrollAnimator = AgentListScrollAnimator(collectionView: collectionView)
    private var dataSource: UICollectionViewDiffableDataSource<Int, ItemID>!
    private var itemsById: [Int: ApiAgentV2NewsFeedItem] = [:]
    /// The news the rows were last configured with
    private var previousItemsById: [Int: ApiAgentV2NewsFeedItem] = [:]
    private var digestsById: [String: ApiAgentV2NewsFeedDigest] = [:]
    private var previousDigestsById: [String: ApiAgentV2NewsFeedDigest] = [:]
    /// The feed was opened for a digest it hasn't shown yet, and the user hasn't scrolled it since
    private var isSeekingRequestedDigest: Bool
    /// When each day's first news came, which its date line's menu shows as a chat's shows its first message's time
    private var dayStarts: [Date: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var hasPerformedInitialScroll = false
    private var isApplyingSnapshot = false
    /// A card's height changed while a snapshot was being applied
    private var needsCardMeasure = false
    private var needsSnapshotUpdate = false
    private var isRestoringPosition = false
    private var lastKnownNearBottom = true
    private var isVisible = false
    private var isOpeningDiscussion = false
    private var retainedDiscussion: AgentV2Model?

    init(
        model: AgentNewsFeedModel,
        preloader: AgentPreloader = .shared,
        openInBrowser: @escaping (URL) -> Void = { AppActions.openInBrowser($0, title: nil, injectDappConnect: false) },
        openTelegramURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) },
        showLinkError: @escaping (DisplayError) -> Void = { AppActions.showError(error: $0) },
        makeNewsChatViewController: ((ApiAgentV2NewsFeedItem, String, @escaping (ApiAgentV2ThreadSummary) -> Void) -> UIViewController)? = nil,
        loadNewsChatViewController: ((Int) async throws -> UIViewController)? = nil,
        makeDigestChatViewController: ((String) -> UIViewController)? = nil,
        presentDigestSettings: @escaping (UIViewController) -> Void = { AgentDigestSettingsSheetVC.present(over: $0) }
    ) {
        self.model = model
        // The discussions open over the feed, as a news card's do, so Back returns to it
        self.loadNewsChatViewController = loadNewsChatViewController ?? {
            try await AgentEntryPoint.makeNewsChatViewController(eventId: $0, client: LiveAgentNewsFeedClient(), preloader: preloader)
        }
        self.makeDigestChatViewController = makeDigestChatViewController ?? {
            AgentVC(model: preloader.acquireDigestModel(id: $0))
        }
        self.presentDigestSettings = presentDigestSettings
        isSeekingRequestedDigest = model.requestedDigestId != nil
        self.preloader = preloader
        self.openInBrowser = openInBrowser
        self.openTelegramURL = openTelegramURL
        self.showLinkError = showLinkError
        self.makeNewsChatViewController = makeNewsChatViewController ?? {
            AgentEntryPoint.makeNewsChatViewController(item: $0, locale: $1, preloader: preloader, onThreadCreated: $2)
        }
        super.init(nibName: nil, bundle: nil)
        title = lang("News")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTask?.cancel()
        paginationTask?.cancel()
        if let retainedDiscussion {
            Task { @MainActor in retainedDiscussion.releasePresentation() }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        configureDataSource()
        contentSizeObservation = collectionView.observe(\.contentSize) { [weak self] _, _ in
            MainActor.assumeIsolated {
                // A snapshot being applied places the capsule once it is in
                guard let self, !self.isApplyingSnapshot else { return }
                self.updateStickyDay()
            }
        }
        model.onChange = { [weak self] in self?.updateFeed() }
        observeDigestHour()
        WalletCoreData.addImmediately(eventObserver: self)
        for name in [UIApplication.significantTimeChangeNotification, NSLocale.currentLocaleDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(reconfigureDayLines), name: name, object: nil)
        }
        updateFeed()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        restoreFlightSource()
        reconfigureDiscussions()
        refresh()
        AgentChatHeaderMorph.runIfNeeded(for: self, isAppearing: true)
    }

    /// A new digest hour, set in the bell's sheet or anywhere else, brings that hour's digests; a hidden feed takes them
    /// as it appears again, when it refreshes
    private func observeDigestHour() {
        withPerceptionTracking {
            _ = model.digestSettings.digestHour
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.isVisible { self.refresh() }
                self.observeDigestHour()
            }
        }
    }

    /// Coming back from a discussion, its card says "Continue discussion" once the user has written there
    private func reconfigureDiscussions() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        let ids = snapshot.itemIdentifiers.filter { id in
            guard case .news(let eventId) = id else { return false }
            return itemsById[eventId]?.discussion != nil
        }
        guard !ids.isEmpty else { return }
        snapshot.reconfigureItems(ids)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in self?.updateCardLayout() }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        fieldLineConstraint.constant = -fieldBottomInset
        view.setNeedsLayout()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBottomInset()
        updateStickyDay()
    }

    /// How far above the bottom edge a chat's field rests, which is where the line under the feed stands
    private var fieldBottomInset: CGFloat {
        AgentComposerMetrics.getFieldBottomInset(safeAreaBottom: view.safeAreaInsets.bottom)
    }

    /// The latest news ends as far above the line as a chat's latest message ends above its field. The space is the
    /// list's inset, as a chat's under its latest message, so a scroll to the latest news rests where the list ends.
    private func updateBottomInset() {
        let target = fieldBottomInset + AgentVCLayout.bottomMessageSpacing
        let baseline = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let inset = max(0, target - baseline)
        guard abs(collectionView.contentInset.bottom - inset) > 0.5 else { return }
        let wasNearBottom = hasPerformedInitialScroll && lastKnownNearBottom
        collectionView.contentInset.bottom = inset
        collectionView.verticalScrollIndicatorInsets.bottom = target - baseline
        if wasNearBottom {
            revealLastItemSettlingRowHeights()
        }
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        AgentChatNavigation.installThreadsButton(in: self)
        installDigestSettingsButton()
        performInitialScrollIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AgentChatHeaderMorph.runIfNeeded(for: self, isAppearing: false)
        backSwipe.restore()
        isVisible = false
        refreshTask?.cancel()
        refreshTask = nil
        paginationTask?.cancel()
        paginationTask = nil
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOpeningDiscussion = false
        backSwipe.install(for: self)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        restoreFlightSource()
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .agentThreadDeleted(let threadId):
            if retainedDiscussion?.threadId == threadId {
                releaseDiscussion()
            }
            model.removeDiscussion(threadId: threadId)
        case .accountsReset:
            releaseDiscussion()
        case .applicationWillEnterForeground where isVisible:
            refresh()
        default:
            break
        }
    }

    /// A tap on the current tab goes to the latest news, as in a chat
    public override func scrollToTop(animated: Bool) {
        isSeekingRequestedDigest = false
        scrollToLatest(animated: animated)
    }

    private func configureViews() {
        view.backgroundColor = .air.background
        titleView.setTitle(lang("News"), icon: nil, animated: false)
        view.addLayoutGuide(contentLayoutGuide)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addLayoutGuide(fieldLineGuide)
        fieldLineConstraint.constant = -fieldBottomInset
        // A card's discussion button lights up the moment it is touched, as Telegram's comments button does
        collectionView.delaysContentTouches = false
        // Clear, so the skeleton fades under the cards, as a chat's under its messages
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "AgentNewsFeed"
        view.addSubview(collectionView)
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        // The lowest placeholder ends where the latest card's body will
        skeletonView.bottomInset = AgentVCLayout.bottomMessageSpacing + AgentBubbleBackgroundView.tailBottomOverflow
        skeletonView.isHidden = !model.entries.isEmpty
        view.insertSubview(skeletonView, belowSubview: collectionView)
        if #available(iOS 26.0, *) {
            collectionView.bottomEdgeEffect.isHidden = true
        }
        navigationBarBackground = AgentChatNavigation.installHeader(in: self, titleView: titleView, scrollView: collectionView)
        // Above the header's backdrop, whose fade would dim the stuck capsule, and below the navigation bar's buttons
        stickyDayContainer.translatesAutoresizingMaskIntoConstraints = false
        stickyDayContainer.isUserInteractionEnabled = false
        stickyDayContainer.clipsToBounds = true
        stickyDayContainer.accessibilityElementsHidden = true
        stickyDayCapsule.alpha = 0
        stickyDayContainer.addSubview(stickyDayCapsule)
        view.insertSubview(stickyDayContainer, aboveSubview: navigationBarBackground ?? collectionView)
        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.accessibilityIdentifier = "AgentNewsScrollToBottom"
        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomButtonPressed), for: .touchUpInside)
        view.addSubview(scrollToBottomButton)
        let contentWidth = contentLayoutGuide.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        contentWidth.priority = UILayoutPriority(999)

        loadErrorView.onRetry = { [weak self] in self?.refresh() }
        loadErrorView.install(in: view, column: contentLayoutGuide, centerY: collectionView.centerYAnchor)

        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: view.topAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: fieldLineGuide.topAnchor),
            fieldLineConstraint,
            fieldLineGuide.heightAnchor.constraint(equalToConstant: 0),
            fieldLineGuide.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            fieldLineGuide.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            contentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentLayoutGuide.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            contentLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor),
            contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            contentWidth,
            // The list is as wide as a chat's, so it scrolls beside the column too, as on an iPad
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            // On the trailing edge of a chat's microphone circle, where a chat's scroll button stands
            scrollToBottomButton.trailingAnchor.constraint(
                equalTo: contentLayoutGuide.trailingAnchor,
                constant: -AgentComposerMetrics.threadHorizontalInset
            ),
            scrollToBottomButton.bottomAnchor.constraint(
                equalTo: fieldLineGuide.topAnchor,
                constant: -AgentVCLayout.scrollToBottomButtonSpacing
            ),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: AgentScrollToBottomButton.size),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: AgentScrollToBottomButton.size),
            // The list's area under the header, where a stuck capsule shows
            stickyDayContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stickyDayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stickyDayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stickyDayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stickyDayTopConstraint,
            // Centred in the column, as the capsules in the list are
            stickyDayCapsule.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            stickyDayCapsule.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor,
                constant: AgentDateCapsuleView.minimumColumnInset
            ),
        ])
    }

    private func configureDataSource() {
        let cardRegistration = UICollectionView.CellRegistration<AgentNewsFeedCardCell, Int> { [weak self] cell, _, id in
            guard let self, let item = self.itemsById[id], let locale = self.model.locale else { return }
            cell.configure(with: item, isDiscussionStarted: self.isDiscussionStarted(for: item))
            cell.contextMenuConfigurationProvider = { [weak self, weak cell] in
                self?.makeContextMenu(for: item, sourceView: cell)
            }
            cell.onPreferredHeightChanged = { [weak self] in self?.updateCardLayout() }
            cell.openSourceAction = { [weak self] in self?.openSource($0) }
            cell.onPictureTap = { [weak self] _ in self?.openPicture(eventId: id) }
            cell.discussionAction = { [weak self] in self?.openDiscussion(eventId: id, locale: locale) }
        }
        let digestRegistration = UICollectionView.CellRegistration<AgentNewsDigestCardCell, String> { [weak self] cell, _, id in
            guard let self, let digest = self.digestsById[id] else { return }
            cell.configure(with: digest)
            cell.onPreferredHeightChanged = { [weak self] in self?.updateCardLayout() }
            cell.headlineAction = { [weak self] eventId in self?.openHeadline(eventId: eventId) }
            cell.discussionAction = { [weak self] in self?.openDigestDiscussion(id: id) }
        }
        // Telegram's date capsule, one for each day
        let dayRegistration = UICollectionView.CellRegistration<AgentSystemMessageCell, Date> { [weak self] cell, _, day in
            guard let self else { return }
            let line = self.makeDayLine(for: day)
            cell.configure(with: line)
            cell.setDayCapsuleHidden(day == self.stuckDay)
            cell.accessibilityIdentifier = "AgentNewsDate"
            cell.contextMenuConfigurationProvider = { [weak self, weak cell] in
                guard let self, let text = cell?.contextMenuCopyText else { return nil }
                return self.makeLineMenu(for: line, copyText: text)
            }
        }
        let failureRegistration = UICollectionView.CellRegistration<AgentSystemMessageCell, ItemID> { [weak self] cell, _, _ in
            guard let self else { return }
            let line = self.makeFailureLine()
            cell.configure(with: line) { [weak self] _ in self?.refresh() }
            cell.contextMenuConfigurationProvider = { [weak self, weak cell] in
                guard let self, let text = cell?.contextMenuCopyText else { return nil }
                return self.makeLineMenu(for: line, copyText: text)
            }
        }
        let unreadRegistration = UICollectionView.CellRegistration<AgentUnreadDividerCell, ItemID> { cell, _, _ in
            cell.accessibilityIdentifier = "AgentNewsUnreadDivider"
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collection, indexPath, id in
            switch id {
            case .news(let eventId):
                return collection.dequeueConfiguredReusableCell(using: cardRegistration, for: indexPath, item: eventId)
            case .digest(let id):
                return collection.dequeueConfiguredReusableCell(using: digestRegistration, for: indexPath, item: id)
            case .day(let day):
                return collection.dequeueConfiguredReusableCell(using: dayRegistration, for: indexPath, item: day)
            case .unread:
                return collection.dequeueConfiguredReusableCell(using: unreadRegistration, for: indexPath, item: id)
            case .failure:
                return collection.dequeueConfiguredReusableCell(using: failureRegistration, for: indexPath, item: id)
            }
        }
    }

    private func makeDayLine(for day: Date) -> AgentMessage {
        AgentMessage(
            role: .system,
            text: AgentThreadDateFormatting.formatDay(for: day),
            isStreaming: false,
            systemStyle: .day,
            timestamp: dayStarts[day] ?? day
        )
    }

    /// The failure as a chat shows it, with Retry as a link after the text
    private func makeFailureLine() -> AgentMessage {
        AgentMessage(
            role: .assistant,
            text: model.error.map(Self.errorText) ?? "",
            isStreaming: false,
            controls: [AgentMessageControl(id: "retry-load", title: lang("Retry"), isEnabled: !model.isLoading)],
            renderingPolicy: .agentV2Safe,
            systemStyle: .failure
        )
    }

    /// A chat's menu of a date line or a failure line: Copy, centred under the line
    private func makeLineMenu(for line: AgentMessage, copyText: String) -> ContextMenuConfiguration? {
        let items = AgentMessageMenuItems.makeItems(
            for: line,
            copyText: copyText,
            canEdit: false,
            canRegenerate: false,
            canReportProblem: false,
            edit: {},
            regenerate: {},
            reportProblem: {}
        )
        guard !items.isEmpty else { return nil }
        return AgentMessageMenu.makeConfiguration(
            items: items,
            date: line.timestamp,
            isOutgoing: false,
            isCentered: true,
            contentAreaInWindow: getVisibleCardsRectInWindow()
        )
    }

    /// "Today" turns into "Yesterday" at midnight, and the capsules follow the language, as a chat's date lines do
    @objc private func reconfigureDayLines() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        let dayIDs = snapshot.itemIdentifiers.filter { id in
            if case .day = id { return true }
            return false
        }
        if let stuckDay {
            stickyDayCapsule.text = AgentThreadDateFormatting.formatDay(for: stuckDay)
        }
        guard !dayIDs.isEmpty else { return }
        snapshot.reconfigureItems(dayIDs)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await model.refresh()
        }
    }

    @objc func scrollToBottomButtonPressed() {
        // A scroll the user asks for is never taken over by the scroll to the requested digest
        isSeekingRequestedDigest = false
        scrollToLatest(animated: true)
    }

    private func updateFeed() {
        // Each visible placeholder becomes a card in the same ordered column.
        let entries = model.entries
        let isRevealingFromSkeleton = !skeletonView.isHidden && !entries.isEmpty && view.window != nil
            && dataSource.snapshot().numberOfItems == 0 && !UIAccessibility.isReduceMotionEnabled
        skeletonView.setVisible(entries.isEmpty && model.error == nil && !model.hasLoaded,
                                animated: !isRevealingFromSkeleton && view.window != nil)
        // With news to show, a failure is the chat's failure line under them
        if !entries.isEmpty {
            loadErrorView.show(nil)
        } else if let error = model.error {
            loadErrorView.show(Self.errorText(error))
        } else {
            loadErrorView.showMessage(model.hasLoaded ? lang("$agent_news_empty") : nil)
        }
        guard !isApplyingSnapshot else {
            needsSnapshotUpdate = true
            return
        }

        let anchor = hasPerformedInitialScroll ? paginationAnchor() : nil
        let stickToBottom = hasPerformedInitialScroll && lastKnownNearBottom && paginationTask == nil && !model.isLoadingMore
        itemsById = Dictionary(uniqueKeysWithValues: model.items.map { ($0.eventId, $0) })
        digestsById = Dictionary(uniqueKeysWithValues: model.digests.map { ($0.id, $0) })
        var ids: [ItemID] = []
        var previousDay: Date?
        let previousDayStarts = dayStarts
        dayStarts = [:]
        days = []
        for entry in entries {
            let deliveredAt = AgentV2DateParser.date(entry.deliveredAt)
            let day = LocalizationSupport.shared.calendar.startOfDay(for: deliveredAt)
            if previousDay != day {
                ids.append(.day(day))
                dayStarts[day] = deliveredAt
                days.append(day)
                previousDay = day
            }
            switch entry {
            case .news(let item):
                if item.eventId == model.unreadEventId { ids.append(.unread) }
                ids.append(.news(item.eventId))
            case .digest(let digest):
                ids.append(.digest(digest.id))
            }
        }
        if model.error != nil, !entries.isEmpty {
            ids.append(.failure)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, ItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        // Only the rows whose news changed are configured again, as a chat reconfigures only the messages that change
        let previousIds = Set(dataSource.snapshot().itemIdentifiers)
        let reconfiguredIds = ids.filter { id in
            guard previousIds.contains(id) else { return false }
            switch id {
            case .news(let eventId):
                return previousItemsById[eventId] != itemsById[eventId]
            case .digest(let id):
                return previousDigestsById[id] != digestsById[id]
            case .failure:
                return true
            case .day(let day):
                return previousDayStarts[day] != dayStarts[day]
            case .unread:
                return false
            }
        }
        snapshot.reconfigureItems(reconfiguredIds)
        previousItemsById = itemsById
        previousDigestsById = digestsById
        isApplyingSnapshot = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            self.collectionView.layoutIfNeeded()
            // Cards configured again in place, and those whose picture gave way meanwhile, are measured again
            if !reconfiguredIds.isEmpty || self.needsCardMeasure {
                self.needsCardMeasure = false
                self.measureRowsAgain()
                self.collectionView.layoutIfNeeded()
            }
            if !self.hasPerformedInitialScroll {
                self.performInitialScrollIfNeeded()
                if isRevealingFromSkeleton {
                    self.revealCardsFromSkeleton()
                }
            } else if !self.revealRequestedDigestIfNeeded() {
                if stickToBottom {
                    self.revealLastItemSettlingRowHeights()
                } else if let anchor {
                    self.restoreAnchor(anchor)
                }
            }
            self.updateNearBottomState()
            self.updateStickyDay()
            if self.needsSnapshotUpdate {
                self.needsSnapshotUpdate = false
                self.updateFeed()
            }
            self.loadRequestedDigestIfNeeded()
        }
        // Older news are in the list once the snapshot is applied, above the card on screen. The card is kept in place
        // in the same update, so the list never draws them pushing it down before the snapshot's completion.
        if hasPerformedInitialScroll, !stickToBottom, let anchor {
            restoreAnchor(anchor)
            updateStickyDay()
        }
    }

    /// Scrolls once to the digest the feed was opened for, once its card is in the feed
    private func revealRequestedDigestIfNeeded() -> Bool {
        guard isSeekingRequestedDigest, let id = model.requestedDigestId,
              let indexPath = dataSource.indexPath(for: .digest(id)) else { return false }
        isSeekingRequestedDigest = false
        revealItemAtTop(indexPath)
        return true
    }

    /// Loads older pages, one after another, until the requested digest comes, the feed runs out of pages or reaches
    /// back past the digest; then the feed stays where it is
    private func loadRequestedDigestIfNeeded() {
        guard isSeekingRequestedDigest, hasPerformedInitialScroll, paginationTask == nil,
              model.hasLoaded, !model.isLoading, !model.isLoadingMore else { return }
        guard model.canLoadRequestedDigest else {
            // A digest that came is revealed as its card goes into the feed
            if !model.digests.contains(where: { $0.id == model.requestedDigestId }) {
                isSeekingRequestedDigest = false
            }
            return
        }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            let cursor = model.nextCursor
            await model.loadMore()
            paginationTask = nil
            // A page that failed to load ends the search rather than asking for it again and again
            guard !Task.isCancelled, model.nextCursor != cursor else {
                if !Task.isCancelled { isSeekingRequestedDigest = false }
                return
            }
            loadRequestedDigestIfNeeded()
        }
    }

    private func revealCardsFromSkeleton() {
        AgentSkeletonReveal.revealRows(in: collectionView, isRightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                                      placeholders: skeletonView.placeholdersInWindow()) { cell, _ in
            cell is AgentNewsFeedCardCell || cell is AgentNewsDigestCardCell ? .bubble(isOutgoing: false) : .line
        }
    }

    /// Opens at the first unread news or at the latest one. Cached news is applied before the feed is on screen, so
    /// this waits until the feed has its size and insets in the window.
    private func performInitialScrollIfNeeded() {
        guard !hasPerformedInitialScroll, !isApplyingSnapshot, collectionView.window != nil,
              !dataSource.snapshot().itemIdentifiers.isEmpty else { return }
        hasPerformedInitialScroll = true
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        // A requested digest already in the feed opens it there, otherwise it opens as usual while older pages load
        if !revealRequestedDigestIfNeeded() {
            if let divider = dataSource.indexPath(for: .unread) {
                revealItemAtTop(divider)
            } else {
                revealLastItemSettlingRowHeights()
            }
        }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    /// Keeps the card a chat's way, without the feed's reaction to scrolling while it does
    private func restoreAnchor(_ anchor: AgentListAnchor<ItemID>) {
        isRestoringPosition = true
        defer { isRestoringPosition = false }
        restorePaginationAnchor(anchor)
    }

    /// Measures the cards on screen again and gives the list their new heights, as a chat measures a row it changes in
    /// place. UIKit measures a card as it first shows it, not when the feed configures it again in place or its picture
    /// gives way, and invalidating the layout would measure every row from the estimate again, those off screen too.
    private func measureRowsAgain() {
        let layout = collectionView.collectionViewLayout
        for cell in collectionView.visibleCells where cell is AgentNewsFeedCardCell || cell is AgentNewsDigestCardCell {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let original = layout.layoutAttributesForItem(at: indexPath),
                  let preferred = original.copy() as? UICollectionViewLayoutAttributes else { continue }
            // Lays the card out at its row's width, which its text wraps at
            _ = cell.preferredLayoutAttributesFitting(preferred)
            preferred.size.height = cell.systemLayoutSizeFitting(
                CGSize(width: original.size.width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            guard abs(preferred.size.height - original.size.height) > 0.5 else { continue }
            layout.invalidateLayout(with: layout.invalidationContext(
                forPreferredLayoutAttributes: preferred,
                withOriginalAttributes: original
            ))
        }
    }

    private func updateCardLayout() {
        // A snapshot being applied measures the cards once it is in
        guard !isApplyingSnapshot else {
            needsCardMeasure = true
            return
        }
        let anchor = paginationAnchor()
        let wasAtBottom = lastKnownNearBottom
        measureRowsAgain()
        collectionView.layoutIfNeeded()
        if wasAtBottom {
            revealLastItemSettlingRowHeights()
        } else if let anchor {
            restoreAnchor(anchor)
        }
        updateNearBottomState()
        updateStickyDay()
    }

    /// Checks again whether the latest news is in reach and shows or hides the scroll button by it, as a chat does
    /// after it applies its rows. Rows can change without a scroll, and the scroll that keeps a row in place runs no
    /// such check.
    private func updateNearBottomState() {
        guard hasPerformedInitialScroll else { return }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    /// Keeps the capsule of the day at the feed's top stuck under the header while that day's news scroll under it, and
    /// lets the next day's capsule push it up and out, as a Telegram chat does with its date headers. Telegram's 34 pt
    /// header is the capsule with 6 pt above and below it, which the list's rows also leave around a capsule.
    private func updateStickyDay() {
        guard hasPerformedInitialScroll, stickyDayContainer.bounds.height > 0, dataSource != nil else {
            setStuckDay(nil)
            return
        }
        let containerTop = collectionView.convert(stickyDayContainer.bounds.origin, from: stickyDayContainer).y
        let stickY = containerTop + AgentDateCapsuleView.verticalSpacing
        let firstDayBelowIndex = findFirstDayIndex(atOrBelow: stickY)
        var stuck: (day: Date, minY: CGFloat)?
        for index in (0..<firstDayBelowIndex).reversed() {
            guard let minY = getDayCapsuleMinY(at: index) else { continue }
            stuck = (days[index], minY)
            break
        }
        let nextDayMinY = (firstDayBelowIndex..<days.count).lazy.compactMap(getDayCapsuleMinY(at:)).first
        guard let stuck,
              let lastIndexPath = lastItemIndexPath,
              let lastFrame = collectionView.layoutAttributesForItem(at: lastIndexPath)?.frame else {
            setStuckDay(nil)
            return
        }
        // The day's rows end a row's spacing above the next day's capsule, or with the feed
        let dayEndY = nextDayMinY.map { $0 - AgentVCLayout.rowSpacing } ?? lastFrame.maxY
        let capsuleHeight = stickyDayCapsule.bounds.height > 0 ? stickyDayCapsule.bounds.height : AgentDateCapsuleView.height
        let capsuleY = min(stickY, dayEndY - AgentDateCapsuleView.verticalSpacing - capsuleHeight)
        let topConstant = capsuleY - containerTop
        if abs(stickyDayTopConstraint.constant - topConstant) > 0.01 {
            stickyDayTopConstraint.constant = topConstant
        }
        stuckDayDistanceFactor = min(1, max(0, (capsuleY - stuck.minY) / StickyDayMetrics.headerHeight))
        setStuckDay(stuck.day)
    }

    /// The index of the first day whose row starts at `y` or below, found by halves, as the days' rows stand in the
    /// order of `days`. A day the layout has no row for is passed over.
    private func findFirstDayIndex(atOrBelow y: CGFloat) -> Int {
        var lowerBound = 0
        var upperBound = days.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            guard let found = findDayCapsuleMinY(in: middle..<upperBound) else {
                upperBound = middle
                continue
            }
            if found.minY < y {
                lowerBound = found.index + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func findDayCapsuleMinY(in indices: Range<Int>) -> (index: Int, minY: CGFloat)? {
        for index in indices {
            if let minY = getDayCapsuleMinY(at: index) {
                return (index, minY)
            }
        }
        return nil
    }

    private func getDayCapsuleMinY(at index: Int) -> CGFloat? {
        guard let indexPath = dataSource.indexPath(for: .day(days[index])) else { return nil }
        return collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY
    }

    private func setStuckDay(_ day: Date?) {
        guard day != stuckDay else {
            updateStickyDayVisibility(animated: true)
            return
        }
        if let stuckDay {
            setDayCapsuleHidden(false, for: stuckDay)
        }
        if let day {
            setDayCapsuleHidden(true, for: day)
        }
        stuckDay = day
        if let day {
            stickyDayCapsule.text = AgentThreadDateFormatting.formatDay(for: day)
        }
        // The stuck capsule takes the place of the row's at once, as Telegram's header is one view that sticks
        updateStickyDayVisibility(animated: false)
    }

    private func setDayCapsuleHidden(_ isHidden: Bool, for day: Date) {
        guard let indexPath = dataSource.indexPath(for: .day(day)),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentSystemMessageCell else { return }
        cell.setDayCapsuleHidden(isHidden)
    }

    /// A stuck capsule shows while the user scrolls and a moment after, and while it stands within half a header of its
    /// own place; otherwise it fades away and leaves the news clear
    private func updateStickyDayVisibility(animated: Bool) {
        let isScrolledByUser = isDraggingList || isDeceleratingAfterDrag || stickyDayHold != nil
        let isShown = stuckDay != nil
            && (isScrolledByUser || stuckDayDistanceFactor < StickyDayMetrics.hidingDistanceFactor)
        let alpha: CGFloat = isShown ? 1 : 0
        guard stickyDayCapsule.alpha != alpha else { return }
        guard animated else {
            stickyDayCapsule.layer.removeAllAnimations()
            stickyDayCapsule.alpha = alpha
            return
        }
        UIView.animate(
            withDuration: isShown ? StickyDayMetrics.fadeInDuration : StickyDayMetrics.fadeOutDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]
        ) {
            self.stickyDayCapsule.alpha = alpha
        }
    }

    /// Keeps the stuck capsule shown for Telegram's moment after the list stops, then lets it fade
    private func holdStickyDay() {
        stickyDayHold?.cancel()
        let hold = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stickyDayHold = nil
            self.updateStickyDayVisibility(animated: true)
        }
        stickyDayHold = hold
        DispatchQueue.main.asyncAfter(deadline: .now() + StickyDayMetrics.holdDuration, execute: hold)
    }

    private func openDiscussion(eventId: Int, locale: String) {
        guard !isOpeningDiscussion, let navigationController,
              let item = model.items.first(where: { $0.eventId == eventId }) else { return }
        isOpeningDiscussion = true
        let thread = item.discussion.flatMap { findDiscussionThread(threadId: $0.threadId) }
        let controller: UIViewController
        if let thread {
            guard let discussion = preloader.acquireModel(thread: thread, news: (item, locale)) else {
                isOpeningDiscussion = false
                return
            }
            retainDiscussion(discussion)
            controller = AgentVC(model: discussion)
        } else {
            controller = makeNewsChatViewController(item, locale) { [weak self] thread in
                guard let self else { return }
                self.model.markDiscussion(eventId: eventId, thread: thread)
                self.retainDiscussion(thread: thread)
            }
            if let discussion = preloader.newsModel(eventId: eventId) {
                retainDiscussion(discussion)
            }
        }
        if !isDiscussionStarted(for: item), let agentVC = controller as? AgentVC,
           let indexPath = dataSource.indexPath(for: .news(eventId)),
           let cell = collectionView.cellForItem(at: indexPath) as? AgentNewsFeedCardCell,
           let window = view.window,
           let flight = cell.makeFlightSnapshot(),
           agentVC.prepareNewsPostArrival(
               snapshot: flight.view,
               from: flight.frame,
               contentTop: collectionView.getContentTopInWindow(),
               in: window,
               navigationHost: navigationController,
               sourceHeaderBackground: navigationBarBackground
           ) {
            // A discussion the user hasn't written in yet starts with the news as the Agent's post, also when its thread
            // was made on an earlier visit; the card flies into that place
            cell.setFlightSourceHidden(true)
            flightSourceCell = cell
        }
        push(controller)
    }

    /// Pushes a chat the feed opens. The opening stays held until the feed appears again; a push the navigation turns
    /// down, as during another transition, releases it at once, so the tap can be repeated.
    private func push(_ controller: UIViewController) {
        guard let navigationController else {
            isOpeningDiscussion = false
            return
        }
        navigationController.pushViewController(controller, animated: true)
        if navigationController.topViewController !== controller {
            isOpeningDiscussion = false
        }
    }

    /// Opens the digest's discussion in the feed, as a news item's: its thread once it has one with messages, otherwise a
    /// new visit that starts it
    private func openDigestDiscussion(id: String) {
        guard !isOpeningDiscussion, navigationController != nil, let digest = digestsById[id] else { return }
        isOpeningDiscussion = true
        guard let thread = digest.discussion.flatMap({ findDiscussionThread(threadId: $0.threadId) }),
              let discussion = preloader.acquireModel(thread: thread) else {
            push(makeDigestChatViewController(id))
            return
        }
        retainDiscussion(discussion)
        push(AgentVC(model: discussion))
    }

    /// The thread of a discussion with messages in it, which opens as it is; nil for one to open as a new visit
    private func findDiscussionThread(threadId: String) -> ApiAgentV2ThreadSummary? {
        if let discussion = preloader.model(threadId: threadId) {
            return discussion.hasMessages || discussion.hasActiveRun ? discussion.thread : nil
        }
        guard let summary = model.findThread(threadId), summary.messageCount > 0 else { return nil }
        return summary
    }

    /// Opens a digest headline's news item over the feed: as its card does when the feed has it, otherwise once the
    /// item's discussion loads
    private func openHeadline(eventId: Int) {
        if let locale = model.locale, model.items.contains(where: { $0.eventId == eventId }) {
            openDiscussion(eventId: eventId, locale: locale)
            return
        }
        guard !isOpeningDiscussion else { return }
        isOpeningDiscussion = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let controller = try await loadNewsChatViewController(eventId)
                guard view.window != nil else {
                    isOpeningDiscussion = false
                    return
                }
                push(controller)
            } catch {
                isOpeningDiscussion = false
                if !(error is CancellationError) { AppActions.showError(error: error) }
            }
        }
    }

    /// The bell in the header's trailing slot, which opens the digest and notifications sheet
    private func installDigestSettingsButton() {
        guard navigationItem.rightBarButtonItem == nil else { return }
        navigationItem.rightBarButtonItem = AgentChatNavigation.makeDigestSettingsItem(primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.presentDigestSettings(self)
        })
    }

    /// A news item's discussion counts once the user has written in it, by the SDK's shared rule: opening it creates
    /// the thread with only the post, its one message, and backing out leaves the card's "Discuss" as it was. A message
    /// sent in the discussion counts at once, before the chat list loads its thread again.
    private func isDiscussionStarted(for item: ApiAgentV2NewsFeedItem) -> Bool {
        guard let threadId = item.discussion?.threadId else { return false }
        if let discussion = preloader.model(threadId: threadId), discussion.isStarted { return true }
        return model.findThread(threadId)?.isStarted == true
    }

    private func restoreFlightSource() {
        flightSourceCell?.setFlightSourceHidden(false)
        flightSourceCell = nil
    }

    private func retainDiscussion(thread: ApiAgentV2ThreadSummary) {
        guard let discussion = preloader.acquireModel(thread: thread) else { return }
        retainDiscussion(discussion)
    }

    private func retainDiscussion(_ discussion: AgentV2Model) {
        guard retainedDiscussion !== discussion else { return }
        releaseDiscussion()
        discussion.retainPresentation()
        retainedDiscussion = discussion
        let onStop = discussion.onStop
        discussion.onStop = { [weak self, weak discussion] in
            onStop?()
            guard let self, let discussion, self.retainedDiscussion === discussion else { return }
            self.releaseDiscussion()
        }
    }

    private func releaseDiscussion() {
        let discussion = retainedDiscussion
        retainedDiscussion = nil
        discussion?.releasePresentation()
    }

    /// The menu of the post in the item's discussion
    private func makeContextMenu(for item: ApiAgentV2NewsFeedItem, sourceView: UIView?) -> ContextMenuConfiguration {
        let items = AgentMessageMenuItems.makeItems(for: AgentNewsFeedCardCell.makeContent(for: item), openSource: { [weak self] in
            self?.openSource(item.sources.first?.url)
        }, share: { [weak self, weak sourceView] text in
            self?.share(text, sourceView: sourceView)
        })
        return AgentMessageMenu.makeConfiguration(
            items: items,
            date: AgentV2DateParser.date(item.deliveredAt),
            isOutgoing: false,
            contentAreaInWindow: getVisibleCardsRectInWindow()
        )
    }

    /// The feed between its header and its bottom edge, or the scroll button over it, in the window's coordinates, as
    /// a chat's menu keeps the pressed message clear of its scroll button
    private func getVisibleCardsRectInWindow() -> CGRect? {
        var bottom = collectionView.bounds.maxY - occlusionBottomInset
        if scrollToBottomButton.isButtonVisible, !scrollToBottomButton.isHidden {
            bottom = min(bottom, collectionView.convert(scrollToBottomButton.bounds, from: scrollToBottomButton).minY)
        }
        return AgentMessageMenu.getVisibleArea(of: collectionView, bottom: bottom)
    }

    /// Opens the feed's pictures in the media viewer at the one of `eventId`, in the feed's order, as the web does
    private func openPicture(eventId: Int) {
        guard let window = view.window else { return }
        let items = model.items.filter { $0.imageUrl.flatMap(URL.init(string:)) != nil }
        guard let index = items.firstIndex(where: { $0.eventId == eventId }) else { return }
        let posts = items.map { item in
            AgentNewsPictureViewer.Post(
                content: AgentNewsFeedCardCell.makeContent(for: item),
                date: AgentV2DateParser.date(item.deliveredAt),
                image: getPictureView(eventId: item.eventId)?.image
            )
        }
        AgentNewsPictureViewer.present(posts: posts, index: index, in: window, openSource: { [weak self] index in
            self?.openSource(items[index].sources.first?.url)
        }, source: { [weak self] index in
            self?.getPictureView(eventId: items[index].eventId)
        })
    }

    /// The picture of the card of `eventId` while the card shows it on screen
    private func getPictureView(eventId: Int) -> UIImageView? {
        guard let indexPath = dataSource.indexPath(for: .news(eventId)),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentNewsFeedCardCell else { return nil }
        let imageView = cell.newsView.imageView
        return imageView.isHidden || imageView.image == nil ? nil : imageView
    }

    private func openSource(_ rawURL: String?) {
        AgentTextLinks.openNewsSource(
            rawURL,
            openInBrowser: openInBrowser,
            openTelegramURL: openTelegramURL,
            showLinkError: showLinkError
        )
    }

    private func share(_ text: String, sourceView: UIView?) {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        presentActivityViewController(controller, sourceView: sourceView)
    }

    static func copyText(for item: ApiAgentV2NewsFeedItem) -> String {
        AgentNewsFeedCardCell.makeContent(for: item).copyText
    }

    static func errorText(_ error: Error) -> String {
        if (error as? ApiAgentV2MutationError)?.code == .newsUnavailable
            || (error as? SdkError)?.backendMessage == "news_unavailable" {
            return lang("$agent_news_unavailable")
        }
        return lang("$agent_error_generic")
    }
}

extension AgentNewsFeedVC: WBackSwipeControlling {
    /// The swipe back follows a chat's rule
    public func shouldAllowBackSwipe(at point: CGPoint) -> Bool {
        AgentChatBackSwipe.shouldAllowBackSwipe(in: view, at: point)
    }
}

extension AgentNewsFeedVC: AgentChatNavigationHandoff {
    public var navigationHandoffLeadingView: UIView? {
        AgentChatNavigation.findCircle(in: navigationItem.leftBarButtonItem)
    }

    public var navigationHandoffTrailingView: UIView? {
        AgentChatNavigation.findCircle(in: navigationItem.rightBarButtonItem)
    }

    public func setNavigationHandoffHidden(_ isHidden: Bool) {
        AgentChatNavigation.setButtonsHidden(isHidden, in: navigationItem)
    }
}

extension AgentNewsFeedVC: AgentChatListScrolling {
    var lastItemIndexPath: IndexPath? {
        guard collectionView.numberOfSections > 0 else { return nil }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        return itemCount > 0 ? IndexPath(item: itemCount - 1, section: 0) : nil
    }

    var occlusionBottomInset: CGFloat {
        collectionView.adjustedContentInset.bottom
    }

    var headingContentOffsetY: CGFloat {
        collectionView.contentOffset.y
    }

    /// The button waits for the feed to open where it opens
    var isScrollToBottomButtonHeld: Bool {
        !hasPerformedInitialScroll
    }

    func listDidEndScrollingToLatest() {
        lastKnownNearBottom = isNearBottom()
    }

    /// The feed keeps its cards in place rather than its date lines
    func getAnchorItemID(at indexPath: IndexPath) -> ItemID? {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .news(let eventId): .news(eventId)
        case .digest(let id): .digest(id)
        default: nil
        }
    }

    func getIndexPath(forAnchorItemID itemID: ItemID) -> IndexPath? {
        dataSource.indexPath(for: itemID)
    }
}

extension AgentNewsFeedVC: UICollectionViewDelegate {
    public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        isSeekingRequestedDigest = false
        return true
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // The user's own scroll is never taken over by the scroll to the requested digest
        isSeekingRequestedDigest = false
        collectionView.isScrollingToLatest = false
        listScrollAnimator.stop()
        stickyDayHold?.cancel()
        stickyDayHold = nil
        isDraggingList = true
        isDeceleratingAfterDrag = false
        updateStickyDayVisibility(animated: true)
        loadOlderNewsIfNeeded()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isDraggingList = false
        isDeceleratingAfterDrag = decelerate
        guard !decelerate else { return }
        holdStickyDay()
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if isDeceleratingAfterDrag {
            isDeceleratingAfterDrag = false
            holdStickyDay()
        }
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateScrollToBottomButtonVisibility(animated: true)
    }

    /// A day's row prefetched before its day stuck or came unstuck shows its capsule as the stuck day now asks
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard case .day(let day) = dataSource.itemIdentifier(for: indexPath),
              let cell = cell as? AgentSystemMessageCell else { return }
        cell.setDayCapsuleHidden(day == stuckDay)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let isMovingUp = scrollView.contentOffset.y < lastContentOffsetY
        lastContentOffsetY = scrollView.contentOffset.y
        // A snapshot being applied places the capsule once it is in
        if !isApplyingSnapshot {
            updateStickyDay()
        }
        guard hasPerformedInitialScroll, !isRestoringPosition, !isApplyingSnapshot else { return }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: true)
        if isMovingUp, isDraggingList || isDeceleratingAfterDrag {
            loadOlderNewsIfNeeded()
        }
    }

    /// Loads older news once the first row below the header is `loadOlderRowThreshold` rows from the feed's first one or
    /// closer, as Android does as a drag starts and as the user scrolls up
    private func loadOlderNewsIfNeeded() {
        guard hasPerformedInitialScroll, !isRestoringPosition, !isApplyingSnapshot,
              paginationTask == nil, !model.isLoading, !model.isLoadingMore, model.nextCursor != nil,
              let firstVisibleItem = getFirstVisibleItem(), firstVisibleItem <= Self.loadOlderRowThreshold,
              paginationAnchor() != nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await model.loadMore()
            paginationTask = nil
            // A search for the requested digest waiting for this page goes on from it
            loadRequestedDigestIfNeeded()
        }
    }

    /// The first row that reaches below the header, as Android's `findFirstVisibleItemPosition` finds it. The layout
    /// tells it for the current offset, which the cells on screen follow only at the next layout pass.
    private func getFirstVisibleItem() -> Int? {
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let visibleRect = CGRect(x: 0, y: visibleTop, width: collectionView.bounds.width, height: collectionView.bounds.height)
        return collectionView.collectionViewLayout.layoutAttributesForElements(in: visibleRect)?
            .filter { $0.representedElementCategory == .cell && $0.frame.maxY > visibleTop }
            .map(\.indexPath.item)
            .min()
    }
}

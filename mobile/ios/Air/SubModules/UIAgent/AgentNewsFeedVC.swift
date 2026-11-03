import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public final class AgentNewsFeedVC: WViewController, WalletCoreData.EventsObserver {
    enum ItemID: Hashable {
        case day(Date)
        case unread
        case news(Int)
        /// The chat's failure line with Retry, after the news shown when the feed failed to refresh
        case failure
    }

    private let model: AgentNewsFeedModel
    private let preloader: AgentPreloader
    private let openInBrowser: (URL) -> Void
    private let openTelegramURL: (URL) -> Void
    private let showLinkError: (DisplayError) -> Void
    private let makeNewsChatViewController: (ApiAgentV2NewsFeedItem, String, @escaping (ApiAgentV2ThreadSummary) -> Void) -> UIViewController
    private let titleView = AgentChatTitleView()
    /// The chat's column: as wide as the screen up to the content's maximum width, centred
    private let contentLayoutGuide = UILayoutGuide()
    /// Where a chat's field rests above the bottom edge. The feed has no field, so what a chat keeps above its field the
    /// feed keeps above this line: the latest news, the scroll button and the fade under them.
    private let fieldLineGuide = UILayoutGuide()
    private lazy var fieldLineConstraint = fieldLineGuide.topAnchor.constraint(equalTo: view.bottomAnchor)
    /// The news fade out under the bottom edge as a chat's messages do under its field
    private let bottomEdgeEffectView = EdgeEffectView()
    private var navigationBarBackground: UIView?
    /// Stands in for the feed until its first page loads
    private let skeletonView = AgentMessagesSkeletonView(style: .newsCards)
    private let backSwipe = AgentChatBackSwipe()
    /// The card whose picture flies into a new discussion, hidden until the feed is off screen
    private weak var flightSourceCell: AgentNewsFeedCardCell?
    private let loadingOlderIndicator = AgentLoadingOlderIndicator()
    /// The failure with Retry for a feed that has nothing to show
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
        makeNewsChatViewController: ((ApiAgentV2NewsFeedItem, String, @escaping (ApiAgentV2ThreadSummary) -> Void) -> UIViewController)? = nil
    ) {
        self.model = model
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
        model.onChange = { [weak self] in self?.updateFeed() }
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
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            bottomEdgeEffectView.updateColor(.air.background)
        }
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
        skeletonView.isHidden = !model.items.isEmpty
        view.insertSubview(skeletonView, belowSubview: collectionView)
        if #available(iOS 26.0, *) {
            collectionView.bottomEdgeEffect.isHidden = true
        }
        bottomEdgeEffectView.update(
            content: .air.background,
            blur: true,
            alpha: 0.85,
            edge: .bottom,
            edgeSize: AgentVCLayout.bottomEdgeFadeHeight + 24
        )
        bottomEdgeEffectView.translatesAutoresizingMaskIntoConstraints = false
        bottomEdgeEffectView.isUserInteractionEnabled = false
        view.addSubview(bottomEdgeEffectView)
        navigationBarBackground = AgentChatNavigation.installHeader(in: self, titleView: titleView, scrollView: collectionView)
        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.accessibilityIdentifier = "AgentNewsScrollToBottom"
        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomButtonPressed), for: .touchUpInside)
        view.addSubview(scrollToBottomButton)
        let contentWidth = contentLayoutGuide.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        contentWidth.priority = UILayoutPriority(999)

        loadErrorView.onRetry = { [weak self] in self?.refresh() }
        loadErrorView.install(in: view, column: contentLayoutGuide, centerY: collectionView.centerYAnchor)

        loadingOlderIndicator.install(in: view, column: contentLayoutGuide)
        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: view.topAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: fieldLineGuide.topAnchor),
            fieldLineConstraint,
            fieldLineGuide.heightAnchor.constraint(equalToConstant: 0),
            fieldLineGuide.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            fieldLineGuide.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            bottomEdgeEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomEdgeEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomEdgeEffectView.topAnchor.constraint(equalTo: fieldLineGuide.topAnchor, constant: -AgentVCLayout.bottomEdgeFadeHeight),
            bottomEdgeEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            cell.openSourceAction = { [weak self] in self?.openSource(for: item) }
            cell.onPictureTap = { [weak self] _ in self?.openPicture(eventId: id) }
            cell.discussionAction = { [weak self] in self?.openDiscussion(eventId: id, locale: locale) }
        }
        // A chat's date line, one for each day
        let dayRegistration = UICollectionView.CellRegistration<AgentSystemMessageCell, Date> { [weak self] cell, _, day in
            guard let self else { return }
            let line = self.makeDayLine(for: day)
            cell.configure(with: line)
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
            text: AgentThreadDateFormatting.headerText(for: day),
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

    /// "Today" turns into "Yesterday" at midnight, and the lines follow the language, as a chat's date lines do
    @objc private func reconfigureDayLines() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        let days = snapshot.itemIdentifiers.filter { id in
            if case .day = id { return true }
            return false
        }
        guard !days.isEmpty else { return }
        snapshot.reconfigureItems(days)
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
        scrollToLatest(animated: true)
    }

    private func updateFeed() {
        // Each visible placeholder becomes a card in the same ordered column.
        let isRevealingFromSkeleton = !skeletonView.isHidden && !model.items.isEmpty && view.window != nil
            && dataSource.snapshot().numberOfItems == 0 && !UIAccessibility.isReduceMotionEnabled
        skeletonView.setVisible(model.items.isEmpty && model.error == nil,
                                animated: !isRevealingFromSkeleton && view.window != nil)
        loadingOlderIndicator.setLoading(model.isLoadingMore)
        // With news to show, a failure is the chat's failure line under them
        loadErrorView.show(model.items.isEmpty ? model.error.map(Self.errorText) : nil)
        guard !isApplyingSnapshot else {
            needsSnapshotUpdate = true
            return
        }

        let anchor = hasPerformedInitialScroll ? paginationAnchor() : nil
        let stickToBottom = hasPerformedInitialScroll && lastKnownNearBottom && paginationTask == nil && !model.isLoadingMore
        itemsById = Dictionary(uniqueKeysWithValues: model.items.map { ($0.eventId, $0) })
        var ids: [ItemID] = []
        var previousDay: Date?
        let previousDayStarts = dayStarts
        dayStarts = [:]
        for item in model.items {
            let deliveredAt = AgentV2DateParser.date(item.deliveredAt)
            let day = LocalizationSupport.shared.calendar.startOfDay(for: deliveredAt)
            if previousDay != day {
                ids.append(.day(day))
                dayStarts[day] = deliveredAt
                previousDay = day
            }
            if item.eventId == model.unreadEventId { ids.append(.unread) }
            ids.append(.news(item.eventId))
        }
        if model.error != nil, !model.items.isEmpty {
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
            } else if stickToBottom {
                self.revealLastItemSettlingRowHeights()
            } else if let anchor {
                self.restoreAnchor(anchor)
            }
            self.updateNearBottomState()
            if self.needsSnapshotUpdate {
                self.needsSnapshotUpdate = false
                self.updateFeed()
            }
        }
    }

    private func revealCardsFromSkeleton() {
        AgentSkeletonReveal.revealRows(in: collectionView, isRightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                                      placeholders: skeletonView.placeholdersInWindow()) { cell, _ in
            cell is AgentNewsFeedCardCell ? .bubble(isOutgoing: false) : .line
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
        if let divider = dataSource.indexPath(for: .unread) {
            revealItemAtTop(divider)
        } else {
            revealLastItemSettlingRowHeights()
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
        for cell in collectionView.visibleCells where cell is AgentNewsFeedCardCell {
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
    }

    /// Checks again whether the latest news is in reach and shows or hides the scroll button by it, as a chat does
    /// after it applies its rows. Rows can change without a scroll, and the scroll that keeps a row in place runs no
    /// such check.
    private func updateNearBottomState() {
        guard hasPerformedInitialScroll else { return }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func openDiscussion(eventId: Int, locale: String) {
        guard !isOpeningDiscussion, let navigationController,
              let item = model.items.first(where: { $0.eventId == eventId }) else { return }
        isOpeningDiscussion = true
        var thread: ApiAgentV2ThreadSummary?
        if let threadId = item.discussion?.threadId {
            if let discussion = preloader.model(threadId: threadId) {
                if discussion.hasMessages || discussion.hasActiveRun {
                    thread = discussion.thread
                }
            } else if let summary = model.findThread(threadId), summary.messageCount > 0 {
                thread = summary
            }
        }
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
        navigationController.pushViewController(controller, animated: true)
    }

    /// A news item's discussion counts once the user has written in it: opening it creates the thread with only the
    /// post, its one message, and backing out leaves the card's "Discuss" as it was
    private func isDiscussionStarted(for item: ApiAgentV2NewsFeedItem) -> Bool {
        guard let threadId = item.discussion?.threadId else { return false }
        if let discussion = preloader.model(threadId: threadId), discussion.hasUserMessages { return true }
        return (model.findThread(threadId)?.messageCount ?? 0) > 1
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
            self?.openSource(for: item)
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
            self?.openSource(for: items[index])
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

    private func openSource(for item: ApiAgentV2NewsFeedItem) {
        AgentTextLinks.openNewsSource(
            item.sources.first?.url,
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
        nil
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
        guard let id = dataSource.itemIdentifier(for: indexPath), case .news = id else { return nil }
        return id
    }

    func getIndexPath(forAnchorItemID itemID: ItemID) -> IndexPath? {
        dataSource.indexPath(for: itemID)
    }
}

extension AgentNewsFeedVC: UICollectionViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collectionView.isScrollingToLatest = false
        listScrollAnimator.stop()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasPerformedInitialScroll, !isRestoringPosition, !isApplyingSnapshot else { return }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: true)
        // Older news load as a chat's older messages do, once the list comes within reach of its top
        guard isNearTopForLoadingOlder, paginationAnchor() != nil,
              paginationTask == nil, !model.isLoading, !model.isLoadingMore, model.nextCursor != nil else { return }
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await model.loadMore()
            paginationTask = nil
        }
    }
}

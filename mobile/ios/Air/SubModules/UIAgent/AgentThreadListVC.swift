import Combine
import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

private enum AgentThreadListLayout {
    static let refreshInterval: TimeInterval = 30
    static let rowMoveDuration: TimeInterval = 0.45
    static let sectionSpacing: CGFloat = 6
    /// The suggestions sit 26 pt above the question field, as on an empty chat
    static let suggestionsToField: CGFloat = 26
    /// Before the field is on screen, the suggestions assume it 12 pt above the keyboard
    static let suggestionsBottomToKeyboard: CGFloat = 12 + AgentListBottomBar.height + suggestionsToField
}

@MainActor
public final class AgentThreadListVC: WViewController, WalletCoreData.EventsObserver {
    /// The question field. The root hosts it over its toolbar; without a host the list lays it out itself.
    public let bottomBar = AgentListBottomBar()
    public var isConsentRequired: Bool { hasLoadedConsent && !hasConsent }
    public var onConsentChanged: (() -> Void)?

    private let model: AgentThreadListModel
    private let loadConsent: () async throws -> Bool
    private let acceptConsent: () async throws -> Void
    private let makeThreadChat: (ApiAgentV2ThreadSummary) -> UIViewController
    private let makeNewChat: (String?) -> UIViewController
    private let makeNewsFeed: (AgentNewsFeedModel) -> UIViewController
    private let loadSuggestions: () async throws -> [AgentHint]
    private let consentView = AgentConsentView()
    /// Telegram's placeholder rows while the chats load, behind the list so it fades with it
    private let skeletonView = AgentThreadListSkeletonView()
    private let paginationIndicator = UIActivityIndicatorView(style: .medium)
    private let suggestionsView = AgentHintsSectionView()
    private var collectionView: UICollectionView!
    private typealias ListSnapshot = NSDiffableDataSourceSnapshot<AgentThreadListSection.ID, String>
    private var dataSource: UICollectionViewDiffableDataSource<AgentThreadListSection.ID, String>!
    /// The list's background above the safe area, solid so the pinned day header continues it to the top of the screen
    private(set) var navigationBarBackground: UIView?
    /// With Liquid Glass, the blurring band the header and the pinned day headers sit on. It lies in the list between
    /// the rows and the day headers, and reaches under the day header's place once the list has scrolled past the
    /// first day header, whether a day header is pinned there or the next one is on its way: the system's edge
    /// effect let the band go altogether in that handover.
    private(set) var headerBackdrop: UIView?
    private var suggestionsHeightConstraint: NSLayoutConstraint!
    private var suggestionsToFieldConstraint: NSLayoutConstraint?
    private var suggestionsNavigationBottomConstraint: NSLayoutConstraint?
    private var localBottomBarConstraints: [NSLayoutConstraint] = []
    private var consentTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var suggestionsTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var conversationChangedSubscription: AnyCancellable?
    private var sections: [AgentThreadListSection] = []
    private var itemsById: [String: ApiAgentV2ThreadListItem] = [:]
    private var suggestions: [AgentHint] = []
    private var hasConsent = false
    private var hasLoadedConsent = false
    private var needsRefresh = false
    private var isShowingSuggestions = false
    private var isComposing = false
    /// A question sent while composing continues in a chat that takes the list's place; the list keeps its compose
    /// state under it, though the field gives up the keyboard first
    private var shouldKeepSuggestionsForComposedChat = false
    private var isBottomBarHostedExternally = false
    private var tabTransitionProgress: CGFloat = 1
    /// The next list change moves rows the way Telegram moves a chat it pins
    private var shouldMoveRowsOnSpring = false
    /// Chats the user deleted: the change that removes one moves the rows on the same spring, as Telegram's list
    /// closes up a removed chat's place
    private var deletingThreadIds: Set<String> = []
    /// A tap beside the new chat's suggestions ends composing and closes the keyboard
    private lazy var composeDismissTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(endComposing))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        return tap
    }()

    public convenience init(userDefaults: UserDefaults = .standard) {
        let client = LiveAgentV2Client()
        self.init(
            model: AgentThreadListModel(readState: AgentNewsReadState(userDefaults: userDefaults)),
            loadConsent: { try await client.consent() },
            acceptConsent: { try await client.acceptConsent() }
        )
    }

    init(
        model: AgentThreadListModel,
        loadConsent: @escaping () async throws -> Bool,
        acceptConsent: @escaping () async throws -> Void,
        makeThreadChat: @escaping (ApiAgentV2ThreadSummary) -> UIViewController = {
            AgentEntryPoint.makeRootViewController(thread: $0)
        },
        makeNewChat: @escaping (String?) -> UIViewController = {
            AgentEntryPoint.makeNewChatViewController(query: $0)
        },
        makeNewsFeed: @escaping (AgentNewsFeedModel) -> UIViewController = {
            AgentNewsFeedVC(model: $0)
        },
        loadSuggestions: @escaping () async throws -> [AgentHint] = {
            try await AgentSearchProvider.shared.loadSuggestions(langCode: "").map {
                AgentHint(id: $0.id, title: $0.title, subtitle: $0.prompt, prompt: $0.prompt, catalogVersion: $0.catalogVersion)
            }
        }
    ) {
        self.model = model
        self.loadConsent = loadConsent
        self.acceptConsent = acceptConsent
        self.makeThreadChat = makeThreadChat
        self.makeNewChat = makeNewChat
        self.makeNewsFeed = makeNewsFeed
        self.loadSuggestions = loadSuggestions
        super.init(nibName: nil, bundle: nil)
        title = lang("Agent")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        consentTask?.cancel()
        refreshTask?.cancel()
        loadMoreTask?.cancel()
        suggestionsTask?.cancel()
        refreshTimer?.invalidate()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        configureDataSource()
        configureBottomBar()
        model.onChange = { [weak self] in self?.updateList() }
        model.onError = { error in AppActions.showError(error: error) }
        model.onActivityChange = { [weak self] threadIds in self?.updateActivities(threadIds: threadIds) }
        WalletCoreData.addImmediately(eventObserver: self)
        conversationChangedSubscription = AgentSearchProvider.shared.conversationChanged.sink { [weak self] in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThreadReadStateChange),
            name: AgentThreadReadState.didChangeNotification,
            object: nil
        )
        checkConsent()
    }

    /// A chat got or lost its unread dot; the visible rows show it at once
    @objc private func handleThreadReadStateChange() {
        guard isViewLoaded, let collectionView else { return }
        for case let cell as AgentThreadCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let id = dataSource.itemIdentifier(for: indexPath),
                  let item = itemsById[id] else { continue }
            cell.configure(with: item, activity: model.getActivityText(threadId: id), isUnread: model.isUnread(item.thread))
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        consentView.isActive = true
        suggestionsView.isActive = true
        // Back from a chat the question started, the list shows its threads again unless its field is editing
        shouldKeepSuggestionsForComposedChat = false
        if isComposing, !bottomBar.isEditing {
            setSuggestionsVisible(false, animated: false)
        }
        if hasConsent {
            updateList()
            refresh()
        } else if consentTask == nil {
            checkConsent()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let constraint = suggestionsNavigationBottomConstraint {
            constraint.isActive = false
            suggestionsNavigationBottomConstraint = nil
            if isShowingSuggestions { attachSuggestionsToField() }
        }
        startRefreshTimer()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderBackdrop()
        layoutSkeleton()
    }

    /// Loading covers every row, including News, from the list's first visible position.
    private func layoutSkeleton() {
        guard !skeletonView.isHidden else { return }
        let top = collectionView.adjustedContentInset.top
        let skeletonFrame = CGRect(
            x: collectionView.frame.minX,
            y: collectionView.frame.minY + top,
            width: collectionView.bounds.width,
            height: max(0, collectionView.bounds.height - top)
        )
        if skeletonView.frame != skeletonFrame { skeletonView.frame = skeletonFrame }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        keepSuggestionsInPlaceForNavigation()
        super.viewWillDisappear(animated)
        consentView.isActive = false
        suggestionsView.isActive = false
        bottomBar.composerView.dictationController?.cancel()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    public override func scrollToTop(animated: Bool) {
        if !hasConsent {
            consentView.scrollToTop(animated: animated)
            return
        }
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .agentV2(let update):
            model.handleAgentUpdate(update)
            switch update {
            case .threadChanged, .messageCompleted:
                // A completed answer keeps its row's status until a load brings the answer's preview
                refresh()
            default:
                break
            }
        case .agentThreadDeleted(let threadId):
            model.removeThread(id: threadId)
        case .accountsReset:
            model.removeAllActivities()
        case .applicationWillEnterForeground:
            // A consent lookup that failed is tried again, as when the screen comes back
            if !hasLoadedConsent, consentTask == nil, view.window != nil {
                checkConsent()
            }
            refresh()
        default:
            break
        }
    }

    // MARK: - Root integration

    /// Lets the root host the bottom bar. Without a host the list installs the bar in its own view.
    public func setBottomBarHostedExternally(_ isHosted: Bool) {
        guard isBottomBarHostedExternally != isHosted else { return }
        isBottomBarHostedExternally = isHosted
        guard isViewLoaded else { return }
        if isHosted {
            NSLayoutConstraint.deactivate(localBottomBarConstraints)
            localBottomBarConstraints = []
            if bottomBar.superview === view { bottomBar.removeFromSuperview() }
        } else {
            bottomBar.setGlassHost(nil)
            installBottomBarLocally()
        }
    }

    /// Paging progress toward this tab, 0 away from it and 1 on it. The list's white background fades in from the
    /// grouped background of the neighbouring tabs.
    public func setTabTransitionProgress(_ progress: CGFloat) {
        tabTransitionProgress = min(1, max(0, progress))
        guard isViewLoaded else { return }
        let color = getBackgroundColor(for: tabTransitionProgress)
        view.backgroundColor = color
        applyChromeBackground(color)
    }

    public func getBackgroundColor(for progress: CGFloat) -> UIColor {
        UIColor { traits in
            let from = UIColor.air.groupedBackground.resolvedColor(with: traits)
            let to = UIColor.air.background.resolvedColor(with: traits)
            return from.interpolate(to: to, progress: progress)
        }
    }

    // MARK: - Setup

    private func configureViews() {
        view.backgroundColor = getBackgroundColor(for: tabTransitionProgress)

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.headerMode = .supplementary
        configuration.backgroundColor = .clear
        configuration.headerTopPadding = 0
        // Rows draw the section separators themselves, so a row lifted into a swipe or menu card can hide its own
        configuration.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            var sectionConfiguration = configuration
            if let self, self.sections.indices.contains(sectionIndex), self.sections[sectionIndex].id == .news {
                sectionConfiguration.headerMode = .none
            }
            let section = NSCollectionLayoutSection.list(using: sectionConfiguration, layoutEnvironment: environment)
            // Sections stand a little apart instead of a line between them
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: 0, bottom: AgentThreadListLayout.sectionSpacing, trailing: 0
            )
            // Day headers stay at the top while their rows scroll beneath
            for header in section.boundarySupplementaryItems {
                header.contentInsets = .zero
                header.pinToVisibleBounds = true
                header.zIndex = 2
            }
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        // Rows light up as the finger lands, as in the token list
        collectionView.delaysContentTouches = false
        collectionView.keyboardDismissMode = .interactive
        collectionView.accessibilityIdentifier = "AgentThreadList"
        collectionView.isHidden = true
        if #available(iOS 26.0, *) {
            // The list draws the band under the header itself; see `headerBackdrop`
            collectionView.topEdgeEffect.isHidden = true
            collectionView.bottomEdgeEffect.isHidden = true
        }

        skeletonView.setVisible(false, animated: false)

        paginationIndicator.translatesAutoresizingMaskIntoConstraints = false
        paginationIndicator.hidesWhenStopped = true

        suggestionsView.translatesAutoresizingMaskIntoConstraints = false
        suggestionsView.layer.shadowOpacity = 0
        suggestionsView.alpha = 0
        suggestionsView.isHidden = true

        view.addSubview(collectionView)
        view.addSubview(skeletonView)
        configureNavigationItemWithTransparentBackground()
        let navigationBarBackground = UIView()
        navigationBarBackground.translatesAutoresizingMaskIntoConstraints = false
        navigationBarBackground.isUserInteractionEnabled = false
        navigationBarBackground.backgroundColor = getBackgroundColor(for: tabTransitionProgress)
        navigationBarBackground.isHidden = Self.shouldUseScrollEdgeEffect
        view.addSubview(navigationBarBackground)
        self.navigationBarBackground = navigationBarBackground
        if Self.shouldUseScrollEdgeEffect {
            let backdrop = addCustomNavigationBarBackground(
                color: getBackgroundColor(for: tabTransitionProgress),
                navItemTransparent: false,
                inside: collectionView
            )
            // Over the rows, under the pinned day headers
            backdrop.layer.zPosition = AgentThreadSectionHeaderView.zPosition - 1
            backdrop.alpha = 0
            headerBackdrop = backdrop
        }
        view.addSubview(suggestionsView)
        view.addSubview(paginationIndicator)

        suggestionsHeightConstraint = suggestionsView.heightAnchor.constraint(equalToConstant: 0)
        let suggestionsAboveKeyboard = suggestionsView.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
            constant: -AgentThreadListLayout.suggestionsBottomToKeyboard
        )
        // The field itself places the suggestions once it is on screen; see `attachSuggestionsToField()`
        suggestionsAboveKeyboard.priority = .defaultLow
        let contentWidth = collectionView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        contentWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            collectionView.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            collectionView.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor),
            contentWidth,
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            navigationBarBackground.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            suggestionsView.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            suggestionsAboveKeyboard,
            suggestionsHeightConstraint,

            paginationIndicator.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            paginationIndicator.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    private func configureBottomBar() {
        let dictationController = AgentDictationController()
        bottomBar.composerView.dictationController = dictationController
        dictationController.onTranscript = { [weak self] text in
            self?.bottomBar.composerView.setDraftText(text, focus: false)
        }
        bottomBar.onSend = { [weak self] text in self?.sendQuestion(text) }
        bottomBar.onEditingChange = { [weak self] isEditing in
            guard let self else { return }
            if isEditing {
                shouldKeepSuggestionsForComposedChat = false
            } else if shouldKeepSuggestionsForComposedChat {
                return
            }
            setSuggestionsVisible(isEditing, animated: true)
        }
        bottomBar.onFieldHeightChange = { [weak self] in
            self?.updateSuggestionsToFieldSpacing()
        }
        view.addGestureRecognizer(composeDismissTap)
        if !isBottomBarHostedExternally {
            installBottomBarLocally()
        }
    }

    private func installBottomBarLocally() {
        guard bottomBar.superview !== view else { return }
        bottomBar.removeFromSuperview()
        bottomBar.isHidden = isConsentRequired
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        let bottom = bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        bottom.priority = .defaultHigh
        localBottomBarConstraints = [
            bottomBar.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor, constant: 28),
            bottomBar.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: -28),
            bottomBar.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            bottom,
            bottomBar.heightAnchor.constraint(equalToConstant: AgentListBottomBar.height),
        ]
        NSLayoutConstraint.activate(localBottomBarConstraints)
    }

    private func configureDataSource() {
        let newsRegistration = UICollectionView.CellRegistration<AgentNewsCell, String> { [weak self] cell, indexPath, _ in
            guard let self else { return }
            cell.configure(latestNews: self.model.latestNews, unreadCount: self.model.newsUnreadCount)
            self.configureSeparator(of: cell, at: indexPath)
        }
        let cellRegistration = UICollectionView.CellRegistration<AgentThreadCell, String> { [weak self] cell, indexPath, id in
            guard let self, let item = self.itemsById[id] else { return }
            cell.configure(
                with: item,
                activity: self.model.getActivityText(threadId: id),
                isUnread: self.model.isUnread(item.thread)
            )
            self.configureSeparator(of: cell, at: indexPath)
            cell.contextMenuConfigurationProvider = { [weak self] in
                self?.makeContextMenu(threadId: id)
            }
            cell.renameAction = { [weak self] in self?.showRename(threadId: id) }
            cell.pinAction = { [weak self] in self?.togglePinned(threadId: id) }
            cell.deleteAction = { [weak self] in self?.showDeleteConfirmation(threadId: id) }
            cell.onSwipeBegan = { [weak self, weak cell] in
                self?.closeSwipedRows(except: cell)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<AgentThreadSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self, self.sections.indices.contains(indexPath.section) else { return }
            header.configure(title: self.sections[indexPath.section].title)
            if Self.shouldUseScrollEdgeEffect {
                header.backgroundColor = .clear
            } else {
                header.backgroundColor = self.getBackgroundColor(for: self.tabTransitionProgress)
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            if id == AgentThreadListSection.newsItemId {
                return collectionView.dequeueConfiguredReusableCell(using: newsRegistration, for: indexPath, item: id)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    /// Liquid Glass puts the header and the pinned day headers on the system's translucent, blurring top edge effect
    static var shouldUseScrollEdgeEffect: Bool {
        if #available(iOS 26.0, *), IOS_26_MODE_ENABLED { return true }
        return false
    }

    /// Without the edge effect, the top chrome and the pinned headers share the list's background, so they read as one
    /// solid band
    private func applyChromeBackground(_ color: UIColor) {
        navigationBarBackground?.backgroundColor = color
        if let headerBackdrop { updateCustomNavigationBarBackground(headerBackdrop, color: color) }
        guard !Self.shouldUseScrollEdgeEffect, let collectionView else { return }
        for header in collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
            header.backgroundColor = color
        }
    }

    /// Shows the changed answering status on the visible rows; other rows pick it up when they are configured
    private func updateActivities(threadIds: Set<String>) {
        guard isViewLoaded, let collectionView else { return }
        for case let cell as AgentThreadCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let id = dataSource.itemIdentifier(for: indexPath),
                  threadIds.contains(id) else { continue }
            cell.setActivity(model.getActivityText(threadId: id), animated: view.window != nil)
        }
    }

    /// As in Telegram's chat list, a line separates the rows of a section, and none follows its last row. The line
    /// above a row lifted into a card or highlighted gives way, as its own does.
    private func configureSeparator(of cell: AgentThreadRowCell, at indexPath: IndexPath) {
        cell.isBottomSeparatorShown = sections.indices.contains(indexPath.section)
            && indexPath.item < sections[indexPath.section].itemIdentifiers.count - 1
        cell.followingRowEmphasis = getFollowingRowEmphasis(after: indexPath)
        cell.onEmphasisChange = { [weak self, weak cell] emphasis in
            guard let self, let cell, let indexPath = self.collectionView.indexPath(for: cell), indexPath.item > 0,
                  let previous = self.collectionView.cellForItem(at: IndexPath(item: indexPath.item - 1, section: indexPath.section))
                    as? AgentThreadRowCell else { return }
            previous.followingRowEmphasis = emphasis
        }
    }

    private func getFollowingRowEmphasis(after indexPath: IndexPath) -> CGFloat {
        let next = IndexPath(item: indexPath.item + 1, section: indexPath.section)
        return (collectionView.cellForItem(at: next) as? AgentThreadRowCell)?.emphasis ?? 0
    }

    // MARK: - Consent

    private func checkConsent() {
        consentTask = Task { [weak self] in
            guard let self else { return }
            let isAllowed = try? await loadConsent()
            guard !Task.isCancelled else { return }
            consentTask = nil
            guard let isAllowed else { return }
            hasLoadedConsent = true
            if isAllowed {
                showList()
            } else {
                showConsent()
            }
        }
    }

    private func showConsent() {
        // A field focused while the lookup ran would keep its keyboard over the consent's button
        bottomBar.resignEditing()
        bottomBar.isHidden = true
        onConsentChanged?()
        skeletonView.setVisible(false, animated: false)
        consentView.translatesAutoresizingMaskIntoConstraints = false
        consentView.onContinue = { [weak self] in self?.continueWithConsent() }
        consentView.onLearnMore = {
            guard let url = URL(string: APP_PRIVACY_POLICY_URL) else { return }
            AppActions.openInBrowser(url, title: lang("Privacy Policy"), injectDappConnect: false)
        }
        guard consentView.superview == nil else { return }
        view.addSubview(consentView)
        NSLayoutConstraint.activate([
            consentView.topAnchor.constraint(equalTo: view.topAnchor),
            consentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            consentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            consentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func continueWithConsent() {
        // The button is disabled while an acceptance runs, so a pending task here is a lookup the acceptance replaces
        consentTask?.cancel()
        consentView.isUserInteractionEnabled = false
        consentTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await acceptConsent()
                guard !Task.isCancelled else { return }
                consentTask = nil
                showList()
            } catch {
                consentTask = nil
                consentView.isUserInteractionEnabled = true
                guard !Task.isCancelled, let error = AgentV2Copy.displayError(error) else { return }
                AppActions.showError(error: error)
            }
        }
    }

    private func showList() {
        hasConsent = true
        consentView.removeFromSuperview()
        collectionView.isHidden = false
        // The root owns visibility while hosting the bar, including when this page was only preloaded.
        if !isBottomBarHostedExternally {
            bottomBar.isHidden = false
        }
        onConsentChanged?()
        updateList()
        refresh()
        loadSuggestionsIfNeeded()
        if view.window != nil { startRefreshTimer() }
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        guard hasConsent else { return }
        // The list stays current while it is on screen, without pull to refresh
        let timer = Timer(timeInterval: AgentThreadListLayout.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.view.window != nil, UIApplication.shared.applicationState == .active else { return }
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refresh() {
        guard hasConsent else { return }
        if refreshTask != nil {
            needsRefresh = true
            return
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                needsRefresh = false
                async let newsRefresh: Void = model.refreshNews()
                await model.refresh()
                await newsRefresh
            } while needsRefresh && !Task.isCancelled
            refreshTask = nil
        }
    }

    private func updateList() {
        guard isViewLoaded else { return }
        sections = model.hasLoaded ? model.sections() : []
        itemsById = Dictionary(model.items.map { ($0.thread.id, $0) }, uniquingKeysWith: { _, item in item })
        let oldSnapshot = dataSource.snapshot()
        let existingIds = Set(oldSnapshot.itemIdentifiers)
        var snapshot = ListSnapshot()
        snapshot.appendSections(sections.map(\.id))
        for section in sections {
            snapshot.appendItems(section.itemIdentifiers, toSection: section.id)
        }
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { existingIds.contains($0) })
        let removedIds = existingIds.subtracting(snapshot.itemIdentifiers)
        let shouldRemoveDeletedRows = !deletingThreadIds.isDisjoint(with: removedIds)
        deletingThreadIds.subtract(removedIds)
        let isAnimated = view.window != nil
        let isShowingSkeleton = hasConsent && !model.hasLoaded
        let listAlpha: CGFloat = bottomBar.isEditing || shouldKeepSuggestionsForComposedChat ? 0 : 1
        let shouldRevealFromSkeleton = isAnimated && hasConsent && !isShowingSkeleton && skeletonView.isShowing
            && !UIAccessibility.isReduceMotionEnabled
        if shouldRevealFromSkeleton {
            shouldMoveRowsOnSpring = false
            dataSource.apply(snapshot, animatingDifferences: false)
            collectionView.layoutIfNeeded()
            UIView.animate(withDuration: AgentThreadListSkeletonView.fadeDuration, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
                self.collectionView.alpha = listAlpha
            }
        } else if isAnimated, shouldMoveRowsOnSpring || shouldRemoveDeletedRows, !UIAccessibility.isReduceMotionEnabled {
            // Telegram moves a pinned or unpinned chat to its place on its list's spring, the other rows making way,
            // and closes up a deleted chat's place on it
            shouldMoveRowsOnSpring = false
            UIView.animate(
                withDuration: AgentThreadListLayout.rowMoveDuration,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.dataSource.apply(snapshot, animatingDifferences: true)
            }
        } else {
            shouldMoveRowsOnSpring = false
            applyKeepingRowsOnScreen(snapshot, from: oldSnapshot)
        }
        setSuggestionsVisible(bottomBar.isEditing || shouldKeepSuggestionsForComposedChat, animated: isAnimated)
        if isShowingSkeleton {
            collectionView.layer.removeAllAnimations()
            collectionView.alpha = 0
            skeletonView.setVisible(listAlpha > 0, animated: false)
            collectionView.layoutIfNeeded()
            layoutSkeleton()
        } else if hasConsent {
            if !shouldRevealFromSkeleton { collectionView.alpha = listAlpha }
            skeletonView.setVisible(false, animated: view.window != nil)
        }
        if model.isLoading, !model.items.isEmpty, model.nextCursor != nil, loadMoreTask != nil {
            paginationIndicator.startAnimating()
        } else {
            paginationIndicator.stopAnimating()
        }
    }

    /// Applies a change that came with the chats themselves, such as a chat moving up with a new message, at once, as
    /// Telegram's list does. At the top of the list the rows make way for a chat coming in above them; scrolled down,
    /// the rows on screen stay where they are, those under a chat that left closing up its place, and a drag or a
    /// fling goes on as it was.
    private func applyKeepingRowsOnScreen(_ snapshot: ListSnapshot, from oldSnapshot: ListSnapshot) {
        let shouldMoveRows = snapshot.sectionIdentifiers != oldSnapshot.sectionIdentifiers
            || Self.groupRowsBySection(of: snapshot) != Self.groupRowsBySection(of: oldSnapshot)
        guard shouldMoveRows, view.window != nil else {
            dataSource.apply(snapshot, animatingDifferences: false)
            return
        }
        collectionView.layoutIfNeeded()
        let anchor = findRowAnchor(for: snapshot, from: oldSnapshot)
        dataSource.apply(snapshot, animatingDifferences: false)
        guard let anchor else { return }
        collectionView.layoutIfNeeded()
        guard let indexPath = dataSource.indexPath(for: anchor.id),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
        var offset = frame.minY - anchor.y
        if !collectionView.isTracking, !collectionView.isDecelerating {
            // At rest the list doesn't bounce back on its own
            let inset = collectionView.adjustedContentInset
            let maxOffset = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
            offset = min(maxOffset, max(-inset.top, offset))
        }
        guard abs(offset - collectionView.contentOffset.y) > 0.25 else { return }
        // Setting the offset itself, unlike `setContentOffset(_:animated:)`, keeps the drag or the fling going
        UIView.performWithoutAnimation {
            collectionView.contentOffset.y = offset
        }
    }

    /// The first row on screen that stays in place, with where on screen its top stays: up by the part of the screen
    /// the chats that left above it took. Nil at the top of the list, where the rows make way for chats coming in
    /// above them.
    private func findRowAnchor(for snapshot: ListSnapshot, from oldSnapshot: ListSnapshot) -> (id: String, y: CGFloat)? {
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        guard visibleTop > 0.5 else { return nil }
        var leavingIds = Set<String>()
        for change in snapshot.itemIdentifiers.difference(from: oldSnapshot.itemIdentifiers).inferringMoves() {
            if case .remove(_, let id, _) = change { leavingIds.insert(id) }
        }
        let rows = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> (id: String, frame: CGRect)? in
            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame,
                  frame.maxY > visibleTop else { return nil }
            return (id, frame)
        }.sorted { $0.frame.minY < $1.frame.minY }
        guard let anchor = rows.first(where: { !leavingIds.contains($0.id) }) else { return nil }
        let closedUp = rows.lazy
            .filter { leavingIds.contains($0.id) && $0.frame.minY < anchor.frame.minY }
            .reduce(CGFloat(0)) { $0 + $1.frame.maxY - max($1.frame.minY, visibleTop) }
        return (anchor.id, anchor.frame.minY - closedUp - collectionView.contentOffset.y)
    }

    private static func groupRowsBySection(of snapshot: ListSnapshot) -> [[String]] {
        snapshot.sectionIdentifiers.map { snapshot.itemIdentifiers(inSection: $0) }
    }

    /// Fades in the rows and section headers on screen that weren't in the list before, over the placeholders fading
    /// out under them
    private func revealRows(exceptItems existingIds: Set<String>, sections existingSections: Set<AgentThreadListSection.ID>) {
        let now = CACurrentMediaTime()
        func fadeIn(_ view: UIView) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = view.layer.opacity
            fade.duration = AgentThreadListSkeletonView.fadeDuration
            fade.beginTime = view.layer.convertTime(now, from: nil)
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer.add(fade, forKey: "agentSkeletonReveal")
        }
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let id = dataSource.itemIdentifier(for: indexPath), !existingIds.contains(id),
                  let cell = collectionView.cellForItem(at: indexPath) else { continue }
            fadeIn(cell)
        }
        let headerKind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: headerKind) {
            guard sections.indices.contains(indexPath.section), !existingSections.contains(sections[indexPath.section].id),
                  let header = collectionView.supplementaryView(forElementKind: headerKind, at: indexPath) else { continue }
            fadeIn(header)
        }
    }

    // MARK: - Question field

    /// Shows a chat started while the list composes a question in the list's place, as the host's header continues
    /// into the chat's. Returns false when the host can't, and the list pushes the chat.
    public var presentComposedChat: ((UIViewController) -> Bool)?

    private func sendQuestion(_ query: String) {
        guard !query.isEmpty, let navigationController else { return }
        let isComposing = self.isComposing
        bottomBar.clearDraft()
        let chat = makeNewChat(query)
        shouldKeepSuggestionsForComposedChat = isComposing && presentComposedChat != nil
        if shouldKeepSuggestionsForComposedChat {
            // The suggestions fade as they go down with the field, while the chat takes the list's place; the list's
            // threads stay away until the chat closes
            suggestionsView.isUserInteractionEnabled = false
            fadeSuggestionsAway()
        }
        // The host takes the keyboard from the field itself as it shows the chat in the list's place
        if shouldKeepSuggestionsForComposedChat, presentComposedChat?(chat) == true { return }
        bottomBar.resignEditing()
        if shouldKeepSuggestionsForComposedChat {
            shouldKeepSuggestionsForComposedChat = false
            setSuggestionsVisible(bottomBar.isEditing, animated: true)
        }
        navigationController.pushViewController(chat, animated: true)
    }

    /// The chat takes the list's place in a crossfade of the whole screen, which would cut the suggestions' own fade
    /// short: a picture of them fades over it instead, in the window, going down with the field
    private func fadeSuggestionsAway() {
        let suggestions = suggestionsView
        let duration: CFTimeInterval = 0.25
        guard let window = view.window, !suggestions.isHidden, suggestions.alpha > 0.01,
              !UIAccessibility.isReduceMotionEnabled,
              let picture = suggestions.snapshotView(afterScreenUpdates: false) else {
            UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
                suggestions.alpha = 0
            }
            return
        }
        picture.frame = suggestions.convert(suggestions.bounds, to: window)
        picture.isUserInteractionEnabled = false
        picture.accessibilityElementsHidden = true
        window.addSubview(picture)
        suggestions.alpha = 0
        let field = bottomBar
        let fieldTop = field.convertAsShown(to: window).minY
        let start = CACurrentMediaTime()
        // The clock keeps itself until the picture is gone
        var clock: GlassMotionClock?
        clock = GlassMotionClock(frameRateRange: nil) { [weak picture, weak field, weak window] _ in
            let progress = min(1, (CACurrentMediaTime() - start) / duration)
            if let picture, let window {
                picture.alpha = 1 - (1 - (1 - progress) * (1 - progress))
                if let field {
                    let offset = field.convertAsShown(to: window).minY - fieldTop
                    picture.transform = CGAffineTransform(translationX: 0, y: max(0, offset))
                }
            }
            guard progress >= 1 || picture == nil else { return }
            picture?.removeFromSuperview()
            clock?.stop()
            clock = nil
        }
        clock?.start()
    }

    private func loadSuggestionsIfNeeded() {
        guard suggestions.isEmpty, suggestionsTask == nil else { return }
        suggestionsTask = Task { [weak self] in
            guard let self else { return }
            let loaded = (try? await loadSuggestions()) ?? []
            suggestionsTask = nil
            guard !Task.isCancelled, !loaded.isEmpty else { return }
            suggestions = Array(loaded.prefix(5))
            suggestionsView.configure(with: suggestions) { [weak self] hint in
                self?.sendQuestion(hint.prompt)
            }
            suggestionsHeightConstraint.constant = AgentHintsSectionView.calculateContentHeight(for: suggestions.count)
        }
    }

    /// Pins the suggestions above the question field wherever its host places it, so they move with it as the
    /// keyboard comes and goes. The field may live in another view, which the constraint reaches through their common
    /// ancestor; it goes away with the field when the field leaves that hierarchy.
    private func attachSuggestionsToField() {
        guard suggestionsNavigationBottomConstraint == nil else { return }
        if let constraint = suggestionsToFieldConstraint, constraint.isActive { return }
        guard let window = view.window, bottomBar.window === window else { return }
        let constraint = suggestionsView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor)
        suggestionsToFieldConstraint = constraint
        updateSuggestionsToFieldSpacing()
        constraint.isActive = true
        UIView.performWithoutAnimation { view.layoutIfNeeded() }
    }

    /// UIKit moves the departing screen into its transition container. The external toolbar stays behind, so its
    /// cross-hierarchy constraint no longer holds the suggestions; they keep their place inside the moving screen.
    private func keepSuggestionsInPlaceForNavigation() {
        guard isBottomBarHostedExternally, isShowingSuggestions, !shouldKeepSuggestionsForComposedChat,
              suggestionsNavigationBottomConstraint == nil, suggestionsView.bounds.height > 0 else { return }
        let bottomInset = view.bounds.maxY - suggestionsView.frame.maxY
        suggestionsToFieldConstraint?.isActive = false
        let constraint = suggestionsView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottomInset)
        suggestionsNavigationBottomConstraint = constraint
        constraint.isActive = true
    }

    /// A field taller than the bar, with several lines of text, reaches above it
    private func updateSuggestionsToFieldSpacing() {
        guard let constraint = suggestionsToFieldConstraint else { return }
        let constant = -AgentThreadListLayout.suggestionsToField - (bottomBar.fieldHeight - AgentListBottomBar.height)
        guard constraint.constant != constant else { return }
        constraint.constant = constant
        guard constraint.isActive, isShowingSuggestions, view.window != nil else { return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }

    /// An empty list keeps its News row above the suggestions; composing gives the suggestions the whole screen
    private func setSuggestionsVisible(_ isEditing: Bool, animated: Bool) {
        let shouldHideList = isEditing && hasConsent
        let isLoadingList = hasConsent && !model.hasLoaded
        let isVisible = hasConsent && (isEditing || model.hasLoaded && model.items.isEmpty)
        if isLoadingList { skeletonView.setVisible(!shouldHideList, animated: animated) }
        if isVisible { attachSuggestionsToField() }
        guard isShowingSuggestions != isVisible || isComposing != shouldHideList else { return }
        let wasShowingSuggestions = isShowingSuggestions
        isComposing = shouldHideList
        isShowingSuggestions = isVisible
        if isVisible {
            loadSuggestionsIfNeeded()
            closeSwipedRows(except: nil)
        }
        suggestionsView.isHidden = false
        suggestionsView.isUserInteractionEnabled = isVisible
        collectionView.accessibilityElementsHidden = shouldHideList
        let updates = {
            self.collectionView.alpha = shouldHideList || isLoadingList ? 0 : 1
            self.suggestionsView.alpha = isVisible ? 1 : 0
            self.suggestionsView.transform = isVisible ? .identity : CGAffineTransform(translationX: 0, y: 24)
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            updates()
            suggestionsView.isHidden = !isVisible
            return
        }
        if isVisible, !wasShowingSuggestions {
            suggestionsView.transform = CGAffineTransform(translationX: 0, y: 24)
        }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            updates()
        } completion: { [weak self] _ in
            guard let self, !self.isShowingSuggestions else { return }
            self.suggestionsView.isHidden = true
        }
    }

    // MARK: - Thread actions

    private func closeSwipedRows(except cell: AgentThreadCell?) {
        for case let visible as AgentThreadCell in collectionView.visibleCells where visible !== cell {
            visible.closeSwipeActions(animated: true)
        }
    }

    private func makeContextMenu(threadId: String) -> ContextMenuConfiguration? {
        guard let thread = itemsById[threadId]?.thread else { return nil }
        let isPinned = thread.isPinned == true
        var style = ContextMenuStyle.default
        style.sourceSpacing = AgentThreadMenuMetrics.menuSpacing
        style.panelCornerRadius = AgentThreadMenuMetrics.menuCornerRadius
        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(ContextMenuAction(title: lang("Rename"), icon: .system("pencil.line")) { [weak self] in
                    self?.showRename(threadId: threadId)
                }),
                .action(ContextMenuAction(title: lang(isPinned ? "Unpin" : "Pin"), icon: .system(isPinned ? "pin.slash" : "pin")) { [weak self] in
                    self?.togglePinned(threadId: threadId)
                }),
                .separator,
                .action(ContextMenuAction(title: lang("Delete"), icon: .system("trash"), role: .destructive) { [weak self] in
                    self?.showDeleteConfirmation(threadId: threadId)
                })
            ]),
            backdrop: .untintedBlur(
                radius: AgentThreadMenuMetrics.backdropBlurRadius,
                dimAlpha: AgentThreadMenuMetrics.backdropDimAlpha
            ),
            backdropTintColor: AgentThreadMenuMetrics.backdropTint,
            style: style
        )
    }

    private func togglePinned(threadId: String) {
        guard let thread = itemsById[threadId]?.thread else { return }
        shouldMoveRowsOnSpring = true
        Task { [model] in await model.setPinned(thread, isPinned: thread.isPinned != true) }
    }

    private func showRename(threadId: String) {
        guard let thread = itemsById[threadId]?.thread, presentedViewController == nil else { return }
        let alert = UIAlertController(title: lang("Rename Chat"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = thread.title
            field.placeholder = lang("New Chat")
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        let save = UIAlertAction(title: lang("Save"), style: .default) { [weak alert, model] _ in
            let title = alert?.textFields?.first?.text ?? ""
            Task { await model.rename(thread, title: title) }
        }
        alert.addAction(save)
        alert.preferredAction = save
        alert.view.tintColor = .tintColor
        present(alert, animated: true)
    }

    private func showDeleteConfirmation(threadId: String) {
        guard let thread = itemsById[threadId]?.thread, presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: lang("Delete Chat?"),
            message: lang("$agent_delete_chat_confirmation"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: lang("Delete"), style: .destructive) { [weak self, model] _ in
            self?.deletingThreadIds.insert(thread.id)
            Task { await model.delete(thread) }
        })
        present(alert, animated: true)
    }
}

extension AgentThreadListVC: UIGestureRecognizerDelegate {
    @objc private func endComposing() {
        guard isComposing else { return }
        bottomBar.resignEditing()
        view.window?.endEditing(true)
    }

    /// Suggestions and the spinning top keep their own touches; anywhere else on the new chat's screen ends composing
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === composeDismissTap else { return true }
        guard isComposing else { return false }
        var view = touch.view
        while let current = view, current !== self.view {
            if current is UIControl || current is AgentSpinningTopView || current === bottomBar {
                return false
            }
            view = current.superview
        }
        return true
    }
}

extension AgentThreadListVC: UICollectionViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateHeaderBackdrop()
        layoutSkeleton()
    }

    /// The band shows once rows pass under the header, and reaches under the day header's place once the list has
    /// scrolled past the first day header's own place
    private func updateHeaderBackdrop() {
        guard let headerBackdrop, isViewLoaded, let collectionView else { return }
        // The visible list's top in the list's content, 0 at rest
        let top = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let alpha = min(1, max(0, top / Self.headerBackdropFadeDistance))
        if headerBackdrop.alpha != alpha { headerBackdrop.alpha = alpha }
        let isExtended = getFirstDayHeaderRestingMinY().map { top >= $0 - 0.5 } ?? false
        setCustomNavigationBarBackgroundExtension(headerBackdrop, isExtended ? Self.headerBackdropDayHeaderExtension : 0)
    }

    /// How far the rows scroll under the header before its band is fully there
    private static let headerBackdropFadeDistance: CGFloat = 12
    /// The band reaches this far further down under a day header, past it a little, so the header sits on the band's
    /// denser part and the rows fade out under it
    private static let headerBackdropDayHeaderExtension: CGFloat = AgentThreadSectionHeaderView.height + 16

    /// Where the first day header sits in the list when it isn't pinned: right above its section's first row
    private func getFirstDayHeaderRestingMinY() -> CGFloat? {
        guard let section = sections.firstIndex(where: { $0.id != .news }),
              collectionView.numberOfSections > section,
              collectionView.numberOfItems(inSection: section) > 0,
              let firstRow = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) else { return nil }
        return firstRow.frame.minY - AgentThreadSectionHeaderView.height
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if let cell = collectionView.cellForItem(at: indexPath) as? AgentThreadCell, cell.isShowingSwipeActions {
            cell.closeSwipeActions(animated: true)
            return
        }
        view.endEditing(true)
        let chat: UIViewController
        if id == AgentThreadListSection.newsItemId {
            chat = makeNewsFeed(model.makeNewsFeedModel())
        } else if let thread = itemsById[id]?.thread {
            chat = makeThreadChat(thread)
        } else {
            return
        }
        guard let navigationController else { return }
        // The row stays lit until the chat has slid in
        let row = collectionView.cellForItem(at: indexPath) as? AgentThreadRowCell
        row?.isHighlightHeld = true
        keepSuggestionsInPlaceForNavigation()
        navigationController.pushViewController(chat, animated: true)
        let accepted = navigationController.transitionCoordinator?.animate(alongsideTransition: nil) { [weak row] _ in
            row?.isHighlightHeld = false
        } ?? false
        if !accepted { row?.isHighlightHeld = false }
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard model.nextCursor != nil, !model.isLoading, loadMoreTask == nil,
              let id = dataSource.itemIdentifier(for: indexPath),
              model.items.suffix(5).contains(where: { $0.thread.id == id }) else { return }
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            await model.loadMore()
            loadMoreTask = nil
            updateList()
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        closeSwipedRows(except: nil)
    }
}

/// A day or "Pinned" header of the thread list. It stays at the top while its rows scroll by.
final class AgentThreadSectionHeaderView: UICollectionReusableView {
    static let height: CGFloat = 39
    private static let titleTop: CGFloat = 8
    private static let titleHeight: CGFloat = 22

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityTraits = .header
        addSubview(label)
        let height = heightAnchor.constraint(equalToConstant: Self.height)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            height,
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AgentThreadRowMetrics.horizontalInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AgentThreadRowMetrics.horizontalInset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Self.titleTop),
            label.heightAnchor.constraint(equalToConstant: Self.titleHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Above the band the list draws under the header, which lies over the rows
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        layer.zPosition = AgentThreadSectionHeaderView.zPosition
    }

    static let zPosition: CGFloat = 2

    func configure(title: String) {
        label.attributedText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: AgentThreadRowMetrics.headerTextColor,
        ])
    }
}

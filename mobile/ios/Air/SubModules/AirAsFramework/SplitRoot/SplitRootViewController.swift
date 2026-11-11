import UIKit
import UIComponents
import UIHome
import UIAssets
import UIAgent
import WalletCore
import WalletContext
import SwiftNavigation

private let sidebarEdgeFadeWidth: CGFloat = 32

private struct SidebarEdgeCoverEntry {
    let navigationController: WNavigationController
    let view: EdgeGradientView
    let color: UIColor
    let isVisible: () -> Bool
}

@MainActor
final class SplitRootViewController: UISplitViewController, VisibleContentProviding {

    let searchController: RootSearchToolbarController
    var presentHiddenTab = presentTabModally
    private let viewModel: SplitRootViewModel

    private let sidebarViewController: SplitRootSidebarViewController
    private let sidebarNavigationController: SplitRootSidebarNavigationController
    private var sideToolbar: UIView?
    private var usesSideToolbar = false
    private var sidebarEdgeCoverEntries: [SidebarEdgeCoverEntry] = []

    /// All live navigation controllers keyed by their tab id.
    private var navControllersByTabId: [AppTabId: WNavigationController]

    var visibleContentProviderViewController: UIViewController {
        currentNavigationController.visibleViewController ?? currentNavigationController
    }

    private var selectedTab: AppTabId { viewModel.selectedTab }
    var currentTabId: AppTabId { selectedTab }
    override var childForStatusBarStyle: UIViewController? { currentNavigationController }

    func takeNavigationStack(for id: AppTabId, keepingRoot: Bool) -> [UIViewController]? {
        guard let navigationController = navControllersByTabId[id] else { return nil }
        if navigationController.viewControllers.isEmpty,
           selectedTab == id,
           let lazyNC = navigationController as? AppTabLazyNavigationController {
            lazyNC.ensureRootViewControllerInstalled()
        }
        let stack = navigationController.viewControllers
        guard !stack.isEmpty else { return nil }
        if keepingRoot, let rootViewController = stack.first {
            navigationController.setViewControllers([rootViewController], animated: false)
        } else {
            navigationController.setViewControllers([Self.makeNavigationStackPlaceholder()], animated: false)
        }
        // Complete removal before the adaptive root reparents the outgoing stack.
        navigationController.viewIfLoaded?.layoutIfNeeded()
        return stack
    }

    func setNavigationStack(_ stack: [UIViewController], for id: AppTabId) {
        guard !stack.isEmpty else { return }
        let navigationController: WNavigationController
        if let existing = navControllersByTabId[id] {
            navigationController = existing
        } else {
            guard let nc = AppTabManager.shared.makeNavigationController(for: id, layout: .split) else { return }
            navControllersByTabId[id] = nc
            navigationController = nc
        }
        if let lazyNC = navigationController as? AppTabLazyNavigationController {
            lazyNC.setPreservedViewControllers(stack)
        } else {
            navigationController.setViewControllers(stack, animated: false)
        }
        if selectedTab == id {
            onTabSelect(tab: id)
        }
    }

    func setNavigationPath(_ path: [UIViewController], for id: AppTabId) {
        let navigationController: WNavigationController
        if let existing = navControllersByTabId[id] {
            navigationController = existing
        } else {
            guard let nc = AppTabManager.shared.makeNavigationController(for: id, layout: .split) else { return }
            navControllersByTabId[id] = nc
            navigationController = nc
        }
        if let lazyNavigationController = navigationController as? AppTabLazyNavigationController {
            lazyNavigationController.ensureRootViewControllerInstalled()
        }
        guard let rootViewController = navigationController.viewControllers.first else { return }
        navigationController.setViewControllers([rootViewController] + path, animated: false)
        if selectedTab == id {
            onTabSelect(tab: id)
        }
    }

    init(searchController: RootSearchToolbarController = RootSearchToolbarController()) {
        self.searchController = searchController
        self.navControllersByTabId = [:]

        let viewModel = SplitRootViewModel()
        // The app opens on the first tab in the user's order
        viewModel.selectedTab = AppTabManager.shared.orderedTabIds.first ?? .wallet
        self.viewModel = viewModel
        self.sidebarViewController = SplitRootSidebarViewController(viewModel: viewModel)
        self.sidebarNavigationController = SplitRootSidebarNavigationController(rootViewController: sidebarViewController)

        super.init(style: .doubleColumn)
        sidebarNavigationController.onDismissSearch = { [weak searchController] in
            searchController?.closeSearch()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        presentsWithGesture = true
        minimumPrimaryColumnWidth = 300
        maximumPrimaryColumnWidth = 420
        updatePrimaryColumnWidthFraction()

        setViewController(sidebarNavigationController, for: .primary)
        // Secondary column and tab-specific setup (edge covers, sidebar selection) are
        // deferred to applyTabConfiguration, called by AdaptiveRootViewController right
        // after loadViewIfNeeded(), so nav controllers are not needed here.

        view.backgroundColor = .black
        AgentHeaderPlatterTransition.installBetweenChats()

        observe { [weak self] in
            guard let self else { return }
            let selectedTab = viewModel.selectedTab
            onTabSelect(tab: selectedTab)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateNavigationPlacement),
            name: DuoNavigationSettings.didChangeNotification,
            object: nil
        )
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge + [UITraitLayoutDirection.self]) {
                (self: SplitRootViewController, _: UITraitCollection) in
                self.updateNavigationPlacement()
            }
        }
        observe { [weak self] in
            guard let self, #available(iOS 27.1, *) else { return }
            let account = AccountStore.account
            (sideToolbar as? SplitRootToolbarView)?.accountButton.configure(account: account)
        }
        viewModel.onCurrentTabTap = { [weak self] tab in
            guard let self else { return }
            if let nc = navControllersByTabId[tab] {
                showDetailViewController(nc, sender: self)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePrimaryColumnWidthFraction()
        updateSidebarEdgeCoverFrames()
        updateNavigationPlacement()
        sideToolbar?.setNeedsLayout()
    }

    @objc private func updateNavigationPlacement() {
        guard #available(iOS 27.1, *) else { return }
        let tabIds = AppTabManager.shared.toolbarTabIds
        usesSideToolbar = DuoNavigationSettings.usesToolbar && traitCollection.verticalBarEdge != .unspecified
        sidebarViewController.hiddenTabIds = usesSideToolbar
            ? Set(tabIds + [.settings]) : []
        updateAgentBottomBar()
        guard usesSideToolbar else {
            (sideToolbar as? SplitRootToolbarView)?.tabBar.cancelInteraction()
            sideToolbar?.removeFromSuperview()
            for nc in navControllersByTabId.values { nc.hidesRootNavigationBar = false }
            updateSidebarNavigationActions()
            return
        }
        guard let nc = navControllersByTabId[selectedTab], let root = nc.viewControllers.first else { return }
        let toolbar: SplitRootToolbarView
        if let existing = sideToolbar as? SplitRootToolbarView, existing.tabIds == tabIds {
            toolbar = existing
        } else {
            (sideToolbar as? SplitRootToolbarView)?.tabBar.cancelInteraction()
            sideToolbar?.removeFromSuperview()
            toolbar = SplitRootToolbarView(tabIds: tabIds)
            toolbar.accountButton.addAction(UIAction { [weak self] _ in
                self?.showSettings(path: [])
            }, for: .touchUpInside)
            toolbar.tabBar.onSelect = { [weak self, weak toolbar] index, repeated in
                guard let toolbar, toolbar.tabIds.indices.contains(index) else { return }
                self?.select(tab: toolbar.tabIds[index], popToRoot: repeated)
            }
            toolbar.tabBar.onReorder = { [weak toolbar] _, _ in
                guard let toolbar else { return }
                AppTabManager.shared.reorderTabs(toolbar.tabIds)
            }
            toolbar.onLayout = { [weak self] in self?.updateSidebarNavigationActions() }
            sideToolbar = toolbar
        }
        if toolbar.superview !== root.view {
            toolbar.tabBar.cancelInteraction()
            toolbar.removeFromSuperview()
            toolbar.frame = root.view.bounds
            root.view.addSubview(toolbar)
        }
        toolbar.navigationContainer = nc.view
        toolbar.accountButton.configure(account: AccountStore.account)
        toolbar.tabBar.showsSelection = toolbar.tabIds.contains(selectedTab)
        if let index = toolbar.tabIds.firstIndex(of: selectedTab) {
            toolbar.tabBar.select(index, animated: false)
        }
        let isEditing = (root as? SplitHomeVC)?.editingNavigator?.state.editingState != nil
        toolbar.isHidden = isEditing || searchController.isSearchVisible
        nc.hidesRootNavigationBar = !isEditing && !(root is SplitHomeVC)
        toolbar.setNeedsLayout()
        updateSidebarNavigationActions()
    }

    private func updateSidebarNavigationActions() {
        let nc = navControllersByTabId[selectedTab]
        let root = nc?.viewControllers.first
        let showsActions = usesSideToolbar && nc?.hidesRootNavigationBar == true && nc?.topViewController === root
        // Leave the trailing side to UIKit's sidebar toggle.
        let actions = showsActions
            ? (root?.navigationItem.leadingItemGroups ?? []) + (root?.navigationItem.trailingItemGroups ?? [])
            : []
        let item = sidebarViewController.navigationItem
        if item.leadingItemGroups != actions { item.leadingItemGroups = actions }
    }

    func applyTabConfiguration(_ orderedIds: [AppTabId]) {
        let currentId = selectedTab

        // Build nav controllers for newly added tabs.
        for id in orderedIds where navControllersByTabId[id] == nil {
            navControllersByTabId[id] = AppTabManager.shared.makeNavigationController(for: id, layout: .split)
        }

        // Remove nav controllers for tabs no longer in the list.
        let removedIds = Set(navControllersByTabId.keys).subtracting(orderedIds)
        for id in removedIds {
            navControllersByTabId.removeValue(forKey: id)
        }

        // Install sidebar edge covers for all tabs (idempotent; color comes from registration).
        for id in orderedIds {
            if let color = AppTabManager.shared.registration(for: id)?.sidebarEdgeCoverColor {
                installSidebarEdgeCoverIfNeeded(for: id, color: color)
            }
        }

        // Notify sidebar to refresh its tab list.
        sidebarViewController.applyTabConfiguration(orderedIds)

        // If the currently selected tab was removed, fall back to wallet.
        if !orderedIds.contains(currentId) {
            viewModel.selectedTab = .wallet
        }

        // Show the current tab in the secondary column (handles initial setup too).
        onTabSelect(tab: viewModel.selectedTab)
    }

    private func installSidebarEdgeCoverIfNeeded(for id: AppTabId, color: UIColor) {
        guard let nc = navControllersByTabId[id],
              !sidebarEdgeCoverEntries.contains(where: { $0.navigationController === nc }) else { return }
        if id == .wallet {
            installSidebarEdgeCover(in: nc, color: color) { [weak nc] in
                nc?.viewControllers.count == 1
            }
        } else {
            installSidebarEdgeCover(in: nc, color: color)
        }
    }

    private func updatePrimaryColumnWidthFraction() {
        let resolvedBounds = view.bounds.isEmpty
            ? (view.window?.bounds ?? UIApplication.shared.anySceneKeyWindow?.bounds ?? .zero)
            : view.bounds
        let maxDimension = max(resolvedBounds.width, resolvedBounds.height)
        guard maxDimension > 0 else { return }
        let isMini = maxDimension < 1150
        preferredPrimaryColumnWidthFraction = isMini ? 0.34 : 0.29
    }

    func select(tab: AppTabId, popToRoot: Bool = false) {
        viewModel.selectedTab = tab
        // Navigation restoration needs the selected host immediately; observation
        // can run after AdaptiveRoot has already finished transferring Search.
        onTabSelect(tab: tab)
        if popToRoot, let nc = navControllersByTabId[tab] {
            nc.popToRootViewController(animated: true)
        }
    }

    func onTabSelect(tab: AppTabId) {
        guard let nc = navControllersByTabId[tab] else { return }
        (nc as? AppTabLazyNavigationController)?.ensureRootViewControllerInstalled()
        if isCollapsed {
            if viewController(for: .secondary) !== nc {
                showDetailViewController(nc, sender: self)
            }
        } else if viewController(for: .secondary) !== nc {
            setViewController(nc, for: .secondary)
        }
        if let home = nc.viewControllers.first as? SplitHomeVC {
            home.onWalletAssetsEditingStateChange = { [weak self] in
                self?.searchController.updatePresentation()
                self?.updateNavigationPlacement()
            }
        }
        searchController.attach(to: self)
        updateAgentBottomBar()
        updateNavigationPlacement()
        setNeedsStatusBarAppearanceUpdate()
    }

    /// The Agent list's question field rides the bottom toolbar beside the search circle, as on the iPhone, so it
    /// carries into a chat's composer and back, and a question sent while composing continues in its chat on the same
    /// screen. Beside a vertical bar the list lays out its own field.
    private func updateAgentBottomBar() {
        guard let list = navControllersByTabId[.agent]?.viewControllers.first as? AgentThreadListVC else {
            searchController.agentBar.isAvailable = true
            searchController.agentBar.setMorphProgress(0)
            return
        }
        searchController.agentBar.isAvailable = true
        var isBarHostedInToolbar = true
        if #available(iOS 27.1, *), traitCollection.verticalBarEdge != .unspecified {
            isBarHostedInToolbar = false
        }
        list.setBottomBarHostedExternally(isBarHostedInToolbar)
        if isBarHostedInToolbar {
            list.presentComposedChat = { [weak self] chat in self?.presentComposedChat(chat) ?? false }
            searchController.agentBar.install(list.bottomBar)
        } else {
            list.presentComposedChat = nil
        }
        // The bar grows out of the toolbar's trailing button on its spring, and folds back into it, once the selected
        // tab's screen, which the toolbar moves into, has joined the window
        guard list.bottomBar.window == nil else {
            searchController.agentBar.setMorphProgress(isBarHostedInToolbar && selectedTab == .agent ? 1 : 0)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            searchController.agentBar.setMorphProgress(isBarHostedInToolbar && selectedTab == .agent ? 1 : 0)
        }
    }

    /// A question sent while the list composes one continues in its chat on the same screen: the chat takes the
    /// list's place in a crossfade as the field lands on its composer. Returns false when the chat should be pushed.
    private func presentComposedChat(_ chat: UIViewController) -> Bool {
        guard selectedTab == .agent, let navigationController = navControllersByTabId[.agent],
              navigationController.viewControllers.count == 1, navigationController.transitionCoordinator == nil,
              let window = view.window, chat is any AgentChatNavigationHandoff else { return false }
        // The field gives up the keyboard first, and the chat comes on the next turn of the run loop, once nothing on
        // the list is editing: a field still editing when the chat covers it would take the keyboard back as it closes
        searchController.agentBar.beginComposedChatHandoff()
        window.endEditing(true)
        DispatchQueue.main.async { [weak navigationController] in
            guard let navigationController else { return }
            guard navigationController.transitionCoordinator == nil, !UIAccessibility.isReduceMotionEnabled else {
                navigationController.pushViewController(chat, animated: !UIAccessibility.isReduceMotionEnabled)
                return
            }
            UIView.transition(
                with: navigationController.view,
                duration: 0.25,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                navigationController.pushViewController(chat, animated: false)
            }
            navigationController.view.layoutIfNeeded()
        }
        return true
    }

    @discardableResult
    func pushFromSearch(_ controller: UIViewController) -> Bool {
        searchController.pushFromSearch(controller)
    }

    func isHomeRootSelected() -> Bool {
        selectedTab == .wallet && navControllersByTabId[.wallet]?.viewControllers.first is SplitHomeVC
    }

    func pushOnHome(_ viewController: UIViewController) -> Bool {
        guard selectedTab == .wallet, let homeNC = navControllersByTabId[.wallet] else { return false }
        homeNC.pushViewController(viewController, animated: true)
        return true
    }

    func showAgentNewsChat(_ controller: UIViewController) {
        guard AppTabManager.shared.contains(.agent) else {
            presentHiddenTab(.agent, topViewController() ?? self, { _ in [controller] })
            return
        }
        searchController.discardSearch()
        select(tab: .agent)
        currentNavigationController.popToRootViewController(animated: false)
        currentNavigationController.pushViewController(
            controller, animated: currentNavigationController.viewIfLoaded?.window != nil
        )
    }

    func showAgentNewsFeed(digestId: String) {
        guard AppTabManager.shared.contains(.agent) else {
            presentHiddenTab(.agent, topViewController() ?? self) { root in
                let list = root as! AgentThreadListVC
                return [list.makeNewsFeedViewController(requestedDigestId: digestId)]
            }
            return
        }
        searchController.discardSearch()
        select(tab: .agent)
        currentNavigationController.popToRootViewController(animated: false)
        guard let list = currentNavigationController.viewControllers.first as? AgentThreadListVC else { return }
        currentNavigationController.pushViewController(
            list.makeNewsFeedViewController(requestedDigestId: digestId),
            animated: currentNavigationController.viewIfLoaded?.window != nil
        )
    }

    func showAgent(query: String?, entryPoint: ApiAgentV2EntryPoint?) {
        if AppTabManager.shared.contains(.agent) {
            searchController.discardSearch()
            select(tab: .agent)
            currentNavigationController.popToRootViewController(animated: false)
        }
        // A navigation controller not in the window yet, as that of a tab just selected, drops an animated push
        currentNavigationController.pushViewController(
            AgentEntryPoint.makeNewChatViewController(query: query, entryPoint: entryPoint),
            animated: currentNavigationController.viewIfLoaded?.window != nil
        )
    }

    func showExplore() {
        select(tab: .explore)
    }

    func showHome(popToRoot: Bool) {
        select(tab: .wallet, popToRoot: popToRoot)
        if let rootViewController = view.window?.rootViewController, rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: true)
        }
    }

    func showSettings(path: [UIViewController]) {
        if let destination = path.last, pushFromSearch(destination) { return }
        select(tab: .settings, popToRoot: false)
        guard let settingsNC = navControllersByTabId[.settings] else { return }
        (settingsNC as? AppTabLazyNavigationController)?.ensureRootViewControllerInstalled()
        guard let rootViewController = settingsNC.viewControllers.first else { return }
        settingsNC.setViewControllers([rootViewController] + path, animated: false)
    }

    func showTemporaryViewAccount(accountId: String) {
        if searchController.isSearchVisible {
            focusSidebarAccount(accountId: accountId, animated: true)
            searchController.pushFromSearch(SplitHomeVC(accountSource: .accountId(accountId)))
            return
        }
        if let rootVC = view.window?.rootViewController, rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
        select(tab: .wallet, popToRoot: false)
        focusSidebarAccount(accountId: accountId, animated: true)

        guard let homeNC = navControllersByTabId[.wallet] else { return }
        if let splitHomeVC = homeNC.topViewController as? SplitHomeVC,
           isTemporarySplitHome(splitHomeVC, accountId: accountId) {
            return
        }

        dismissTemporaryViewAccountIfNeeded(animated: false)
        let vc = SplitHomeVC(accountSource: .accountId(accountId))
        homeNC.pushViewController(vc, animated: true)
    }

    func dismissTemporaryViewAccountIfNeeded(animated: Bool) {
        guard let homeNC = navControllersByTabId[.wallet] else { return }
        let hasTemporaryHomeInStack = homeNC.viewControllers.contains { viewController in
            guard let splitHomeVC = viewController as? SplitHomeVC else { return false }
            guard case .accountId = splitHomeVC.splitHomeAccountContext.source else { return false }
            return true
        }
        guard hasTemporaryHomeInStack else { return }
        homeNC.popToRootViewController(animated: animated)
        syncSidebarFocusWithHomeStack(animated: animated)
    }

    func showAssets(
        accountSource: AccountSource,
        selectedTab: DisplayAssetTab,
        collectionsFilter: NftCollectionFilter,
        initialPosition: AssetListInitialPosition?
    ) {
        currentNavigationController.showAssets(
            accountSource: accountSource,
            selectedTab: selectedTab,
            collectionsFilter: collectionsFilter,
            initialPosition: initialPosition
        )
    }

    func focusSidebarAccount(accountId: String?, animated: Bool) {
        sidebarViewController.focusAccount(accountId, animated: animated)
    }

    func syncSidebarFocusWithHomeStack(animated: Bool) {
        guard selectedTab == .wallet else {
            focusSidebarAccount(accountId: nil, animated: animated)
            return
        }
        guard let homeNC = navControllersByTabId[.wallet],
              let splitHomeVC = homeNC.topViewController as? SplitHomeVC,
              case .accountId(let accountId) = splitHomeVC.splitHomeAccountContext.source else {
            focusSidebarAccount(accountId: nil, animated: animated)
            return
        }
        focusSidebarAccount(accountId: accountId, animated: animated)
    }

    private var currentNavigationController: WNavigationController {
        navControllersByTabId[selectedTab]
            ?? navControllersByTabId[.wallet]
            ?? { fatalError("wallet nav controller missing — required tab invariant broken") }()
    }

    private func isTemporarySplitHome(_ splitHomeVC: SplitHomeVC, accountId: String) -> Bool {
        guard case .accountId(let splitHomeAccountId) = splitHomeVC.splitHomeAccountContext.source else { return false }
        guard splitHomeVC.splitHomeAccountContext.account.isTemporaryView else { return false }
        return splitHomeAccountId == accountId
    }

    private static func makeNavigationStackPlaceholder() -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        return viewController
    }

    private func installSidebarEdgeCover(
        in navigationController: WNavigationController,
        color: UIColor,
        isVisible: @escaping () -> Bool = { true }
    ) {
        let edgeCoverView = EdgeGradientView()
        edgeCoverView.color = color.withAlphaComponent(0.8)
        edgeCoverView.isHidden = true
        navigationController.view.clipsToBounds = false
        navigationController.view.addSubview(edgeCoverView)
        sidebarEdgeCoverEntries.append(
            SidebarEdgeCoverEntry(
                navigationController: navigationController,
                view: edgeCoverView,
                color: color,
                isVisible: isVisible
            )
        )
    }

    private func updateSidebarEdgeCoverFrames() {
        guard traitCollection.horizontalSizeClass == .regular,
              !isCollapsed,
              displayMode != .secondaryOnly,
              sidebarNavigationController.view.superview != nil else {
            hideSidebarEdgeCovers()
            return
        }

        let sidebarFrame = view.convert(sidebarNavigationController.view.bounds, from: sidebarNavigationController.view)
        let isSidebarOnTrailingEdge = sidebarFrame.midX > view.bounds.midX
        let isRightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let outerGap = isSidebarOnTrailingEdge
            ? view.bounds.maxX - sidebarFrame.maxX
            : sidebarFrame.minX - view.bounds.minX
        guard outerGap > 1 else {
            hideSidebarEdgeCovers()
            return
        }

        let targetFrame: CGRect
        let direction: EdgeGradientView.Direction

        if isSidebarOnTrailingEdge {
            targetFrame = CGRect(
                x: view.bounds.maxX - outerGap - sidebarEdgeFadeWidth,
                y: view.bounds.minY,
                width: outerGap + sidebarEdgeFadeWidth,
                height: view.bounds.height
            )
            direction = isRightToLeft ? .leading : .trailing
        } else {
            targetFrame = CGRect(
                x: view.bounds.minX,
                y: view.bounds.minY,
                width: outerGap + sidebarEdgeFadeWidth,
                height: view.bounds.height
            )
            direction = isRightToLeft ? .trailing : .leading
        }

        for entry in sidebarEdgeCoverEntries {
            guard entry.navigationController.view.window != nil,
                  entry.isVisible() else {
                entry.view.isHidden = true
                continue
            }
            entry.view.color = entry.color.withAlphaComponent(0.8)
            entry.view.direction = direction
            entry.view.solidEdgeLength = outerGap
            entry.view.frame = entry.navigationController.view.convert(targetFrame, from: view)
            entry.view.isHidden = false
            entry.navigationController.view.bringSubviewToFront(entry.view)
        }
    }

    private func hideSidebarEdgeCovers() {
        for entry in sidebarEdgeCoverEntries {
            entry.view.isHidden = true
        }
    }
}

extension SplitRootViewController: RootSearchToolbarHost {
    func setSearchVisible(_ isVisible: Bool, coordinator: (any UIViewControllerTransitionCoordinator)?) {
        sidebarNavigationController.setSearchVisible(isVisible, coordinator: coordinator)
        updateNavigationPlacement()
    }

    var searchNavigationController: WNavigationController? { navControllersByTabId[selectedTab] }
    var showsRootSearchToolbar: Bool { [.wallet, .market, .agent, .explore].contains(selectedTab) }
    var searchRootContentControllers: [UIViewController] {
        guard showsRootSearchToolbar, let root = searchNavigationController?.viewControllers.first else { return [] }
        return [root]
    }
    var searchEditingNavigator: NftsEditingNavigator? {
        (searchNavigationController?.viewControllers.first as? SplitHomeVC)?.editingNavigator
    }
}

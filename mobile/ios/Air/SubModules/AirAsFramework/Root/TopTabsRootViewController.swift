import ContextMenuKit
import SwiftUI
import SwiftNavigation
import UIKit
import UIAgent
import UIBrowser
import UIAssets
import UIComponents
import UIHome
import UISettings
import WalletContext
import WalletCore

private let topTabsNavigationBarHeight: CGFloat = 44
private let topTabsSegmentedControlHeight: CGFloat = 40
private let topTabsNavigationBarSpacing: CGFloat = 10

@MainActor
final class TopTabsRootViewController: WViewController, VisibleContentProviding {
    private enum Page: CaseIterable {
        case wallet
        case market
        case agent
        case explore

        init?(tabId: AppTabId) {
            switch tabId {
            case .wallet: self = .wallet
            case .market: self = .market
            case .agent: self = .agent
            case .explore: self = .explore
            default: return nil
            }
        }

        var navigationTitle: String {
            switch self {
            case .wallet: lang("Wallet")
            case .market: lang("Market")
            case .agent: lang("Agent")
            case .explore: lang("Explore")
            }
        }

        var tabId: AppTabId {
            switch self {
            case .wallet: .wallet
            case .market: .market
            case .agent: .agent
            case .explore: .explore
            }
        }

        var menuDescription: String {
            switch self {
            case .wallet: lang("View your assets and activity")
            case .market: lang("$perps_explore_market")
            case .agent: lang("Ask AI and follow the news")
            case .explore: lang("$perps_explore_apps")
            }
        }

        var menuIconName: String {
            switch self {
            case .wallet: "TabMenuWallet"
            case .market: "TabMenuMarket"
            case .agent: "TabMenuAgent"
            case .explore: "TabMenuApps"
            }
        }

        var menuAnimationName: String {
            switch self {
            case .wallet: "tab_menu_wallet"
            case .market: "tab_menu_market"
            case .agent: "tab_menu_agent"
            case .explore: "tab_menu_explore"
            }
        }
    }

    private(set) var homeVC: HomeVC {
        didSet {
            oldValue.onWalletAssetsEditingStateChange = nil
            oldValue.onUpdateStatusChange = nil
            if isViewLoaded {
                observeHomeWalletAssetsEditingState()
                observeHomeUpdateStatus()
            }
        }
    }

    private let walletPage: TopTabsPageViewController
    private let marketPage: TopTabsPageViewController
    private let agentPage: TopTabsPageViewController
    private let explorePage: TopTabsPageViewController

    private var pager: WPagerViewController!
    /// The pages in the user's tab order; the pager, the segmented control and the side tab bar follow it
    private var pageOrder = TopTabsRootViewController.pageOrder(for: AppTabManager.shared.orderedTabIds)
    private var segmentedControl: WSegmentedControl!
    private let tabControlContainer = UIView()
    private var headerContentView: UIView?
    private var horizontalHeaderConstraints: [NSLayoutConstraint] = []
    private var sideHeaderConstraints: [NSLayoutConstraint] = []
    private var sideHeaderCenterConstraint: NSLayoutConstraint?
    private var sideHeaderTopConstraint: NSLayoutConstraint?
    private var sideTabTopConstraint: NSLayoutConstraint?
    private var sideTabHeightConstraint: NSLayoutConstraint?
    private enum SideTabEdge { case left, right }
    private var sideTabEdge: SideTabEdge?
    private var sideTabBar: UIView?

    override var hideNavigationBar: Bool {
        sideTabEdge != nil && (selectedPage != .wallet || homeVC.walletAssetsEditingNavigator?.state.editingState == nil)
    }
    private var navigationBarTitleWidthConstraint: NSLayoutConstraint?
    private var tabControlTrailingConstraint: NSLayoutConstraint?
    private var toolbarSettingsObservation: NSObjectProtocol?
    private var accountVisibilityAnimationID: UUID?
    private var accountButtonPlacement: (isHidden: Bool, trailingSpacing: CGFloat)?
    private var headerPlatterTransition: AgentHeaderPlatterTransition?
    /// A chat composed in the list is taking the screen's place, carrying the header with it
    private var isPresentingComposedChat = false
    /// The tabs' content as they last showed, for a pop that brings them back while they are not on screen
    private var tabsTransitionSnapshot: UIView?
    private lazy var composeHeaderSwap = AgentComposeHeaderSwap { [weak self] in
        self?.view.window?.endEditing(true)
    }
    private let accountSwitcherButton = WalletAccountButton()
    let searchController: RootSearchToolbarController
    var presentHiddenTab = presentTabModally
    private var accountSwitcherMenuInteraction: ContextMenuInteraction?
    private var isSearchVisible: Bool { searchController.isSearchVisible }

    private var accountObservation: ObserveToken?
    private struct TintedBackground {
        weak var view: UIView?
        let original: UIColor?
    }
    private var tintedPageBackgrounds: [ObjectIdentifier: [TintedBackground]] = [:]
    private var appliedPageTintShares: [Page: CGFloat?] = [:]
    private var sharedNavigationPaths: [Page: [UIViewController]] = [:]
    /// The screen opens on the first page in the user's tab order
    private var activePage: Page = TopTabsRootViewController.pageOrder(for: AppTabManager.shared.orderedTabIds)[0] {
        didSet {
            title = activePage.navigationTitle
        }
    }
    private var standardSettingsRootViewController: SettingsVC?
    private var pendingStandardSettingsStack: [UIViewController]?
    private var detachedStandardSettingsStackForMigration: [UIViewController]?
    private var didPrepareStandardNavigationMigration = false

    private var sharedMainNavigationController: WNavigationController? {
        return navigationController as? WNavigationController
    }

    var visibleContentProviderViewController: UIViewController {
        if let visibleViewController = sharedMainNavigationController?.visibleViewController,
           visibleViewController !== self {
            return visibleViewController
        }
        return page(for: selectedPage).contentViewController
    }

    var currentTabId: AppTabId {
        if isShowingStandardSettings {
            return .settings
        }
        return switch selectedPage {
        case .explore: .explore
        case .market: .market
        case .agent: .agent
        case .wallet: .wallet
        }
    }

    var isHomeRootSelected: Bool {
        guard currentTabId == .wallet else { return false }
        return sharedMainNavigationController?.viewControllers.count == 1
            && sharedMainNavigationController?.viewControllers.first === self
    }

    private var selectedPage: Page {
        guard let pager else { return activePage }
        return page(at: pager.selectedIndex) ?? .wallet
    }

    private static func pageOrder(for ids: [AppTabId]) -> [Page] {
        let order = ids.compactMap(Page.init(tabId:))
        return order + Page.allCases.filter { !order.contains($0) }
    }

    private func pageIndex(of page: Page) -> Int {
        pageOrder.firstIndex(of: page)!
    }

    private func page(at index: Int) -> Page? {
        pageOrder.indices.contains(index) ? pageOrder[index] : nil
    }

    init(searchController: RootSearchToolbarController = RootSearchToolbarController()) {
        self.searchController = searchController
        let homeVC = HomeVC(
            rootNavigationStyle: .topTabsNavigationBar,
            showsActionsRow: WalletActionButtonsSettings.showsActionButtonsRow
        )
        self.homeVC = homeVC
        self.walletPage = TopTabsPageViewController { homeVC }
        self.marketPage = TopTabsPageViewController {
            MarketVC(showsLargeTitle: false, usesTopTabsChrome: true)
        }
        self.agentPage = TopTabsPageViewController {
            AgentThreadListVC(userDefaults: .standard)
        }
        self.explorePage = TopTabsPageViewController {
            ExploreTabVC(showsSearchBar: false, showsLargeTitle: false, usesTopTabsChrome: true)
        }

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = activePage.navigationTitle
        view.backgroundColor = .air.groupedBackground

        let pages = [walletPage, marketPage, agentPage, explorePage]
        AgentHeaderPlatterTransition.installBetweenChats()
        searchController.attach(to: self)
        pages.forEach { page in
            page.onLoadContent = { [weak self] in self?.applyChromeInsets(to: $0) }
        }
        agentPage.onLoadContent = { [weak self] controller in
            self?.applyChromeInsets(to: controller)
            self?.installAgentBottomBar(from: controller)
        }
        pages.compactMap(\.loadedContentViewController).forEach(applyChromeInsets)
        agentPage.loadedContentViewController.map(installAgentBottomBar)
        configurePager()
        configureToolbarPaging()
        observeHomeWalletAssetsEditingState()
        observeAccountSwitcher()
        observeHomeUpdateStatus()
        toolbarSettingsObservation = NotificationCenter.default.addObserver(
            forName: ToolbarSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAccountButtonPlacement(animated: true) }
        }
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge + [UITraitLayoutDirection.self]) { (controller: TopTabsRootViewController, _: UITraitCollection) in
                controller.updateTabBarPlacement()
            }
        }
        updateTabBarPlacement()
        updateAccountButtonPlacement(animated: false)
    }

    deinit {
        if let toolbarSettingsObservation { NotificationCenter.default.removeObserver(toolbarSettingsObservation) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTabBarPlacement()
        animateTabsChatHandoff(isCollapsing: false)
        if let coordinator = transitionCoordinator, coordinator.isAnimated {
            // The header lives in the navigation bar's title view, which stays put while this screen springs past the
            // leading edge after a fast swipe back: the capsules move along with the screen so they don't show beside it.
            // Their glass takes the move from the title view around its container, not from the container itself.
            NavigationOvershootFollower.follow(coordinator) { [weak self] offset, _ in
                self?.tabControlContainer.transform = offset == 0 ? .identity : CGAffineTransform(translationX: offset, y: 0)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.cancelInteraction() }
        animateTabsChatHandoff(isCollapsing: true)
    }

    /// Pushing a chat from the Agent list turns the tabs' capsule into the chat's title pill, out of which its threads
    /// button grows, and the avatar's into its more button; popping turns them back
    private func animateTabsChatHandoff(isCollapsing: Bool) {
        if isPresentingComposedChat {
            // The composed chat's own transition carries the header; the new chat's header steps aside under it
            composeHeaderSwap.setActive(false, animated: false)
            updatePagingEnabled()
            return
        }
        headerPlatterTransition?.cancel()
        headerPlatterTransition = nil
        if isCollapsing, composeHeaderSwap.isActive {
            // A sent question's chat has the new chat's header in the same place; the bar's crossfade carries it
            let accepted = transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else { return }
                self?.composeHeaderSwap.setActive(false, animated: false)
            } ?? false
            if !accepted { composeHeaderSwap.setActive(false, animated: false) }
            return
        }
        guard sideTabEdge == nil, selectedPage == .agent, segmentedControl != nil,
              let window = view.window ?? navigationController?.view.window,
              let coordinator = transitionCoordinator, coordinator.isAnimated,
              let chat = coordinator.viewController(forKey: isCollapsing ? .to : .from) as? any AgentChatNavigationHandoff else {
            return
        }
        let listBar: @MainActor () -> AgentHeaderPlatterTransition.Bar = { [weak self] in
            self?.makeListHeaderBar() ?? AgentHeaderPlatterTransition.Bar()
        }
        let chatBar: @MainActor () -> AgentHeaderPlatterTransition.Bar = { [weak chat] in
            AgentHeaderPlatterTransition.Bar.chat(chat)
        }
        // The chat's title pill swells a third as wide as it turns back into the tabs, as tall as ever
        let transition = AgentHeaderPlatterTransition(
            outgoing: isCollapsing ? listBar : chatBar,
            incoming: isCollapsing ? chatBar : listBar,
            pillSwellStrength: isCollapsing ? CGSize(width: 1, height: 1) : CGSize(width: 1 / 3, height: 1)
        )
        headerPlatterTransition = transition
        transition.run(in: window, alongside: coordinator)
    }

    /// A question sent while the list composes one, from its field or its suggestions, continues on the same screen: the
    /// chat takes the list's place without sliding in, its content fading in over the list's, and the new chat's header
    /// turns into the chat's where it is. Returns false when the chat should be pushed as usual.
    private func presentComposedChat(_ chat: UIViewController) -> Bool {
        guard composeHeaderSwap.isActive, let navigationController = sharedMainNavigationController,
              navigationController.topViewController === self, navigationController.transitionCoordinator == nil,
              let window = view.window, chat is any AgentChatNavigationHandoff else { return false }
        // The field gives up the keyboard first, and the chat comes on the next turn of the run loop, once nothing on
        // this screen is editing: a field still editing when the chat covers it would take the keyboard back as the
        // chat closes
        isPresentingComposedChat = true
        searchController.agentBar.beginComposedChatHandoff()
        window.endEditing(true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let isShown = showComposedChat(chat)
            isPresentingComposedChat = false
            if !isShown {
                composeHeaderSwap.setActive(false, animated: false)
                updatePagingEnabled()
                navigationController.pushViewController(chat, animated: true)
            }
        }
        return true
    }

    private func showComposedChat(_ chat: UIViewController) -> Bool {
        guard composeHeaderSwap.isActive, let navigationController = sharedMainNavigationController,
              navigationController.topViewController === self, navigationController.transitionCoordinator == nil,
              let window = view.window, let handoff = chat as? any AgentChatNavigationHandoff else { return false }
        headerPlatterTransition?.cancel()
        let transition = AgentHeaderPlatterTransition(
            outgoing: { [weak self] in self?.composeHeaderSwap.makeBar() ?? AgentHeaderPlatterTransition.Bar() },
            incoming: { [weak handoff] in AgentHeaderPlatterTransition.Bar.chat(handoff) }
        )
        headerPlatterTransition = transition
        transition.run(in: window) {
            let push = { navigationController.pushViewController(chat, animated: false) }
            if UIAccessibility.isReduceMotionEnabled {
                push()
            } else {
                UIView.transition(
                    with: navigationController.view,
                    duration: 0.25,
                    options: [.transitionCrossDissolve, .allowUserInteraction],
                    animations: push
                )
            }
            navigationController.view.layoutIfNeeded()
        }
        return true
    }

    /// The list header's capsules for the header transitions: the tabs and the wallet avatar
    private func makeListHeaderBar() -> AgentHeaderPlatterTransition.Bar {
        let hasAvatar = accountButtonPlacement?.isHidden != true
        // The tabs and the avatar share one glass container, which the transition hides as a whole: hidden one by
        // one, each would linger a moment as the container merges it away
        return AgentHeaderPlatterTransition.Bar(
            pill: AgentHeaderPlatterTransition.Capsule(
                view: segmentedControl,
                makeItem: { [weak self] in self?.makeTabsTransitionItem() },
                shouldSwapOnHandOff: true,
                shouldKeepContentScale: true,
                hidingView: tabControlContainer
            ),
            trailing: hasAvatar ? AgentHeaderPlatterTransition.Capsule(
                view: accountSwitcherButton,
                makeItem: { [weak self] in self?.accountSwitcherButton.makeContentCopy() },
                hidingView: tabControlContainer
            ) : nil,
            // With the avatar in the bottom toolbar, the chat's more button grows out of the tabs
            isTrailingGrowingFromPill: !hasAvatar
        )
    }

    /// The tabs' content for the header transition: taken fresh while they show, kept for the way back
    private func makeTabsTransitionItem() -> UIView? {
        if let snapshot = segmentedControl.makeContentSnapshot() {
            tabsTransitionSnapshot = snapshot
            return snapshot
        }
        guard let snapshot = tabsTransitionSnapshot else { return nil }
        snapshot.removeFromSuperview()
        snapshot.transform = .identity
        snapshot.alpha = 1
        return snapshot
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installSettingsMorph()
        settingsMorphSource = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTabBarPlacement()
        let availableWidth = max(0, view.bounds.width - 32)
        if navigationBarTitleWidthConstraint?.constant != availableWidth {
            navigationBarTitleWidthConstraint?.constant = availableWidth
        }
    }

    func discardSearch() { searchController.discardSearch() }

    func finishPaging() { pager?.finishPaging() }

    func applyTabConfiguration(_ orderedIds: [AppTabId]) {
        let order = Self.pageOrder(for: orderedIds)
        guard order != pageOrder else { return }
        pageOrder = order
        guard isViewLoaded, let pager, let segmentedControl else { return }
        let items = segmentedControl.model.items
        segmentedControl.model.setItems(order.compactMap { page in
            items.first { $0.id == page.tabId.rawValue }
        })
        pager.reorderPages(order.map(\.tabId.rawValue))
        segmentedControl.setPagingProgress(CGFloat(pager.selectedIndex))
        updateAgentBottomBar(committedIndex: pager.committedIndex)
        updateSideTabBarOrder()
    }

    /// Saves the order the tab menu or the side tab bar was given. A page shown without being in the user's order
    /// keeps its place after the others
    private func reorderTabs(_ ids: [AppTabId]) {
        AppTabManager.shared.reorderTabs(ids.filter { AppTabManager.shared.contains($0) })
        updateSideTabBarOrder()
    }

    /// The side tab bar takes its items once, so it is built again when the pages' order differs from its own. A bar
    /// that moved a tab itself already shows the order
    private func updateSideTabBarOrder() {
        guard let sideTabBar else { return }
        if #available(iOS 26.0, *),
           (sideTabBar as? WVerticalTabBar)?.itemIds == pageOrder.map(\.tabId.rawValue) {
            return
        }
        sideTabBar.removeFromSuperview()
        self.sideTabBar = nil
        sideTabEdge = nil
        updateTabBarPlacement()
    }

    func takeNavigationStack(for id: AppTabId, keepingRoot: Bool) -> [UIViewController]? {
        prepareStandardNavigationMigrationIfNeeded()
        if id == .settings {
            return detachedStandardSettingsStackForMigration
        }
        guard let page = page(for: id), let pageValue = pageValue(for: id) else { return nil }
        let path = sharedNavigationPaths[pageValue] ?? []
        // An unused page has nothing to migrate; do not run its factory while leaving this layout.
        guard page.loadedContentViewController != nil || !path.isEmpty else { return nil }
        let stack = [page.contentViewController] + path
        stack.forEach(removeChrome)
        return stack
    }

    func setNavigationStack(_ stack: [UIViewController], for id: AppTabId) {
        if id == .settings {
            setPendingStandardSettingsStack(stack)
            return
        }
        guard !stack.isEmpty,
              let page = page(for: id),
              let pageValue = pageValue(for: id) else {
            return
        }
        let rootViewController = stack[0]
        page.setContentViewController(rootViewController)
        if id == .wallet, let homeVC = rootViewController as? HomeVC {
            self.homeVC = homeVC
        }
        sharedNavigationPaths[pageValue] = Array(stack.dropFirst())
        stack.forEach(applyChromeInsets)
        if pageValue == activePage {
            installSharedNavigationPath(for: pageValue)
        }
        updateRootChromeVisibilityForSelectedPage()
    }

    func setNavigationPath(_ path: [UIViewController], for id: AppTabId) {
        if id == .settings {
            setPendingStandardSettingsStack([SettingsVC()] + path)
            return
        }
        guard let pageValue = pageValue(for: id) else { return }
        sharedNavigationPaths[pageValue] = path
        path.forEach(applyChromeInsets)
        if pageValue == activePage {
            installSharedNavigationPath(for: pageValue)
        }
        updateRootChromeVisibilityForSelectedPage()
    }

    @discardableResult
    func selectTab(_ id: AppTabId, popToRoot: Bool = false, animated: Bool = true) -> Bool {
        loadViewIfNeeded()

        if id == .settings {
            return showStandardSettings(
                path: nil,
                popToRoot: popToRoot,
                animated: animated
            )
        }

        let page: Page
        switch id {
        case .wallet: page = .wallet
        case .market: page = .market
        case .agent: page = .agent
        case .explore: page = .explore
        default: return false
        }
        if page != activePage {
            discardSearch()
            captureSharedNavigationPath(for: activePage)
            sharedMainNavigationController?.setViewControllers([self], animated: false)
        }
        // The pager can call its completion delegate synchronously.
        activePage = page
        if popToRoot {
            sharedNavigationPaths[page] = []
        }
        let index = pageIndex(of: page)
        if animated, index != pager.selectedIndex {
            segmentedControl.beginSelectionScroll(toItemId: id.rawValue)
        }
        pager.select(index: index, animated: animated)
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.select(index, animated: animated) }
        installSharedNavigationPath(for: page)
        return true
    }

    func showAgentNewsChat(_ controller: UIViewController) {
        guard AppTabManager.shared.contains(.agent) else {
            presentHiddenTab(.agent, topViewController() ?? self, { _ in [controller] })
            return
        }
        discardSearch()
        selectTab(.agent, popToRoot: true, animated: false)
        sharedMainNavigationController?.pushViewController(
            controller, animated: sharedMainNavigationController?.viewIfLoaded?.window != nil
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
        discardSearch()
        selectTab(.agent, popToRoot: true, animated: false)
        guard let list = agentPage.contentViewController as? AgentThreadListVC else { return }
        sharedMainNavigationController?.pushViewController(
            list.makeNewsFeedViewController(requestedDigestId: digestId),
            animated: sharedMainNavigationController?.viewIfLoaded?.window != nil
        )
    }

    func showAgent(query: String?, entryPoint: ApiAgentV2EntryPoint?) {
        discardSearch()
        selectTab(.agent, popToRoot: true, animated: false)
        sharedMainNavigationController?.pushViewController(
            AgentEntryPoint.makeNewChatViewController(query: query, entryPoint: entryPoint),
            animated: true
        )
    }

    func switchToHome(popToRoot: Bool) {
        selectTab(.wallet, popToRoot: popToRoot)
        if let rootViewController = view.window?.rootViewController,
           rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: true)
        }
    }

    func switchToSettings(path: [UIViewController]) {
        if let destination = path.last, pushFromSearch(destination) { return }
        _ = showStandardSettings(
            path: path,
            popToRoot: false,
            animated: true
        )
    }

    @discardableResult
    func pushFromSearch(_ viewController: UIViewController) -> Bool {
        searchController.pushFromSearch(viewController)
    }

    @discardableResult
    func pushOnSettingsRoot(_ viewController: UIViewController, animated: Bool = true) -> Bool {
        guard showStandardSettings(path: nil, popToRoot: false, animated: false),
              let sharedMainNavigationController else {
            return false
        }
        applyChromeInsets(to: viewController)
        sharedMainNavigationController.pushViewController(
            viewController,
            animated: animated && sharedMainNavigationController.viewIfLoaded?.window != nil
        )
        return true
    }

    func scrollToTop() {
        page(for: selectedPage).scrollToTop(animated: true)
    }

    private func configurePager() {
        let itemsInDefaultOrder = [
            SegmentedControlItem(
                id: AppTabId.wallet.rawValue,
                title: lang("Wallet"),
                isDeletable: false,
                accessibilityIdentifier: "tab_wallet",
                viewController: walletPage
            ),
            SegmentedControlItem(
                id: AppTabId.market.rawValue,
                title: lang("Market"),
                isDeletable: false,
                accessibilityIdentifier: "tab_market",
                viewController: marketPage
            ),
            SegmentedControlItem(
                id: AppTabId.agent.rawValue,
                title: lang("Agent"),
                isDeletable: false,
                accessibilityIdentifier: "tab_agent",
                viewController: agentPage
            ),
            SegmentedControlItem(
                id: AppTabId.explore.rawValue,
                title: lang("Explore"),
                isDeletable: false,
                accessibilityIdentifier: "tab_explore",
                viewController: explorePage
            ),
        ]
        let items = pageOrder.compactMap { page in
            itemsInDefaultOrder.first { $0.id == page.tabId.rawValue }
        }

        let model = SegmentedControlModel(
            items: items,
            selection: .init(item1: activePage.tabId.rawValue),
            primaryColor: .tintColor,
            capsuleColor: .air.thumbBackground,
            style: .compactRootHeader
        )
        let segmentedControl = WSegmentedControl(model: model, isGlassInteractive: true)
        if #available(iOS 26, *) {
            segmentedControl.tintAdjustmentMode = .normal
        }
        self.segmentedControl = segmentedControl
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.longPressContextMenuAccessibilityLabel = lang("Tabs")
        segmentedControl.longPressContextMenuProvider = SegmentedControlContextMenuProvider { [weak self, weak model] in
            let pages = (model?.items ?? []).compactMap { item in
                Page.allCases.first { $0.tabId.rawValue == item.id }
            }
            // Reduced motion and turned-off animations keep the static icons
            let areIconsAnimated = AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
            var menuOrder = pages
            return ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: pages.map { page in
                    .action(ContextMenuAction(
                        id: "tab_menu_\(page.tabId.rawValue)",
                        title: page.navigationTitle,
                        subtitle: page.menuDescription,
                        icon: .image(UIImage.airBundle(page.menuIconName), renderingMode: .template),
                        handler: { [weak self] in
                            guard let self, self.segmentedControl.model.items.contains(where: {
                                $0.id == page.tabId.rawValue
                            }) else { return }
                            let isSelected = self.pager.selectedIndex == self.pageIndex(of: page)
                            self.selectTab(page.tabId)
                            if isSelected { self.segmentedControl.centerSelectedItem(animated: true) }
                        },
                        animatedIcon: {
                            areIconsAnimated ? ContextMenuStickerIconView(animationName: page.menuAnimationName) : nil
                        }
                    ))
                }, onReorder: { sourceIndex, destinationIndex in
                    menuOrder.insert(menuOrder.remove(at: sourceIndex), at: destinationIndex)
                    self?.reorderTabs(menuOrder.map(\.tabId))
                }),
                backdrop: .none,
                popoverUsesSourceViewBounds: true,
                popoverDisablesInteractiveDismissal: true,
                style: ContextMenuStyle(minWidth: 340, maxWidth: 340, subtitleNumberOfLines: 2)
            )
        }
        model.onSelect = { [weak self] item in
            self?.selectTab(AppTabId(item.id))
        }

        let initialIndex = pageIndex(of: activePage)
        let pager = WPagerViewController(pages: pageOrder.map { page in
            .init(id: page.tabId.rawValue, makeViewController: { [unowned self] in self.page(for: page) })
        }, selectedIndex: initialIndex, preloadsPages: true)
        self.pager = pager
        segmentedControl.setPagingProgress(CGFloat(initialIndex))
        pager.onProgressChanged = { [weak self] progress in
            guard let self else { return }
            self.segmentedControl.setPagingProgress(progress.logicalOffset)
            let agent = self.pageIndex(of: .agent)
            if progress.source == agent, progress.destination != agent {
                self.updateAgentPaging(agentShare: 1 - progress.fraction, neighbor: self.page(at: progress.destination))
            } else if progress.destination == agent, progress.source != agent {
                self.updateAgentPaging(agentShare: progress.fraction, neighbor: self.page(at: progress.source))
            } else {
                self.updateAgentPaging(agentShare: progress.source == agent ? 1 : 0, neighbor: nil)
            }
        }
        pager.onSelectionChanged = { [weak self] index in
            self?.pagerDidSelect(index)
        }
        pager.onCommittedIndexChanged = { [weak self] index in
            self?.updateAgentBottomBar(committedIndex: index)
        }
        addChild(pager)
        view.addStretchedToBounds(subview: pager.view)
        pager.didMove(toParent: self)
        configureNavigationBarHeader(segmentedControl: segmentedControl)
    }

    private func configureNavigationBarHeader(segmentedControl: WSegmentedControl) {
        configureNavigationItemWithTransparentBackground()
        addCustomNavigationBarBackground(color: .clear)

        accountSwitcherButton.configure(account: AccountStore.account)
        accountSwitcherButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let accountSwitcherMenuInteraction = ContextMenuInteraction(
            triggers: [.longPress],
            configurationProvider: { sourceView in
                SwitchAccountMenu.makeConfiguration(sourceView: sourceView)
            }
        )
        accountSwitcherMenuInteraction.attach(to: accountSwitcherButton)
        self.accountSwitcherMenuInteraction = accountSwitcherMenuInteraction
        tabControlContainer.backgroundColor = .clear
        tabControlContainer.translatesAutoresizingMaskIntoConstraints = false
        let contentView: UIView
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            let effect = UIGlassContainerEffect()
            effect.spacing = topTabsNavigationBarSpacing
            let glassContainerView = UIVisualEffectView(effect: effect)
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            tabControlContainer.addSubview(glassContainerView)
            NSLayoutConstraint.activate([
                glassContainerView.leadingAnchor.constraint(equalTo: tabControlContainer.leadingAnchor),
                glassContainerView.trailingAnchor.constraint(equalTo: tabControlContainer.trailingAnchor),
                glassContainerView.topAnchor.constraint(equalTo: tabControlContainer.topAnchor),
                glassContainerView.bottomAnchor.constraint(equalTo: tabControlContainer.bottomAnchor),
            ])
            contentView = glassContainerView.contentView
        } else {
            contentView = tabControlContainer
        }
        headerContentView = contentView
        contentView.addSubview(accountSwitcherButton)
        contentView.addSubview(segmentedControl)
        composeHeaderSwap.install(in: contentView, tabs: segmentedControl, avatar: accountSwitcherButton) { [weak self] in
            self?.makeListHeaderBar() ?? AgentHeaderPlatterTransition.Bar()
        }
        navigationItem.titleView = tabControlContainer

        let titleWidthConstraint = tabControlContainer.widthAnchor.constraint(
            equalToConstant: max(0, view.bounds.width - 32)
        )
        navigationBarTitleWidthConstraint = titleWidthConstraint

        let tabControlTrailingConstraint = segmentedControl.trailingAnchor.constraint(
            equalTo: accountSwitcherButton.leadingAnchor, constant: -topTabsNavigationBarSpacing
        )
        self.tabControlTrailingConstraint = tabControlTrailingConstraint
        horizontalHeaderConstraints = [
            titleWidthConstraint,
            tabControlContainer.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),

            accountSwitcherButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            accountSwitcherButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            accountSwitcherButton.widthAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),
            accountSwitcherButton.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),

            segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabControlTrailingConstraint,
            segmentedControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: topTabsSegmentedControlHeight),
        ]
        NSLayoutConstraint.activate(horizontalHeaderConstraints)
    }

    private func updateTabBarPlacement() {
        guard segmentedControl != nil else { return }
        let edge: SideTabEdge?
        if #available(iOS 27.1, *) {
            switch traitCollection.verticalBarEdge {
            case .leading: edge = view.effectiveUserInterfaceLayoutDirection == .leftToRight ? .left : .right
            case .trailing: edge = view.effectiveUserInterfaceLayoutDirection == .leftToRight ? .right : .left
            default: edge = nil
            }
        } else {
            edge = nil
        }
        guard sideTabEdge != edge else {
            updateSideHeaderGeometry()
            return
        }
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.cancelInteraction() }
        composeHeaderSwap.setActive(false, animated: false)
        sideTabEdge = edge
        NSLayoutConstraint.deactivate(sideHeaderConstraints)
        sideHeaderConstraints = []
        sideHeaderCenterConstraint = nil
        sideHeaderTopConstraint = nil
        sideTabTopConstraint = nil
        sideTabHeightConstraint = nil
        if let edge, #available(iOS 27.1, *) {
            if sideTabBar == nil {
                let ids = pageOrder.map(\.tabId)
                let items = ids.compactMap { id -> WVerticalTabBar.Item? in
                    guard let registration = AppTabManager.shared.registration(for: id) else { return nil }
                    return .init(id: id.rawValue, title: registration.titleProvider(), image: registration.compactIcon)
                }
                let bar = WVerticalTabBar(items: items)
                bar.tintColor = .tintColor
                bar.onSelect = { [weak self] index, repeated in
                    guard let self, let page = self.page(at: index) else { return }
                    self.selectTab(page.tabId, popToRoot: repeated)
                    if repeated { self.scrollToTop() }
                }
                bar.onReorder = { [weak self, weak bar] _, _ in
                    guard let self, let bar else { return }
                    self.reorderTabs(bar.itemIds.map { AppTabId($0) })
                }
                bar.onExpandedFrameChange = { [weak self, weak bar] frame in
                    guard let self, let bar else { return }
                    self.searchController.setSideTabBarFrame(frame, in: bar)
                    if let frame, let bounds = bar.expansionBounds {
                        let button = self.accountSwitcherButton
                        let buttonFrame = CGRect(x: button.center.x - button.bounds.width / 2,
                                                 y: button.center.y - button.bounds.height / 2,
                                                 width: button.bounds.width, height: button.bounds.height)
                        let offset = getSideControlOffset(frame: buttonFrame, avoiding: self.view.convert(frame, from: bar),
                                                          within: self.view.convert(bounds, from: bar), isOnLeftEdge: bar.isOnLeftEdge)
                        button.transform = CGAffineTransform(translationX: offset.x, y: offset.y)
                    } else {
                        self.accountSwitcherButton.transform = .identity
                    }
                }
                bar.translatesAutoresizingMaskIntoConstraints = false
                sideTabBar = bar
                view.addSubview(bar)
            }
            (sideTabBar as? WVerticalTabBar)?.isOnLeftEdge = edge == .left
            (sideTabBar as? WVerticalTabBar)?.select(pageIndex(of: selectedPage), animated: false)
            NSLayoutConstraint.deactivate(horizontalHeaderConstraints)
            accountSwitcherButton.removeFromSuperview()
            accountSwitcherButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(accountSwitcherButton)
            navigationItem.titleView = nil
            if let bar = sideTabBar {
                let center = accountSwitcherButton.centerXAnchor.constraint(equalTo: view.leftAnchor)
                let top = accountSwitcherButton.topAnchor.constraint(equalTo: view.topAnchor)
                sideHeaderCenterConstraint = center
                sideHeaderTopConstraint = top
                let tabsTop = bar.topAnchor.constraint(equalTo: accountSwitcherButton.bottomAnchor,
                    constant: ToolbarSettings.configuration().showsAccounts ? -48 : 12)
                sideTabTopConstraint = tabsTop
                let height = bar.heightAnchor.constraint(equalToConstant: bar.intrinsicContentSize.height)
                sideTabHeightConstraint = height
                sideHeaderConstraints = [
                    center,
                    top,
                    accountSwitcherButton.widthAnchor.constraint(equalToConstant: 48),
                    accountSwitcherButton.heightAnchor.constraint(equalToConstant: 48),
                    bar.centerXAnchor.constraint(equalTo: accountSwitcherButton.centerXAnchor),
                    tabsTop,
                    bar.widthAnchor.constraint(equalToConstant: bar.intrinsicContentSize.width),
                    height,
                ]
                NSLayoutConstraint.activate(sideHeaderConstraints)
                updateSideHeaderGeometry()
            }
        } else {
            sideTabBar?.isHidden = true
            accountSwitcherButton.removeFromSuperview()
            accountSwitcherButton.translatesAutoresizingMaskIntoConstraints = false
            headerContentView?.addSubview(accountSwitcherButton)
            NSLayoutConstraint.activate(horizontalHeaderConstraints)
        }
        segmentedControl.accessibilityElementsHidden = edge != nil
        [walletPage, marketPage, agentPage, explorePage].compactMap(\.loadedContentViewController).forEach(applyChromeInsets)
        agentPage.loadedContentViewController.map(installAgentBottomBar)
        updateHomeWalletAssetsNavigationChrome()
        updateRootChromeVisibilityForSelectedPage()
    }

    private func updateSideHeaderGeometry() {
        guard #available(iOS 27.1, *), let edge = sideTabEdge, let bar = sideTabBar,
              let container = navigationController?.view, view.isDescendant(of: container) else { return }
        // The navigation container owns the bar region. Its content already has
        // the side-bar safe-area inset, which would move a content-local region inward.
        let region = container.layoutGuide(for: .bar(
            onEdge: edge == .left ? UIRectEdge.left : .right,
            extent: bar.intrinsicContentSize.width
        )).layoutFrame
        guard !region.isEmpty else { return }
        // Native vertical navigation groups have a 24 pt minimum outer margin.
        let origin = view.convert(CGPoint(x: region.midX, y: max(region.minY, container.bounds.minY + 24)), from: container)
        // Local constraints survive the root view being detached on a navigation push.
        sideHeaderCenterConstraint?.constant = origin.x - view.bounds.minX
        sideHeaderTopConstraint?.constant = origin.y - view.bounds.minY
        let top = origin.y + (ToolbarSettings.configuration().showsAccounts ? 0 : 60)
        let bottom = searchController.getSideToolbarFrame(in: view)?.minY
            ?? view.convert(CGPoint(x: region.midX, y: region.maxY), from: container).y
        sideTabHeightConstraint?.constant = min(bar.intrinsicContentSize.height, max(0, bottom - 12 - top))
        if let bar = bar as? WVerticalTabBar {
            let regionBottom = view.convert(CGPoint(x: region.midX, y: min(region.maxY, container.bounds.maxY - 24)), from: container).y
            let available = CGRect(x: view.bounds.minX, y: origin.y, width: view.bounds.width, height: max(0, regionBottom - origin.y))
            bar.expansionBounds = available.offsetBy(dx: -origin.x + bar.bounds.width / 2, dy: -top)
        }
    }

    func searchToolbarGeometryDidChange() {
        viewIfLoaded?.setNeedsLayout()
    }

    private func observeAccountSwitcher() {
        accountObservation = observe { [weak self] in
            guard let self else { return }
            let currentAccountId = AccountStore.currentAccountId
            accountSwitcherButton.configure(account: AccountStore.accountsById[currentAccountId])
        }
    }

    private func observeHomeUpdateStatus() {
        homeVC.onUpdateStatusChange = { [weak self] state, animated in
            self?.accountSwitcherButton.setUpdateStatus(state, animated: animated)
            self?.searchController.searchToolbar.accountsButton.setUpdateStatus(state, animated: animated)
        }
        accountSwitcherButton.setUpdateStatus(homeVC.updateStatus, animated: false)
        searchController.searchToolbar.accountsButton.setUpdateStatus(homeVC.updateStatus, animated: false)
    }

    private func updateAccountButtonPlacement(animated: Bool) {
        let movedToToolbar = ToolbarSettings.configuration().showsAccounts
        let isHidden = movedToToolbar
            || (sideTabEdge != nil && homeVC.walletAssetsEditingNavigator?.state.editingState != nil)
        let trailingSpacing = movedToToolbar ? topTabsNavigationBarHeight : -topTabsNavigationBarSpacing
        guard accountButtonPlacement?.isHidden != isHidden || accountButtonPlacement?.trailingSpacing != trailingSpacing else { return }
        accountButtonPlacement = (isHidden, trailingSpacing)
        let animationID = UUID()
        accountVisibilityAnimationID = animationID
        tabControlContainer.layoutIfNeeded()
        if sideTabEdge != nil { view.layoutIfNeeded() }
        sideTabTopConstraint?.constant = movedToToolbar ? -48 : 12
        tabControlTrailingConstraint?.constant = trailingSpacing
        accountSwitcherButton.isHidden = false
        accountSwitcherButton.isUserInteractionEnabled = !isHidden
        accountSwitcherButton.accessibilityElementsHidden = isHidden
        let updates = {
            self.accountSwitcherButton.setToolbarAppearance(showsBackground: !isHidden, showsContent: !isHidden)
            self.tabControlContainer.layoutIfNeeded()
            if self.sideTabEdge != nil { self.view.layoutIfNeeded() }
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.accountVisibilityAnimationID == animationID else { return }
            self.accountSwitcherButton.isHidden = isHidden
        }
        if animated, view.window != nil, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: updates, completion: completion)
        } else {
            UIView.performWithoutAnimation(updates)
            completion(true)
        }
    }

    private func updateRootChromeVisibilityForSelectedPage() {
        updateAccountButtonPlacement(animated: view.window != nil)
        searchController.updatePresentation()
    }

    private func installAgentBottomBar(from controller: UIViewController) {
        guard let list = controller as? AgentThreadListVC else { return }
        list.presentComposedChat = { [weak self] chat in self?.presentComposedChat(chat) ?? false }
        // A side tab bar keeps the toolbar beside the content, so the list lays out its own field there
        let isBarHostedInToolbar = sideTabEdge == nil
        list.setBottomBarHostedExternally(isBarHostedInToolbar)
        if isBarHostedInToolbar {
            searchController.agentBar.install(list.bottomBar)
        }
        updateAgentPaging(agentShare: selectedPage == .agent ? 1 : 0, neighbor: nil)
        updateAgentBottomBar(committedIndex: pager?.committedIndex ?? pageIndex(of: selectedPage))
    }

    /// The Agent tab's bar grows out of the toolbar once paging commits to the Agent tab, and goes back into it once
    /// paging commits elsewhere: as with Telegram's bars, nothing changes while the finger holds the pages
    private func updateAgentBottomBar(committedIndex: Int) {
        let isAgent = committedIndex == pageIndex(of: .agent)
        searchController.agentBar.isAvailable = true
        searchController.agentBar.setMorphProgress(sideTabEdge == nil && isAgent ? 1 : 0)
    }

    /// The Agent tab's white background fades in with paging on both the Agent list and the page beside it, so the two
    /// screens change color together.
    ///
    /// `agentShare` is how much of the transition the Agent tab occupies; `neighbor` is the other page in it.
    private func updateAgentPaging(agentShare: CGFloat, neighbor: Page?) {
        let share = min(1, max(0, agentShare))
        let list = agentPage.loadedContentViewController as? AgentThreadListVC
        list?.setTabTransitionProgress(share)
        for page in [Page.wallet, .market, .explore] {
            let tintShare: CGFloat? = page == neighbor && share > 0 && list != nil ? share : nil
            guard appliedPageTintShares[page] != tintShare else { continue }
            appliedPageTintShares[page] = tintShare
            tintPageBackground(self.page(for: page), with: tintShare.flatMap { list?.getBackgroundColor(for: $0) })
        }
    }

    /// Paints a page's grouped backgrounds with `color`, or restores them when `color` is nil. A screen that draws
    /// its background itself, in SwiftUI for example, takes the color through `WPagingBackgroundTinting`.
    private func tintPageBackground(_ page: TopTabsPageViewController, with color: UIColor?) {
        if let content = page.loadedContentViewController {
            let screen = (content as? UINavigationController)?.topViewController ?? content
            // The band under the bar changes color with the page, or the Agent tab's background meets it in a seam
            (screen as? WViewController)?.setCustomNavigationBarBackgroundTint(color)
            if let tinting = screen as? any WPagingBackgroundTinting {
                page.viewIfLoaded?.backgroundColor = color
                tinting.setPagingBackgroundColor(color)
                return
            }
        }
        let key = ObjectIdentifier(page)
        guard let color else {
            for entry in tintedPageBackgrounds.removeValue(forKey: key) ?? [] {
                entry.view?.backgroundColor = entry.original
            }
            return
        }
        if tintedPageBackgrounds[key] == nil {
            tintedPageBackgrounds[key] = findPageBackgroundViews(of: page).map { TintedBackground(view: $0, original: $0.backgroundColor) }
        }
        for entry in tintedPageBackgrounds[key] ?? [] {
            entry.view?.backgroundColor = color
        }
    }

    /// The page's views that show the grouped background: the page, its screen and that screen's scroll views
    private func findPageBackgroundViews(of page: TopTabsPageViewController) -> [UIView] {
        guard page.isViewLoaded, let content = page.loadedContentViewController else { return [] }
        let screen = (content as? UINavigationController)?.topViewController ?? content
        guard screen.isViewLoaded else { return [] }
        let grouped = UIColor.air.groupedBackground.resolvedColor(with: traitCollection)
        let candidates = [page.view, content.view, screen.view] + screen.view.subviews.filter { $0 is UIScrollView }
        var seen = Set<ObjectIdentifier>()
        return candidates.compactMap { $0 }.filter { view in
            guard seen.insert(ObjectIdentifier(view)).inserted else { return false }
            guard let background = view.backgroundColor?.resolvedColor(with: traitCollection) else {
                // A clear page shows the root's grouped background through it
                return view === page.view
            }
            return background.isApproximatelyEqual(to: grouped)
        }
    }

    private func applyChromeInsets(to controller: UIViewController) { searchController.applyChromeInsets(to: controller) }
    private func removeChrome(from controller: UIViewController) { searchController.removeChrome(from: controller) }

    private func observeHomeWalletAssetsEditingState() {
        homeVC.onWalletAssetsEditingStateChange = { [weak self] in
            self?.homeWalletAssetsEditingStateDidChange()
        }
        homeWalletAssetsEditingStateDidChange()
    }

    private func homeWalletAssetsEditingStateDidChange() {
        updateHomeWalletAssetsNavigationChrome()
        guard !isSearchVisible,
              selectedPage == .wallet,
              let navigationController = sharedMainNavigationController,
              navigationController.visibleViewController === self else {
            return
        }
        searchController.updatePresentation()
    }

    private var isWalletAssetsEditing = false

    /// Paging stops while the wallet's assets are edited and while a question is composed in the Agent list
    private func updatePagingEnabled() {
        pager?.isPagingEnabled = !isWalletAssetsEditing && !composeHeaderSwap.isActive
    }

    private func updateHomeWalletAssetsNavigationChrome() {
        // Keep the root item's controls in sync while a transient controller is presented.
        let isShowingWalletRoot = selectedPage == .wallet
            && sharedMainNavigationController?.topViewController === self
        let navigator = isShowingWalletRoot ? homeVC.walletAssetsEditingNavigator : nil
        let editingState = navigator?.state.editingState

        isWalletAssetsEditing = editingState != nil
        updatePagingEnabled()
        navigationItem.titleView = editingState == nil && sideTabEdge == nil ? tabControlContainer : UIView()
        if editingState != nil, #available(iOS 26.0, *) {
            (sideTabBar as? WVerticalTabBar)?.cancelInteraction()
        }
        sideTabBar?.isHidden = sideTabEdge == nil || editingState != nil
        updateAccountButtonPlacement(animated: false)
        if sharedMainNavigationController?.topViewController === self {
            sharedMainNavigationController?.setNavigationBarHidden(hideNavigationBar, animated: false)
        }

        switch editingState {
        case .reordering:
            navigationItem.leadingItemGroups = (navigator?.cancelEditingBarButtonItem
                .asSingleItemGroup()).map { [$0] } ?? []
            navigationItem.trailingItemGroups = (navigator?.commitEditingBarButtonItem
                .asSingleItemGroup()).map { [$0] } ?? []
        case .selection:
            navigationItem.leadingItemGroups = (navigator?.selectAllBarButtonItem
                .asSingleItemGroup()).map { [$0] } ?? []
            navigationItem.trailingItemGroups = (navigator?.cancelXEditingBarButtonItem
                .asSingleItemGroup()).map { [$0] } ?? []
        case nil:
            navigationItem.leadingItemGroups = []
            navigationItem.trailingItemGroups = []
        }
    }

    private func configureToolbarPaging() {
        let isPagingEnabled: () -> Bool = { [weak self] in
            guard let self,
                  let navigationController = sharedMainNavigationController else { return false }
            return navigationController.topViewController === self
                && navigationController.presentedViewController == nil
                && navigationController.transitionCoordinator == nil
                && !isSearchVisible
                && !searchController.isClosingSearch
                && !searchController.searchToolbar.isHidden
                && !composeHeaderSwap.isActive
        }
        pager.setAdditionalPagingGestureView(searchController.searchToolbar, isEnabled: isPagingEnabled)
        pager.setForwardNavigation(in: sharedMainNavigationController?.view ?? view, allowsEdgeNavigation: true, beginTransition: { [weak self] in
            guard let self, let navigationController = sharedMainNavigationController else { return nil }
            let settings = standardSettingsRootViewController ?? SettingsVC()
            standardSettingsRootViewController = settings
            applyChromeInsets(to: settings)
            return navigationController.beginInteractivePush(settings)
        }, isEnabled: isPagingEnabled)
    }

    private var settingsMorphSource: SettingsMorphSource?
    private let settingsMorphPressRecognizer = SettingsMorphPressRecognizer()

    private var canMorphSettings: Bool {
        guard IOS_26_MODE_ENABLED, AppStorageHelper.animations, UIView.areAnimationsEnabled,
              !UIAccessibility.isReduceMotionEnabled, !ToolbarSettings.configuration().showsAccounts,
              sideTabEdge == nil, !isSearchVisible, !composeHeaderSwap.isActive,
              accountButtonPlacement?.isHidden == false,
              navigationItem.titleView === tabControlContainer else { return false }
        if #available(iOS 27.1, *) {
            switch traitCollection.verticalBarEdge {
            case .leading, .trailing: return false
            default: break
            }
        }
        return true
    }

    private func installSettingsMorph() {
        guard #available(iOS 26, *), let navigationController = sharedMainNavigationController else { return }
        let bar = navigationController.navigationBar
        if settingsMorphPressRecognizer.view !== bar {
            bar.addGestureRecognizer(settingsMorphPressRecognizer)
        }
        navigationController.customTransitionProvider = { [weak self, weak navigationController] operation, from, to in
            guard let self, let navigationController, canMorphSettings,
                  !navigationController.isInteractivePopInProgress else { return nil }
            switch operation {
            case .push where from === self && to === standardSettingsRootViewController:
                settingsMorphSource = captureSettingsMorphSource()
                guard let source = settingsMorphSource else { return nil }
                return SettingsMorphTransition(isPush: true, source: source, navigationController: navigationController)
            case .pop where to === self && from === standardSettingsRootViewController:
                guard var source = settingsMorphSource, source.matches(navigationController.view) else { return nil }
                let bar = navigationController.navigationBar
                let isRTL = source.layoutDirection == .rightToLeft
                source.pressLift = settingsMorphPressRecognizer.recentLift(in: CGRect(
                    x: isRTL ? bar.bounds.width - 90 : 0, y: 0, width: 90, height: bar.bounds.height
                ))
                return SettingsMorphTransition(isPush: false, source: source, navigationController: navigationController)
            default:
                return nil
            }
        }
    }

    private func captureSettingsMorphSource() -> SettingsMorphSource? {
        guard canMorphSettings, let navigationView = sharedMainNavigationController?.view,
              let segmentedControl, segmentedControl.window != nil,
              accountSwitcherButton.window != nil, !accountSwitcherButton.isHidden,
              let titles = segmentedControl.makeContentSnapshot(),
              let bar = sharedMainNavigationController?.navigationBar else { return nil }
        return SettingsMorphSource(
            segmentedFrame: segmentedControl.convert(segmentedControl.bounds, to: navigationView),
            segmentedSnapshot: titles,
            avatarGlassFrame: accountSwitcherButton.convert(accountSwitcherButton.bounds, to: navigationView),
            avatarFrame: accountSwitcherButton.convert(accountSwitcherButton.avatarFrame, to: navigationView),
            containerSize: navigationView.bounds.size,
            safeAreaInsets: navigationView.safeAreaInsets,
            layoutDirection: navigationView.effectiveUserInterfaceLayoutDirection,
            pressLift: settingsMorphPressRecognizer.recentLift(in: accountSwitcherButton.convert(accountSwitcherButton.bounds, to: bar))
        )
    }

    @objc private func openSettings() {
        selectTab(.settings)
    }

    private var isShowingStandardSettings: Bool {
        guard let sharedMainNavigationController else { return false }
        return standardSettingsIndex(in: sharedMainNavigationController.viewControllers) != nil
    }

    @discardableResult
    private func showStandardSettings(
        path: [UIViewController]?,
        popToRoot: Bool,
        animated: Bool
    ) -> Bool {
        guard let sharedMainNavigationController else { return false }

        loadViewIfNeeded()
        // Older UIKit can drop an animated stack change before the container is onscreen.
        let animated = animated && sharedMainNavigationController.viewIfLoaded?.window != nil

        let currentStack = sharedMainNavigationController.viewControllers
        let existingSettingsIndex = standardSettingsIndex(in: currentStack)
        let baseStack = existingSettingsIndex.map { Array(currentStack[..<$0]) } ?? currentStack

        if let pendingStandardSettingsStack {
            self.pendingStandardSettingsStack = nil
            let settingsStack = popToRoot
                ? Array(pendingStandardSettingsStack.prefix(1))
                : pendingStandardSettingsStack
            settingsStack.forEach(applyChromeInsets)
            sharedMainNavigationController.setViewControllers(
                baseStack + settingsStack,
                animated: animated
            )
            updateRootChromeVisibilityForSelectedPage()
            return true
        }

        let settingsRoot: SettingsVC
        if let existingSettingsIndex,
           let existingRoot = currentStack[existingSettingsIndex] as? SettingsVC {
            settingsRoot = existingRoot
        } else if let standardSettingsRootViewController {
            settingsRoot = standardSettingsRootViewController
        } else {
            settingsRoot = SettingsVC()
        }
        standardSettingsRootViewController = settingsRoot
        applyChromeInsets(to: settingsRoot)

        if existingSettingsIndex == nil, path == nil, !popToRoot {
            sharedMainNavigationController.pushViewController(settingsRoot, animated: animated)
            return true
        }

        let settingsPath: [UIViewController]
        if popToRoot {
            settingsPath = []
        } else if let path {
            settingsPath = path
        } else if let existingSettingsIndex {
            settingsPath = Array(currentStack.dropFirst(existingSettingsIndex + 1))
        } else {
            settingsPath = []
        }
        settingsPath.forEach(applyChromeInsets)
        sharedMainNavigationController.setViewControllers(
            baseStack + [settingsRoot] + settingsPath,
            animated: animated
        )
        updateRootChromeVisibilityForSelectedPage()
        return true
    }

    private func standardSettingsIndex(in stack: [UIViewController]) -> Int? {
        // A Settings result above Search belongs to its source tab, even after
        // Search expires. Only the explicitly opened Settings root is shared.
        guard let standardSettingsRootViewController else { return nil }
        return stack.firstIndex { $0 === standardSettingsRootViewController }
    }

    private func setPendingStandardSettingsStack(_ stack: [UIViewController]) {
        guard let settingsRoot = stack.first as? SettingsVC else { return }
        standardSettingsRootViewController = settingsRoot
        pendingStandardSettingsStack = stack
        stack.forEach(applyChromeInsets)
    }

    private func prepareStandardNavigationMigrationIfNeeded() {
        guard !didPrepareStandardNavigationMigration else { return }
        didPrepareStandardNavigationMigration = true

        if let sharedMainNavigationController {
            sharedNavigationPaths[activePage] = Array(
                sharedMainNavigationController.viewControllers.dropFirst()
            )
            sharedMainNavigationController.setViewControllers([self], animated: false)
            // Finish UIKit's nonanimated removal before another navigation container
            // takes ownership of the outgoing detail controllers.
            sharedMainNavigationController.viewIfLoaded?.layoutIfNeeded()
        }

        for page in [Page.wallet, .market, .agent, .explore] {
            guard let path = sharedNavigationPaths[page],
                  let settingsIndex = standardSettingsIndex(in: path) else {
                continue
            }
            detachedStandardSettingsStackForMigration = Array(path[settingsIndex...])
            sharedNavigationPaths[page] = Array(path[..<settingsIndex])
            return
        }

        detachedStandardSettingsStackForMigration = pendingStandardSettingsStack
        pendingStandardSettingsStack = nil
    }

    private func captureSharedNavigationPath(for page: Page) {
        guard let sharedMainNavigationController else { return }
        let path = Array(sharedMainNavigationController.viewControllers.dropFirst())
        // Settings is shared across tabs and must not reopen when returning to the source tab.
        let endIndex = standardSettingsIndex(in: path) ?? path.endIndex
        sharedNavigationPaths[page] = Array(path[..<endIndex])
    }

    private func installSharedNavigationPath(for page: Page) {
        guard let sharedMainNavigationController else { return }
        let path = sharedNavigationPaths[page] ?? []
        let viewControllers = [self] + path
        if !sharedMainNavigationController.viewControllers.elementsEqual(viewControllers, by: { $0 === $1 }) {
            sharedMainNavigationController.setViewControllers(viewControllers, animated: false)
        }
        updateRootChromeVisibilityForSelectedPage()
    }

    private func navigationController(for page: Page) -> WNavigationController? {
        sharedMainNavigationController
    }

    private func page(for id: AppTabId) -> TopTabsPageViewController? {
        return switch id {
        case .wallet: walletPage
        case .market: marketPage
        case .agent: agentPage
        case .explore: explorePage
        default: nil
        }
    }

    private func pageValue(for id: AppTabId) -> Page? {
        return switch id {
        case .wallet: .wallet
        case .market: .market
        case .agent: .agent
        case .explore: .explore
        default: nil
        }
    }

    private func page(for page: Page) -> TopTabsPageViewController {
        return switch page {
        case .wallet: walletPage
        case .market: marketPage
        case .agent: agentPage
        case .explore: explorePage
        }
    }
}

extension TopTabsRootViewController {
    private func pagerDidSelect(_ index: Int) {
        segmentedControl.setPagingProgress(CGFloat(index))
        segmentedControl.endSelectionScroll()
        updateAgentPaging(agentShare: index == pageIndex(of: .agent) ? 1 : 0, neighbor: nil)
        updateAgentBottomBar(committedIndex: index)
        let page = selectedPage
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.select(pageIndex(of: page)) }
        if page != activePage {
            captureSharedNavigationPath(for: activePage)
            activePage = page
            installSharedNavigationPath(for: page)
        }
        navigationController(for: page)?.viewControllers.forEach(applyChromeInsets)
        updateHomeWalletAssetsNavigationChrome()
        updateRootChromeVisibilityForSelectedPage()
    }
}

@MainActor
private final class TopTabsPageViewController: UIViewController, WSegmentedControllerContent {
    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { nil }

    private var makeContent: (() -> UIViewController)?
    private(set) var loadedContentViewController: UIViewController?
    var onLoadContent: ((UIViewController) -> Void)?
    var contentViewController: UIViewController {
        if let loadedContentViewController { return loadedContentViewController }
        guard let makeContent else { preconditionFailure("A page requires content or a factory") }
        let controller = makeContent()
        loadedContentViewController = controller
        self.makeContent = nil
        onLoadContent?(controller)
        return controller
    }

    init(makeContent: @escaping () -> UIViewController) {
        self.makeContent = makeContent
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentViewController()
    }

    func setContentViewController(_ viewController: UIViewController) {
        guard loadedContentViewController !== viewController else { return }
        uninstallContentViewController()
        loadedContentViewController = viewController
        makeContent = nil
        onLoadContent?(viewController)
        if isViewLoaded {
            installContentViewController()
        }
    }

    private func uninstallContentViewController() {
        guard let contentViewController = loadedContentViewController,
              contentViewController.parent === self else { return }
        contentViewController.willMove(toParent: nil)
        contentViewController.view.removeFromSuperview()
        contentViewController.removeFromParent()
    }

    private func installContentViewController() {
        addChild(contentViewController)
        contentViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentViewController.view)
        NSLayoutConstraint.activate([
            contentViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentViewController.didMove(toParent: self)
    }

    func scrollToTop(animated: Bool) {
        let viewController = (contentViewController as? UINavigationController)?.visibleViewController
            ?? contentViewController
        if let viewController = viewController as? WViewController {
            viewController.scrollToTop(animated: animated)
        }
    }

    func calculateHeight(isHosted: Bool) -> CGFloat {
        view.bounds.height
    }
}

extension TopTabsRootViewController: RootSearchToolbarHost {
    func searchToolbarWillDetach() {
        pager?.setAdditionalPagingGestureView(nil)
    }

    var searchNavigationController: WNavigationController? { sharedMainNavigationController }
    var searchRootContentControllers: [UIViewController] {
        [walletPage, marketPage, agentPage, explorePage].compactMap(\.loadedContentViewController)
    }
    var searchEditingNavigator: NftsEditingNavigator? {
        selectedPage == .wallet ? homeVC.walletAssetsEditingNavigator : nil
    }
    var showsRootSearchToolbar: Bool { true }

    func agentQuestionEditingDidChange(_ isEditing: Bool) {
        guard isEditing else {
            // Sending pushes the question's chat right after the field resigns; that chat's header takes over then
            DispatchQueue.main.async { [weak self] in
                guard let self, !isPresentingComposedChat, composeHeaderSwap.isActive,
                      sharedMainNavigationController?.topViewController === self,
                      sharedMainNavigationController?.transitionCoordinator == nil else { return }
                composeHeaderSwap.setActive(false, animated: true)
                updatePagingEnabled()
            }
            return
        }
        guard sideTabEdge == nil, selectedPage == .agent,
              sharedMainNavigationController?.topViewController === self else { return }
        composeHeaderSwap.setActive(true, animated: view.window != nil)
        updatePagingEnabled()
    }
}

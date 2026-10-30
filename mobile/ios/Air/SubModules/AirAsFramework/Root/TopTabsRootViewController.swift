import ContextMenuKit
import SwiftUI
import SwiftNavigation
import UIKit
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
private let topTabsAccountAvatarSize: CGFloat = 36

@MainActor
final class TopTabsRootViewController: WViewController, VisibleContentProviding {
    private enum Page: Int {
        case wallet
        case market
        case explore

        var navigationTitle: String {
            switch self {
            case .wallet: lang("Wallet")
            case .market: lang("Market")
            case .explore: lang("Explore")
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
    private let explorePage: TopTabsPageViewController

    private var pager: WPagerViewController!
    private var segmentedControl: WSegmentedControl!
    private let tabControlContainer = UIView()
    private var headerContentView: UIView?
    private var horizontalHeaderConstraints: [NSLayoutConstraint] = []
    private var sideHeaderConstraints: [NSLayoutConstraint] = []
    private var sideHeaderCenterConstraint: NSLayoutConstraint?
    private var sideHeaderTopConstraint: NSLayoutConstraint?
    private enum SideTabEdge { case left, right }
    private var sideTabEdge: SideTabEdge?
    private var sideTabBar: UIView?

    override var hideNavigationBar: Bool {
        sideTabEdge != nil && (selectedPage != .wallet || homeVC.walletAssetsEditingNavigator?.state.editingState == nil)
    }
    private var navigationBarTitleWidthConstraint: NSLayoutConstraint?
    private let accountSwitcherButton = TopTabsAccountButton()
    let searchController: RootSearchToolbarController
    private var accountSwitcherMenuInteraction: ContextMenuInteraction?
    private var isSearchVisible: Bool { searchController.isSearchVisible }

    private var accountObservation: ObserveToken?
    private var sharedNavigationPaths: [Page: [UIViewController]] = [:]
    private var activePage: Page = .wallet {
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
        case .wallet: .wallet
        }
    }

    var isHomeRootSelected: Bool {
        guard currentTabId == .wallet else { return false }
        return sharedMainNavigationController?.viewControllers.count == 1
            && sharedMainNavigationController?.viewControllers.first === self
    }

    private var selectedPage: Page {
        Page(rawValue: pager?.selectedIndex ?? Page.wallet.rawValue) ?? .wallet
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

        let pages = [walletPage, marketPage, explorePage]
        searchController.attach(to: self)
        pages.forEach { page in
            page.onLoadContent = { [weak self] in self?.applyChromeInsets(to: $0) }
        }
        pages.compactMap(\.loadedContentViewController).forEach(applyChromeInsets)
        configurePager()
        configureToolbarPaging()
        observeHomeWalletAssetsEditingState()
        observeAccountSwitcher()
        observeHomeUpdateStatus()
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge + [UITraitLayoutDirection.self]) { (controller: TopTabsRootViewController, _: UITraitCollection) in
                controller.updateTabBarPlacement()
            }
        }
        updateTabBarPlacement()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTabBarPlacement()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.cancelInteraction() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installSettingsMorph()
        // Kept for a morphing pop even when Settings was opened another way (edge swipe).
        settingsMorphSource = captureSettingsMorphSource() ?? settingsMorphSource
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
        // Top Tabs follows the fixed order from the design.
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
        pager.select(index: page.rawValue, animated: animated)
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.select(page.rawValue, animated: animated) }
        installSharedNavigationPath(for: page)
        return true
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
        let items = [
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
                id: AppTabId.explore.rawValue,
                title: lang("Explore"),
                isDeletable: false,
                accessibilityIdentifier: "tab_explore",
                viewController: explorePage
            ),
        ]

        let model = SegmentedControlModel(
            items: items,
            selection: .init(item1: AppTabId.wallet.rawValue),
            primaryColor: .tintColor,
            capsuleColor: .air.thumbBackground,
            style: .compactRootHeader
        )
        let segmentedControl = WSegmentedControl(model: model, isGlassInteractive: true)
        self.segmentedControl = segmentedControl
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        model.onSelect = { [weak self] item in
            self?.selectTab(AppTabId(item.id))
        }

        let pages = [walletPage, marketPage, explorePage]
        let pager = WPagerViewController(pages: zip(items, pages).map { item, page in
            .init(id: item.id, makeViewController: { page })
        }, preloadsPages: true)
        self.pager = pager
        pager.onProgressChanged = { [weak self] progress in
            self?.segmentedControl.setPagingProgress(progress.logicalOffset)
        }
        pager.onSelectionChanged = { [weak self] index in
            self?.pagerDidSelect(index)
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
        if #available(iOS 26, iOSApplicationExtension 26, *) {
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
        navigationItem.titleView = tabControlContainer

        let titleWidthConstraint = tabControlContainer.widthAnchor.constraint(
            equalToConstant: max(0, view.bounds.width - 32)
        )
        navigationBarTitleWidthConstraint = titleWidthConstraint

        horizontalHeaderConstraints = [
            titleWidthConstraint,
            tabControlContainer.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),

            accountSwitcherButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            accountSwitcherButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            accountSwitcherButton.widthAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),
            accountSwitcherButton.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),

            segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(
                equalTo: accountSwitcherButton.leadingAnchor,
                constant: -topTabsNavigationBarSpacing
            ),
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
        sideTabEdge = edge
        NSLayoutConstraint.deactivate(sideHeaderConstraints)
        sideHeaderConstraints = []
        sideHeaderCenterConstraint = nil
        sideHeaderTopConstraint = nil
        if let edge, #available(iOS 27.1, *) {
            if sideTabBar == nil {
                let ids: [AppTabId] = [.wallet, .market, .explore]
                let items = ids.compactMap { id -> WVerticalTabBar.Item? in
                    guard let registration = AppTabManager.shared.registration(for: id) else { return nil }
                    return .init(id: id.rawValue, title: registration.titleProvider(), image: registration.compactIcon)
                }
                let bar = WVerticalTabBar(items: items)
                bar.tintColor = .tintColor
                bar.onSelect = { [weak self] index, repeated in
                    guard ids.indices.contains(index) else { return }
                    self?.selectTab(ids[index], popToRoot: repeated)
                    if repeated { self?.scrollToTop() }
                }
                bar.translatesAutoresizingMaskIntoConstraints = false
                sideTabBar = bar
                view.addSubview(bar)
            }
            (sideTabBar as? WVerticalTabBar)?.isOnLeftEdge = edge == .left
            (sideTabBar as? WVerticalTabBar)?.select(selectedPage.rawValue, animated: false)
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
                sideHeaderConstraints = [
                    center,
                    top,
                    accountSwitcherButton.widthAnchor.constraint(equalToConstant: 48),
                    accountSwitcherButton.heightAnchor.constraint(equalToConstant: 48),
                    bar.centerXAnchor.constraint(equalTo: accountSwitcherButton.centerXAnchor),
                    bar.topAnchor.constraint(equalTo: accountSwitcherButton.bottomAnchor, constant: 12),
                    bar.widthAnchor.constraint(equalToConstant: bar.intrinsicContentSize.width),
                    bar.heightAnchor.constraint(equalToConstant: bar.intrinsicContentSize.height),
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
        [walletPage, marketPage, explorePage].compactMap(\.loadedContentViewController).forEach(applyChromeInsets)
        updateHomeWalletAssetsNavigationChrome()
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
        }
        accountSwitcherButton.setUpdateStatus(homeVC.updateStatus, animated: false)
    }

    private func updateRootChromeVisibilityForSelectedPage() { searchController.updatePresentation() }
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

    private func updateHomeWalletAssetsNavigationChrome() {
        // Keep the root item's controls in sync while a transient controller is presented.
        let isShowingWalletRoot = selectedPage == .wallet
            && sharedMainNavigationController?.topViewController === self
        let navigator = isShowingWalletRoot ? homeVC.walletAssetsEditingNavigator : nil
        let editingState = navigator?.state.editingState

        pager?.isPagingEnabled = editingState == nil
        navigationItem.titleView = editingState == nil && sideTabEdge == nil ? tabControlContainer : UIView()
        if editingState != nil, #available(iOS 26.0, *) {
            (sideTabBar as? WVerticalTabBar)?.cancelInteraction()
        }
        sideTabBar?.isHidden = sideTabEdge == nil || editingState != nil
        accountSwitcherButton.isHidden = sideTabEdge != nil && editingState != nil
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

    // MARK: Settings morph

    private var settingsMorphSource: SettingsMorphSource?
    private let barPressRecorder = PressTimingRecognizer()

    private func installSettingsMorph() {
        guard #available(iOS 26, *), let navigationController = sharedMainNavigationController else { return }
        if barPressRecorder.view !== navigationController.navigationBar {
            navigationController.navigationBar.addGestureRecognizer(barPressRecorder)
        }
        navigationController.customTransitionProvider = { [weak self, weak navigationController] operation, from, to in
            guard let self, let navigationController,
                  UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled,
                  !navigationController.isInteractivePopInProgress,
                  to is SettingsVC || from is SettingsVC else { return nil }
            switch operation {
            case .push where from === self:
                guard var source = captureSettingsMorphSource() else { return nil }
                if let lift = SettingsMorphTransition.takeCaughtLift() { source.pressLift = lift }
                settingsMorphSource = source
                return SettingsMorphTransition(isPush: true, source: source, navigationController: navigationController,
                                               reverse: { [weak navigationController] in
                    _ = navigationController?.popViewController(animated: true)
                })
            case .pop where to === self:
                guard var source = settingsMorphSource else { return nil }
                // The back button's glass is lifted by the tap that pops, like the avatar's on push.
                let bar = navigationController.navigationBar
                source.pressLift = SettingsMorphTransition.takeCaughtLift()
                    ?? barPressRecorder.recentLift(in: CGRect(x: 0, y: 0, width: 90, height: bar.bounds.height))
                return SettingsMorphTransition(isPush: false, source: source, navigationController: navigationController,
                                               reverse: { [weak self] in self?.openSettings() })
            default:
                return nil
            }
        }
    }

    /// Top-bar geometry while it is on screen; nil in other states (editing, search, offscreen).
    private func captureSettingsMorphSource() -> SettingsMorphSource? {
        guard let navigationView = sharedMainNavigationController?.view,
              let segmentedControl, segmentedControl.window != nil,
              accountSwitcherButton.window != nil,
              navigationItem.titleView === tabControlContainer else { return nil }
        let avatar = accountSwitcherButton.avatarView
        return SettingsMorphSource(
            segmentedFrame: segmentedControl.convert(segmentedControl.bounds, to: navigationView),
            // Titles only: the stand-in glass draws the capsule, so its rim is never doubled.
            segmentedSnapshot: segmentedControl.makeTitlesReplica(),
            avatarGlassFrame: accountSwitcherButton.convert(accountSwitcherButton.bounds, to: navigationView),
            avatarFrame: avatar.convert(avatar.bounds, to: navigationView),
            pressLift: accountSwitcherButton.pressLift
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

        for page in [Page.wallet, .market, .explore] {
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
        case .explore: explorePage
        default: nil
        }
    }

    private func pageValue(for id: AppTabId) -> Page? {
        return switch id {
        case .wallet: .wallet
        case .market: .market
        case .explore: .explore
        default: nil
        }
    }

    private func page(for page: Page) -> TopTabsPageViewController {
        return switch page {
        case .wallet: walletPage
        case .market: marketPage
        case .explore: explorePage
        }
    }
}

extension TopTabsRootViewController {
    private func pagerDidSelect(_ index: Int) {
        segmentedControl.setPagingProgress(CGFloat(index))
        let page = selectedPage
        if #available(iOS 26.0, *) { (sideTabBar as? WVerticalTabBar)?.select(page.rawValue) }
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
final class TopTabsAccountButton: UIControl {
    private let iconView = IconView(size: topTabsAccountAvatarSize)
    var avatarView: UIView { iconView }
    /// How far the interactive glass is lifted by the touch that just ended. UIKit lifts it on
    /// touch-down (measured: ×1.36, ~63% there after 0.05 s) and keeps it up until the screen
    /// changes, but renders this outside the app's layers, so it is modelled from the press time.
    var pressLift: CGFloat {
        guard let touchDownTime, CACurrentMediaTime() - touchUpTime < 0.4 else { return 1 }
        return InteractiveGlassLift.scale(heldFor: touchUpTime - touchDownTime)
    }
    private var touchDownTime: CFTimeInterval?
    private var touchUpTime: CFTimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        touchDownTime = CACurrentMediaTime()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchUpTime = CACurrentMediaTime()
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
    }
    private let activityIndicator = UIView()
    private let activityIndicatorImage = UIImageView(image: .airBundle("AccountActivityIndicator"))
    private var isUpdating = false
    private var visibilityAnimationId = 0
    private let glassView: UIVisualEffectView = {
        let view: UIVisualEffectView
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            view = UIVisualEffectView(effect: effect)
            view.cornerConfiguration = .capsule()
        } else {
            view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            view.layer.cornerRadius = topTabsNavigationBarHeight / 2
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            view.isUserInteractionEnabled = false
        }
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "tab_settings_button"

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isAccessibilityElement = false
        addSubview(glassView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        glassView.contentView.addSubview(iconView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.isUserInteractionEnabled = false
        activityIndicator.isAccessibilityElement = false
        activityIndicator.alpha = 0
        activityIndicator.isHidden = true
        glassView.contentView.addSubview(activityIndicator)
        activityIndicatorImage.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.addSubview(activityIndicatorImage)
        NSLayoutConstraint.activate([
            activityIndicatorImage.leadingAnchor.constraint(equalTo: activityIndicator.leadingAnchor),
            activityIndicatorImage.trailingAnchor.constraint(equalTo: activityIndicator.trailingAnchor),
            activityIndicatorImage.topAnchor.constraint(equalTo: activityIndicator.topAnchor),
            activityIndicatorImage.bottomAnchor.constraint(equalTo: activityIndicator.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: glassView.contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: topTabsAccountAvatarSize),
            iconView.heightAnchor.constraint(equalToConstant: topTabsAccountAvatarSize),

            activityIndicator.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            activityIndicator.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])

        if #available(iOS 26, iOSApplicationExtension 26, *) {
            glassView.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(glassTapped))
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(account: MAccount?) {
        iconView.config(with: account)
        accessibilityLabel = lang("Settings")
    }

    func setUpdateStatus(_ state: UpdateStatusView.State, animated: Bool) {
        switch state {
        case .waitingForNetwork:
            accessibilityValue = lang("Waiting for network…")
        case .updating:
            accessibilityValue = lang("Updating…")
        case .updated:
            accessibilityValue = nil
        }

        let isUpdating = state != .updated
        guard self.isUpdating != isUpdating else { return }
        self.isUpdating = isUpdating
        visibilityAnimationId += 1
        let animationId = visibilityAnimationId
        if isUpdating {
            activityIndicator.isHidden = false
            startIndicatorRotation()
        }

        let opacity = activityIndicator.layer.presentation()?.opacity ?? activityIndicator.layer.opacity
        let targetOpacity: Float = isUpdating ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.visibilityAnimationId == animationId, !self.isUpdating else { return }
            self.activityIndicator.isHidden = true
            self.activityIndicatorImage.layer.removeAnimation(forKey: "rotation")
        }
        activityIndicator.layer.opacity = targetOpacity
        if animated && !UIAccessibility.isReduceMotionEnabled {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity
            fade.toValue = targetOpacity
            fade.duration = 0.3
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            activityIndicator.layer.add(fade, forKey: "opacity")
        } else {
            activityIndicator.layer.removeAnimation(forKey: "opacity")
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isUpdating {
            startIndicatorRotation()
        } else if window == nil {
            activityIndicatorImage.layer.removeAnimation(forKey: "rotation")
        }
    }

    private func startIndicatorRotation() {
        guard activityIndicatorImage.layer.animation(forKey: "rotation") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation")
        animation.fromValue = 0
        animation.beginTime = activityIndicatorImage.layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.toValue = 2 * Double.pi
        animation.duration = 0.625
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        activityIndicatorImage.layer.add(animation, forKey: "rotation")
    }

    @objc private func glassTapped() {
        // Recognized at touch-up, before the touch itself is cancelled: the press ends here.
        touchUpTime = CACurrentMediaTime()
        sendActions(for: .touchUpInside)
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
        [walletPage, marketPage, explorePage].compactMap(\.loadedContentViewController)
    }
    var searchEditingNavigator: NftsEditingNavigator? {
        selectedPage == .wallet ? homeVC.walletAssetsEditingNavigator : nil
    }
    var showsRootSearchToolbar: Bool { true }
}

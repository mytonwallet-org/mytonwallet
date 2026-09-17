import ContextMenuKit
import SwiftUI
import SwiftNavigation
import UIKit
import UIBrowser
import UIAgent
import UIAssets
import UIComponents
import UIHome
import UISettings
import UIUniversalSearch
import UniversalSearchFeature
import WalletContext
import WalletCore

private let topTabsNavigationBarHeight: CGFloat = 44
private let topTabsSegmentedControlHeight: CGFloat = 40
private let topTabsNavigationBarSpacing: CGFloat = 10
private let topTabsAccountAvatarSize: CGFloat = 36
private let topTabsBottomChromeHeight: CGFloat = 64
private let topTabsBottomGradientHeight: CGFloat = 84
private let topTabsActionMenuWidth: CGFloat = 386
private let topTabsActionMenuMaximumCompactWidth: CGFloat = 424
private let topTabsActionMenuItemHeight: CGFloat = 124
private let topTabsActionMenuItemOrder: [SplitHomeActionItem] = [
    .buy,
    .deposit,
    .swap,
    .sell,
    .send,
    .earn,
    .scan,
]
private let topTabsSearchAnimationDuration: TimeInterval = 0.42

@MainActor
final class TopTabsRootViewController: WViewController, VisibleContentProviding {
    private enum Page: Int {
        case wallet
        case market
        case explore
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

    private var segmentedController: WSegmentedController!
    private let tabControlContainer = UIView()
    private var navigationBarTitleWidthConstraint: NSLayoutConstraint?
    private let accountSwitcherButton = TopTabsAccountButton()
    private let bottomGradientView = TopTabsBottomGradientView()
    private let searchToolbar = UniversalSearchFieldView(configuration: .init(
        placeholder: lang("Search or Ask"),
        showsMicrophone: false
    ))
    private var searchToolbarLeadingConstraint: NSLayoutConstraint?
    private var searchToolbarTrailingConstraint: NSLayoutConstraint?
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private var searchToolbarHostConstraints: [NSLayoutConstraint] = []
    private var accountSwitcherMenuInteraction: ContextMenuInteraction?
    private var actionsMenuInteraction: ContextMenuInteraction?
    private var universalSearchViewController: TopTabsSearchViewController?
    private var searchSheetObservation: MinimizableSheetObservation?

    private var isSearchVisible: Bool {
        guard let universalSearchViewController else { return false }
        return sharedMainNavigationController?.topViewController === universalSearchViewController
    }
    private weak var activeSharedBottomToolbarProvider: (any SharedBottomToolbarContentProviding)?
    private var isClosingSearch = false
    private var baseAdditionalSafeAreaInsets: [ObjectIdentifier: UIEdgeInsets] = [:]
    private var accountObservation: ObserveToken?
    private var sharedNavigationPaths: [Page: [UIViewController]] = [:]
    private var activePage: Page = .wallet
    private var standardSettingsRootViewController: SettingsVC?
    private var pendingStandardSettingsStack: [UIViewController]?
    private var detachedStandardSettingsStackForMigration: [UIViewController]?
    private var didPrepareStandardNavigationMigration = false

    private var sharedMainNavigationController: WNavigationController? {
        return navigationController as? WNavigationController
    }

    private var searchToolbarHostView: UIView {
        searchToolbar.superview ?? sharedMainNavigationController?.view ?? view
    }

    private var homeToolbarBottomInset: CGFloat {
        homeToolbarBottomInset(in: searchToolbarHostView)
    }

    private func homeToolbarBottomInset(in hostView: UIView) -> CGFloat {
        hostView.safeAreaInsets.bottom > 0 ? 2 : -16
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
        Page(rawValue: segmentedController?.selectedIndex ?? Page.wallet.rawValue) ?? .wallet
    }

    init() {
        let homeVC = HomeVC(
            rootNavigationStyle: .topTabsNavigationBar,
            showsActionsRow: WalletActionButtonsSettings.showsActionButtonsRow
        )
        let marketViewController = MarketVC(
            showsLargeTitle: false,
            usesTopTabsChrome: true
        )
        let exploreViewController = ExploreTabVC(
            showsSearchBar: false,
            showsLargeTitle: false,
            usesTopTabsChrome: true
        )

        self.homeVC = homeVC
        self.walletPage = TopTabsPageViewController(contentViewController: homeVC)
        self.marketPage = TopTabsPageViewController(contentViewController: marketViewController)
        self.explorePage = TopTabsPageViewController(contentViewController: exploreViewController)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.groupedBackground

        let pages = [walletPage, marketPage, explorePage]
        pages.forEach {
            addChild($0)
            $0.didMove(toParent: self)
        }

        configureNavigationControllers()
        pages.map(\.contentViewController).forEach(applyChromeInsets)
        configurePager()
        configureBottomBar()
        observeHomeWalletAssetsEditingState()
        observeAccountSwitcher()
        observeHomeUpdateStatus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let availableWidth = max(0, view.bounds.width - 32)
        if navigationBarTitleWidthConstraint?.constant != availableWidth {
            navigationBarTitleWidthConstraint?.constant = availableWidth
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if !isSearchVisible {
            bottomBarBottomConstraint?.constant = homeToolbarBottomInset
        }
    }

    func discardSearch() {
        guard let search = universalSearchViewController else { return }
        search.stop()
        universalSearchViewController = nil
        clearSharedSearchField()
        searchSheetObservation?.invalidate()
        searchSheetObservation = nil
        if let navigationController = sharedMainNavigationController {
            navigationController.setViewControllers(
                navigationController.viewControllers.filter { $0 !== search },
                animated: false
            )
        }
        isClosingSearch = false
    }

    func applyTabConfiguration(_ orderedIds: [AppTabId]) {
        // Top Tabs follows the fixed order from the design.
    }

    func takeNavigationStack(for id: AppTabId, keepingRoot: Bool) -> [UIViewController]? {
        prepareStandardNavigationMigrationIfNeeded()
        if id == .settings {
            return detachedStandardSettingsStackForMigration
        }
        guard let page = page(for: id), let pageValue = pageValue(for: id) else { return nil }
        if pageValue == activePage, let sharedMainNavigationController {
            sharedNavigationPaths[pageValue] = Array(
                sharedMainNavigationController.viewControllers.dropFirst()
            )
            sharedMainNavigationController.setViewControllers([self], animated: false)
        }
        let stack = [page.contentViewController] + (sharedNavigationPaths[pageValue] ?? [])
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
    func selectTab(_ id: AppTabId, popToRoot: Bool = false) -> Bool {
        if id == .settings {
            return showStandardSettings(
                path: nil,
                popToRoot: popToRoot,
                animated: true
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
        segmentedController.setSelectedIndex(to: page.rawValue, animated: true)
        activePage = page
        if popToRoot {
            sharedNavigationPaths[page] = []
        }
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

    func debugOnly_resetAgentRoot() {
        guard let sharedMainNavigationController else { return }
        AgentEntryPoint.resetRootViewControllerForDebug(in: sharedMainNavigationController)
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
        guard isSearchVisible, let navigationController = sharedMainNavigationController else { return false }
        navigationController.pushViewController(viewController, animated: true)
        return true
    }

    @discardableResult
    func pushOnSettingsRoot(_ viewController: UIViewController, animated: Bool = true) -> Bool {
        guard showStandardSettings(path: nil, popToRoot: false, animated: false),
              let sharedMainNavigationController else {
            return false
        }
        applyChromeInsets(to: viewController)
        sharedMainNavigationController.pushViewController(viewController, animated: animated)
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
                viewController: walletPage
            ),
            SegmentedControlItem(
                id: AppTabId.market.rawValue,
                title: lang("Market"),
                isDeletable: false,
                viewController: marketPage
            ),
            SegmentedControlItem(
                id: AppTabId.explore.rawValue,
                title: lang("Explore"),
                isDeletable: false,
                viewController: explorePage
            ),
        ]

        let segmentedController = WSegmentedController(
            items: items,
            leadingViewControllers: [],
            defaultItemId: AppTabId.wallet.rawValue,
            barHeight: topTabsNavigationBarHeight,
            goUnderNavBar: true,
            animationSpeed: .fast,
            primaryTextColor: .tintColor,
            capsuleFillColor: .air.thumbBackground,
            isGlassInteractive: true,
            style: .compactRootHeader,
            delegate: self
        )
        self.segmentedController = segmentedController
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedController.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true

        let segmentedControl = segmentedController.segmentedControl!
        segmentedControl.removeFromSuperview()

        configureNavigationBarHeader(segmentedControl: segmentedControl)
    }

    private func configureNavigationBarHeader(segmentedControl: WSegmentedControl) {
        configureNavigationItemWithTransparentBackground()
        addCustomNavigationBarBackground(color: .clear)

        accountSwitcherButton.configure(account: AccountStore.account)
        accountSwitcherButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let accountSwitcherMenuInteraction = ContextMenuInteraction(
            triggers: [.longPress],
            configurationProvider: { _ in
                SwitchAccountMenu.makeConfiguration()
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
        contentView.addSubview(accountSwitcherButton)
        contentView.addSubview(segmentedControl)
        navigationItem.titleView = tabControlContainer

        let titleWidthConstraint = tabControlContainer.widthAnchor.constraint(
            equalToConstant: max(0, view.bounds.width - 32)
        )
        navigationBarTitleWidthConstraint = titleWidthConstraint

        NSLayoutConstraint.activate([
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
        ])
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

    private func configureNavigationControllers() {
        sharedMainNavigationController?.onWillShowViewController = { [weak self] viewController in
            guard let self, let sharedMainNavigationController else { return }
            searchNavigationWillShow(viewController, in: sharedMainNavigationController)
            applyChromeInsets(to: viewController)
            updateRootChromeVisibility(
                for: sharedMainNavigationController,
                showing: viewController
            )
        }
        sharedMainNavigationController?.onDidShowViewController = { [weak self] viewController in
            self?.searchNavigationDidShow(viewController)
        }
    }

    private func updateRootChromeVisibility(
        for navigationController: WNavigationController,
        showing viewController: UIViewController
    ) {
        guard navigationController === self.navigationController(for: selectedPage) else {
            return
        }
        let isShowingRoot = navigationController.viewControllers.first === viewController
        if isShowingRoot, installHomeNftSelectionToolbarIfNeeded(in: navigationController) {
            return
        }
        let provider = viewController as? any SharedBottomToolbarContentProviding
        let targetPresentation: UniversalSearchFieldPresentation = viewController is TopTabsSearchViewController
            ? .search
            : sharedBottomToolbarPresentation(isShowingRoot: isShowingRoot, provider: provider)
        searchToolbar.isHidden = false
        updateSharedBottomToolbar(
            provider: provider,
            targetPresentation: targetPresentation,
            in: navigationController,
            coordinator: navigationController.transitionCoordinator
        )
    }

    private func updateRootChromeVisibilityForSelectedPage() {
        guard let navigationController = navigationController(for: selectedPage),
              let viewController = navigationController.topViewController else {
            return
        }
        // Presented sheets do not change the navigation stack's toolbar.
        updateRootChromeVisibility(for: navigationController, showing: viewController)
    }

    private func updateSharedBottomToolbar(
        provider: (any SharedBottomToolbarContentProviding)?,
        targetPresentation: UniversalSearchFieldPresentation,
        in navigationController: WNavigationController,
        coordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        if let provider {
            bindSharedBottomToolbarProvider(provider)
            searchToolbar.setCompactActions(provider.sharedBottomToolbarActions)
        }

        guard searchToolbar.presentation != targetPresentation else {
            updateSearchToolbarGeometry(for: targetPresentation)
            finishBottomChromeVisibility(at: targetPresentation)
            if targetPresentation != .compactToolbar {
                finishSharedBottomToolbarPresentation(
                    provider: nil,
                    presentation: targetPresentation
                )
            }
            return
        }

        if targetPresentation != .homeToolbar {
            actionsMenuInteraction?.detach()
        }
        prepareBottomChromeVisibilityForTransition()
        navigationController.view.layoutIfNeeded()
        updateSearchToolbarGeometry(for: targetPresentation)

        guard let coordinator else {
            searchToolbar.setPresentation(targetPresentation, animated: false)
            navigationController.view.layoutIfNeeded()
            finishBottomChromeVisibility(at: targetPresentation)
            finishSharedBottomToolbarPresentation(
                provider: provider,
                presentation: targetPresentation
            )
            return
        }

        let sourcePresentation = searchToolbar.presentation
        searchToolbar.preparePresentationTransition(to: targetPresentation)
        let accepted = coordinator.animate { [weak self, weak navigationController] _ in
            guard let self, let navigationController else { return }
            searchToolbar.applyPreparedPresentationTransition()
            if targetPresentation == .search, !coordinator.isInteractive,
               universalSearchViewController?.restoresKeyboard == true {
                _ = searchToolbar.focus()
            }
            bottomGradientView.alpha = targetPresentation == .empty ? 0 : 1
            navigationController.view.layoutIfNeeded()
        } completion: { [weak self, weak navigationController] context in
            guard let self else { return }
            let finalPresentation = context.isCancelled ? sourcePresentation : targetPresentation
            updateSearchToolbarGeometry(for: finalPresentation)
            searchToolbar.setPresentation(
                finalPresentation,
                animated: false
            )
            finishBottomChromeVisibility(at: finalPresentation)
            guard let navigationController,
                  let topViewController = navigationController.topViewController else {
                return
            }
            synchronizeSharedBottomToolbar(
                for: topViewController,
                in: navigationController
            )
        }

        if !accepted {
            searchToolbar.setPresentation(targetPresentation, animated: false)
            navigationController.view.layoutIfNeeded()
            finishBottomChromeVisibility(at: targetPresentation)
            finishSharedBottomToolbarPresentation(
                provider: provider,
                presentation: targetPresentation
            )
        }
    }

    private func synchronizeSharedBottomToolbar(
        for viewController: UIViewController,
        in navigationController: WNavigationController
    ) {
        let isShowingRoot = navigationController.viewControllers.first === viewController
        if isShowingRoot, installHomeNftSelectionToolbarIfNeeded(in: navigationController) {
            return
        }
        let provider = viewController as? any SharedBottomToolbarContentProviding
        let targetPresentation: UniversalSearchFieldPresentation = viewController is TopTabsSearchViewController
            ? .search
            : sharedBottomToolbarPresentation(isShowingRoot: isShowingRoot, provider: provider)
        searchToolbar.isHidden = false
        if let provider {
            bindSharedBottomToolbarProvider(provider)
            searchToolbar.setCompactActions(provider.sharedBottomToolbarActions)
        }
        updateSearchToolbarGeometry(for: targetPresentation)
        searchToolbar.setPresentation(targetPresentation, animated: false)
        navigationController.view.layoutIfNeeded()
        finishBottomChromeVisibility(at: targetPresentation)
        finishSharedBottomToolbarPresentation(
            provider: provider,
            presentation: targetPresentation
        )
    }

    private func updateSearchToolbarGeometry(for presentation: UniversalSearchFieldPresentation) {
        let isSearch = presentation == .search
        searchToolbarLeadingConstraint?.constant = isSearch ? 8 : 28
        searchToolbarTrailingConstraint?.constant = isSearch ? -8 : -28
        bottomBarBottomConstraint?.constant = isSearch ? -10 : homeToolbarBottomInset
    }

    private func sharedBottomToolbarPresentation(
        isShowingRoot: Bool,
        provider: (any SharedBottomToolbarContentProviding)?
    ) -> UniversalSearchFieldPresentation {
        if isShowingRoot {
            .homeToolbar
        } else if provider != nil {
            .compactToolbar
        } else {
            .empty
        }
    }

    @discardableResult
    private func installHomeNftSelectionToolbarIfNeeded(
        in navigationController: WNavigationController
    ) -> Bool {
        guard selectedPage == .wallet,
              let navigator = homeVC.walletAssetsEditingNavigator,
              navigator.state.editingState == .selection else {
            return false
        }
        bottomGradientView.isHidden = false
        searchToolbar.isHidden = true
        navigator.installToolbar(into: navigationController.view)
        return true
    }

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
        updateRootChromeVisibility(for: navigationController, showing: self)
    }

    private func updateHomeWalletAssetsNavigationChrome() {
        // Keep the root item's controls in sync while a transient controller is presented.
        let isShowingWalletRoot = selectedPage == .wallet
            && sharedMainNavigationController?.topViewController === self
        let navigator = isShowingWalletRoot ? homeVC.walletAssetsEditingNavigator : nil
        let editingState = navigator?.state.editingState

        segmentedController?.scrollView.isScrollEnabled = editingState == nil
        navigationItem.titleView = editingState == nil ? tabControlContainer : nil

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

    private func bindSharedBottomToolbarProvider(
        _ provider: any SharedBottomToolbarContentProviding
    ) {
        if let activeSharedBottomToolbarProvider,
           (activeSharedBottomToolbarProvider as AnyObject) !== (provider as AnyObject) {
            activeSharedBottomToolbarProvider.onSharedBottomToolbarActionsChange = nil
            activeSharedBottomToolbarProvider.setSharedBottomToolbarHosted(false)
        }
        activeSharedBottomToolbarProvider = provider
        provider.setSharedBottomToolbarHosted(true)
        provider.onSharedBottomToolbarActionsChange = { [weak self, weak provider] in
            guard let self, let provider,
                  (activeSharedBottomToolbarProvider as AnyObject?) === (provider as AnyObject),
                  searchToolbar.presentation == .compactToolbar else {
                return
            }
            searchToolbar.setCompactActions(provider.sharedBottomToolbarActions)
        }
    }

    private func finishSharedBottomToolbarPresentation(
        provider: (any SharedBottomToolbarContentProviding)?,
        presentation: UniversalSearchFieldPresentation
    ) {
        if provider == nil {
            activeSharedBottomToolbarProvider?.onSharedBottomToolbarActionsChange = nil
            activeSharedBottomToolbarProvider?.setSharedBottomToolbarHosted(false)
            activeSharedBottomToolbarProvider = nil
            searchToolbar.setCompactActions([])
            if presentation == .homeToolbar {
                actionsMenuInteraction?.attach(to: searchToolbar.trailingButtonView)
            } else {
                actionsMenuInteraction?.detach()
            }
        } else {
            actionsMenuInteraction?.detach()
        }
    }

    private func prepareBottomChromeVisibilityForTransition() {
        searchToolbar.isHidden = false
        bottomGradientView.isHidden = false
        bottomGradientView.alpha = searchToolbar.presentation == .empty ? 0 : 1
    }

    private func finishBottomChromeVisibility(
        at presentation: UniversalSearchFieldPresentation
    ) {
        let isVisible = presentation != .empty
        searchToolbar.isHidden = false
        bottomGradientView.alpha = isVisible ? 1 : 0
        bottomGradientView.isHidden = !isVisible
    }

    private func applyChromeInsets(to viewController: UIViewController) {
        let identifier = ObjectIdentifier(viewController)
        let baseInsets = baseAdditionalSafeAreaInsets[identifier] ?? viewController.additionalSafeAreaInsets
        baseAdditionalSafeAreaInsets[identifier] = baseInsets
        let isRootViewController = [walletPage, marketPage, explorePage].contains {
            $0.contentViewController === viewController
        }
        let usesSharedBottomToolbar = viewController is any SharedBottomToolbarContentProviding
        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: baseInsets.top,
            left: baseInsets.left,
            bottom: baseInsets.bottom + (isRootViewController || usesSharedBottomToolbar
                ? topTabsBottomChromeHeight
                : 0),
            right: baseInsets.right
        )
    }

    private func removeChrome(from viewController: UIViewController) {
        if let provider = viewController as? any SharedBottomToolbarContentProviding,
           (activeSharedBottomToolbarProvider as AnyObject?) === (provider as AnyObject) {
            finishSharedBottomToolbarPresentation(
                provider: nil,
                presentation: searchToolbar.presentation
            )
        }

        let identifier = ObjectIdentifier(viewController)
        if let baseInsets = baseAdditionalSafeAreaInsets.removeValue(forKey: identifier) {
            viewController.additionalSafeAreaInsets = baseInsets
        }
    }

    private func configureBottomBar() {
        searchToolbar.bottomHitAreaExtension = 12
        searchToolbar.actionsAccessibilityLabel = lang("Actions")
        searchToolbar.closeAccessibilityLabel = lang("Close")
        searchToolbar.setPresentation(.homeToolbar, animated: false)
        searchToolbar.onActivate = { [weak self] in
            self?.openSearch()
        }
        searchToolbar.onCloseTap = { [weak self] in
            self?.closeSearch()
        }
        searchToolbar.onTextChange = { [weak self] text in
            guard let self, isSearchVisible, let search = universalSearchViewController else { return }
            search.fieldConfiguration.text = text
            search.session.updateQuery(text)
        }
        searchToolbar.onReturn = { [weak self] _ in
            guard let self else { return }
            if universalSearchViewController?.screen.selectPreselectedItem() != true {
                searchToolbar.endEditing()
            }
        }
        searchToolbar.onToolbarActionTap = { [weak self] id in
            self?.activeSharedBottomToolbarProvider?.performSharedBottomToolbarAction(id: id)
        }

        bottomGradientView.translatesAutoresizingMaskIntoConstraints = false
        bottomGradientView.toolbarView = searchToolbar
        let toolbarHostView = searchToolbarHostView
        toolbarHostView.addSubview(bottomGradientView)
        installSearchToolbar(
            in: toolbarHostView,
            leading: 28,
            trailing: -28,
            bottom: homeToolbarBottomInset
        )
        NSLayoutConstraint.activate([
            bottomGradientView.leadingAnchor.constraint(equalTo: toolbarHostView.leadingAnchor),
            bottomGradientView.trailingAnchor.constraint(equalTo: toolbarHostView.trailingAnchor),
            bottomGradientView.bottomAnchor.constraint(equalTo: toolbarHostView.bottomAnchor),
            bottomGradientView.heightAnchor.constraint(equalToConstant: topTabsBottomGradientHeight),
        ])

        let interaction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            presentationMode: .zoomSheetOrPopover,
            longPressDuration: 0.25,
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: 24, cornerCurve: .continuous)
            ),
            activationViewProvider: { [weak searchToolbar] _ in
                searchToolbar?.trailingButtonPresentationSourceView
            }
        ) { [weak self] _ in
            self?.makeActionsMenuConfiguration()
        }
        interaction.attach(to: searchToolbar.trailingButtonView)
        actionsMenuInteraction = interaction
        let isPagingEnabled: () -> Bool = { [weak self] in
            guard let self,
                  let navigationController = sharedMainNavigationController else { return false }
            return navigationController.topViewController === self
                && navigationController.presentedViewController == nil
                && navigationController.transitionCoordinator == nil
                && !isSearchVisible
                && !isClosingSearch
                && !searchToolbar.isHidden
        }
        segmentedController.setAdditionalPagingGestureView(searchToolbar, isEnabled: isPagingEnabled)
        segmentedController.setForwardNavigation(in: toolbarHostView, beginTransition: { [weak self] in
            guard let self, let navigationController = sharedMainNavigationController else { return nil }
            let settings = standardSettingsRootViewController ?? SettingsVC()
            standardSettingsRootViewController = settings
            applyChromeInsets(to: settings)
            return navigationController.beginInteractivePush(settings)
        }, isEnabled: isPagingEnabled)
    }

    private func installSearchToolbar(
        in hostView: UIView,
        leading: CGFloat,
        trailing: CGFloat,
        bottom: CGFloat
    ) {
        NSLayoutConstraint.deactivate(searchToolbarHostConstraints)
        searchToolbar.removeFromSuperview()
        searchToolbar.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(searchToolbar)

        let leadingConstraint = searchToolbar.leadingAnchor.constraint(
            equalTo: hostView.leadingAnchor,
            constant: leading
        )
        let trailingConstraint = searchToolbar.trailingAnchor.constraint(
            equalTo: hostView.trailingAnchor,
            constant: trailing
        )
        let bottomConstraint = searchToolbar.bottomAnchor.constraint(
            equalTo: hostView.keyboardLayoutGuide.topAnchor,
            constant: bottom
        )
        let constraints = [
            leadingConstraint,
            trailingConstraint,
            bottomConstraint,
            searchToolbar.heightAnchor.constraint(equalToConstant: 48),
        ]
        NSLayoutConstraint.activate(constraints)
        searchToolbarHostConstraints = constraints
        searchToolbarLeadingConstraint = leadingConstraint
        searchToolbarTrailingConstraint = trailingConstraint
        bottomBarBottomConstraint = bottomConstraint
    }

    private func makeActionsMenuConfiguration() -> ContextMenuConfiguration {
        guard let account = AccountStore.account else {
            return ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: []),
                backdrop: .none
            )
        }
        let accountContext = AccountContext(accountId: account.id)
        let maximumWidth = traitCollection.horizontalSizeClass == .compact
            ? topTabsActionMenuMaximumCompactWidth
            : topTabsActionMenuWidth
        let availableItems = Set(SplitHomeActionItem.availableItems(for: account))
        let items: [ContextMenuItem] = topTabsActionMenuItemOrder.compactMap { item in
            guard availableItems.contains(item) else {
                return nil
            }
            return actionMenuItem(item, accountContext: accountContext)
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(
                items: items,
                layout: .grid(ContextMenuGridLayout(
                    columns: 3,
                    contentInsets: UIEdgeInsets(top: 48, left: 20, bottom: 20, right: 20),
                    highlightInsets: UIEdgeInsets(top: -7, left: 4, bottom: 15, right: 4),
                    highlightCornerRadius: 24
                ))
            ),
            backdrop: .none,
            style: ContextMenuStyle(
                minWidth: topTabsActionMenuWidth,
                maxWidth: maximumWidth,
                verticalPlacementBehavior: .screenBottom,
                panelCornerRadius: 54,
                screenInsets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            ),
            sheetNavigationControllerProvider: { menu in
                menu.navigationItem.hidesBackButton = true
                if #available(iOS 26.0, *) {
                    return ActionMenuNavigationController(rootViewController: menu)
                }
                return UINavigationController(rootViewController: menu)
            }
        )
    }

    private func actionMenuItem(
        _ item: SplitHomeActionItem,
        accountContext: AccountContext
    ) -> ContextMenuItem {
        let handsOffSheet: Bool
        if #available(iOS 26.0, *), traitCollection.horizontalSizeClass == .compact {
            handsOffSheet = true
        } else {
            handsOffSheet = false
        }
        return .custom(
            .swiftUI(
                sizing: .fixed(height: topTabsActionMenuItemHeight),
                interaction: .selectable(dismissesMenu: !handsOffSheet) {
                    if #available(iOS 26.0, *), handsOffSheet,
                       let host = topViewController() as? ActionMenuNavigationController {
                        host.perform(item, accountContext: accountContext)
                    } else {
                        item.perform(accountContext: accountContext)
                    }
                }
            ) { _ in
                ActionMenuItem(item: item)
            }
        )
    }

    @objc private func openSearch() {
        guard !isSearchVisible,
              presentedViewController == nil,
              let navigationController = sharedMainNavigationController,
              navigationController.transitionCoordinator == nil else { return }
        discardSearch()
        var configuration = searchToolbar.configuration
        configuration.text = ""
        configuration.autocomplete = nil
        let search = TopTabsSearchViewController(configuration: configuration)
        search.screen.onClose = { [weak self] in self?.closeSearch() }
        search.session.onSelectRoute = { [weak self] route in
            self?.handleUniversalSearchRoute(route)
        }
        search.session.onAutocompleteChange = { [weak self, weak search] autocomplete in
            guard let self, let search else { return }
            search.fieldConfiguration.autocomplete = autocomplete
            if isSearchVisible, searchToolbar.presentation == .search {
                searchToolbar.configuration = search.fieldConfiguration
            }
        }
        search.onAppear = { [weak self, weak search] in
            guard let self, let search, universalSearchViewController === search else { return }
            searchDidReturn(search)
        }
        universalSearchViewController = search
        actionsMenuInteraction?.detach()
        search.session.start()
        navigationController.withCrossfade(
            duration: topTabsSearchAnimationDuration,
            keepingAboveTransition: [bottomGradientView, searchToolbar]
        ) {
            navigationController.pushViewController(search, animated: true)
        }
    }

    func closeSearch() {
        guard let search = universalSearchViewController,
              let navigationController = sharedMainNavigationController else { return }
        guard !isClosingSearch else { return }
        if let coordinator = navigationController.transitionCoordinator {
            isClosingSearch = true
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isClosingSearch = false
                    self?.closeSearch()
                }
            }
            return
        }
        guard navigationController.topViewController === search else {
            discardSearch()
            return
        }
        isClosingSearch = true
        search.stop()
        searchToolbar.endEditing()
        navigationController.withCrossfade(
            duration: topTabsSearchAnimationDuration,
            keepingAboveTransition: [bottomGradientView, searchToolbar]
        ) {
            _ = navigationController.popViewController(animated: true)
        }
    }

    private func searchNavigationWillShow(_ viewController: UIViewController, in navigationController: WNavigationController) {
        guard let search = universalSearchViewController else { return }
        if viewController === search {
            searchToolbar.configuration = search.fieldConfiguration
        } else if navigationController.transitionCoordinator?.viewController(forKey: .from) === search {
            if searchToolbar.isEditing { search.restoresKeyboard = true }
            searchToolbar.endEditing()
        }
    }

    private func searchNavigationDidShow(_ viewController: UIViewController) {
        guard let search = universalSearchViewController,
              let navigationController = sharedMainNavigationController else { return }
        if viewController !== search { clearSharedSearchField() }
        if !navigationController.viewControllers.contains(where: { $0 === search }) {
            search.stop()
            universalSearchViewController = nil
            searchSheetObservation?.invalidate()
            searchSheetObservation = nil
            isClosingSearch = false
        } else if viewController === search {
            searchDidReturn(search)
        } else if search.returnDeadline == nil {
            retainSearchForReturn(search)
        } else {
            expireSearchIfNeeded(search)
        }
    }

    private func clearSharedSearchField() {
        var configuration = searchToolbar.configuration
        configuration.text = ""
        configuration.autocomplete = nil
        searchToolbar.configuration = configuration
    }

    private func searchDidReturn(_ search: TopTabsSearchViewController) {
        guard isSearchVisible, !isClosingSearch else { return }
        search.expirationTask?.cancel()
        search.expirationTask = nil
        search.returnDeadline = nil
        searchToolbar.configuration = search.fieldConfiguration
        if search.restoresKeyboard { _ = searchToolbar.focus() }
    }

    private func retainSearchForReturn(_ search: TopTabsSearchViewController) {
        guard universalSearchViewController === search, search.returnDeadline == nil else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        search.returnDeadline = deadline
        search.expirationTask = Task { [weak self, weak search] in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard let self, let search else { return }
            expireSearchIfNeeded(search)
        }
    }

    private var isSearchCoveredByPresentation: Bool {
        let root = sharedMainNavigationController?.view.window?.rootViewController
        return root?.presentedViewController != nil
            || root?.descendantViewController(of: MinimizableSheetContainerViewController.self)?.sheetController.state == .expanded
    }

    private func expireSearchIfNeeded(_ search: TopTabsSearchViewController) {
        guard universalSearchViewController === search,
              let deadline = search.returnDeadline, ContinuousClock.now >= deadline,
              let navigationController = sharedMainNavigationController else { return }
        if let coordinator = navigationController.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self, weak search] _ in
                Task { @MainActor [weak self, weak search] in
                    guard let self, let search else { return }
                    expireSearchIfNeeded(search)
                }
            }
            return
        }
        guard !isSearchVisible || isSearchCoveredByPresentation else { return }
        discardSearch()
    }

    private func trackSearchPresentation(_ search: TopTabsSearchViewController) {
        if isSearchCoveredByPresentation { retainSearchForReturn(search) }
        if let controller = sharedMainNavigationController?.view.window?.rootViewController?
            .descendantViewController(of: MinimizableSheetContainerViewController.self)?.sheetController {
            searchSheetObservation?.invalidate()
            searchSheetObservation = controller.addObserver(options: .stateChanges) { [weak self, weak search] event in
                guard let self, let search, universalSearchViewController === search,
                      case let .stateDidChange(change) = event else { return }
                if change.toState == .expanded {
                    retainSearchForReturn(search)
                } else if isSearchVisible {
                    searchDidReturn(search)
                }
            }
        }
    }

    private func handleUniversalSearchRoute(_ route: UniversalSearchFeatureRoute) {
        guard isSearchVisible, !isClosingSearch,
              sharedMainNavigationController?.transitionCoordinator == nil,
              let search = universalSearchViewController else { return }
        search.expirationTask?.cancel()
        search.returnDeadline = nil
        search.restoresKeyboard = searchToolbar.isEditing
        searchToolbar.endEditing()
        switch route {
        case .walletAction(let action):
            let context = AccountContext(source: .current)
            switch action {
            case .fund: AppActions.showReceive(accountContext: context, chain: nil)
            case .send: AppActions.showSend(accountContext: context, prefilledValues: .init())
            case .earn: AppActions.showEarn(accountContext: context, tokenSlug: nil)
            case .buyWithCard: AppActions.showBuyWithCard(accountContext: context, chain: nil, push: nil)
            case .sell: AppActions.showSell(accountContext: context, tokenSlug: nil)
            case .scan: AppActions.scanAndHandleQR(accountContext: context)
            case .swap:
                Task {
                    await AppActions.showSwap(accountContext: context, defaultSellingToken: nil,
                                              defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
                    if self.universalSearchViewController === search {
                        self.trackSearchPresentation(search)
                    }
                }
            }

        case .settings(let section):
            AppActions.showSettings(section: section)

        case .token(let accountID, let token):
            AppActions.showToken(
                accountSource: .accountId(accountID),
                token: token,
                isInModal: false
            )

        case .collectible(let accountID, let nft):
            AppActions.showNft(
                accountContext: AccountContext(accountId: accountID),
                nft: nft,
                isExpanded: true
            )

        case .collection(let accountID, let collection):
            let filter = NftCollectionFilter.collection(collection)
            AppActions.showAssets(
                accountSource: .accountId(accountID),
                selectedTab: .nftCollectionFilter(filter),
                collectionsFilter: filter
            )

        case .application(let url, let title, let opensExternally):
            if opensExternally {
                UIApplication.shared.open(url)
            } else {
                AppActions.openInBrowser(
                    url,
                    title: title,
                    injectDappConnect: true
                )
            }

        case .wallet(let account):
            Task {
                do {
                    _ = try await AccountStore.activateAccount(accountId: account.id)
                    self.discardSearch()
                    AppActions.showHome(popToRoot: true)
                } catch {
                    AppActions.showError(error: error)
                }
            }

        case .externalWallet(let network, let addressOrDomainByChain):
            AppActions.showTemporaryViewAccount(
                network: network,
                addressOrDomainByChain: addressOrDomainByChain
            )

        case .agent(let query):
            AppActions.showAgent(query: query)

        case .website(let url, let title):
            AppActions.openInBrowser(
                url,
                title: title,
                injectDappConnect: true,
                historyTag: "explore"
            )

        case .google(let query):
            guard let url = UniversalSearchWebIntent.googleSearchURL(for: query) else { return }
            AppActions.openInBrowser(
                url,
                title: nil,
                injectDappConnect: false,
                historyTag: "explore"
            )
        }
        trackSearchPresentation(search)
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
        if let standardSettingsRootViewController,
           let index = stack.firstIndex(where: { $0 === standardSettingsRootViewController }) {
            return index
        }
        return stack.firstIndex { $0 is SettingsVC }
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

extension TopTabsRootViewController: WSegmentedController.Delegate {
    func segmentedController(scrollOffsetChangedTo progress: CGFloat) {}

    func segmentedControllerDidStartDragging() {}

    func segmentedControllerDidEndScrolling() {
        let page = selectedPage
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
private final class TopTabsAccountButton: UIControl {
    private let iconView = IconView(size: topTabsAccountAvatarSize)
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
            view.cornerConfiguration = .corners(
                radius: UICornerRadius(floatLiteral: topTabsNavigationBarHeight / 2)
            )
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
        sendActions(for: .touchUpInside)
    }
}

@MainActor
private final class TopTabsPageViewController: UIViewController, WSegmentedControllerContent {
    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { nil }

    private(set) var contentViewController: UIViewController

    init(contentViewController: UIViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        installContentViewController()
    }

    func setContentViewController(_ viewController: UIViewController) {
        guard contentViewController !== viewController else { return }
        if isViewLoaded {
            contentViewController.willMove(toParent: nil)
            contentViewController.view.removeFromSuperview()
            contentViewController.removeFromParent()
        }
        contentViewController = viewController
        if isViewLoaded {
            installContentViewController()
        }
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

@MainActor
private final class TopTabsBottomGradientView: UIView {
    weak var toolbarView: UIView?
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(gradientLayer)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let toolbarView,
              toolbarView.superview === superview,
              !toolbarView.isHidden,
              toolbarView.alpha > 0.01,
              toolbarView.isUserInteractionEnabled else { return false }
        // Absorb touches beside and below the toolbar, keeping content above it interactive.
        return super.point(inside: point, with: event)
            && convert(point, to: toolbarView).y >= toolbarView.bounds.minY
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        let color = UIColor.air.groupedBackground
        gradientLayer.colors = [
            color.withAlphaComponent(0).cgColor,
            color.withAlphaComponent(0.6).cgColor,
        ]
        gradientLayer.locations = [0, 1]
    }
}

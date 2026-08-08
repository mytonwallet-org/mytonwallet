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
private let topTabsNavigationBarSpacing: CGFloat = 10
private let topTabsBottomChromeHeight: CGFloat = 64
private let topTabsBottomGradientHeight: CGFloat = 84
private let topTabsActionMenuWidth: CGFloat = 244
private let topTabsActionMenuRowHeight: CGFloat = 56

@MainActor
final class TopTabsRootViewController: WViewController, VisibleContentProviding {
    private enum Page: Int {
        case wallet
        case market
        case explore

        var title: String {
            switch self {
            case .wallet:
                lang("Wallet")
            case .market:
                lang("Market")
            case .explore:
                lang("Explore")
            }
        }
    }

    private(set) var homeVC: HomeVC

    private let settingsNavigationController: WNavigationController

    private let walletPage: TopTabsPageViewController
    private let marketPage: TopTabsPageViewController
    private let explorePage: TopTabsPageViewController

    private var segmentedController: WSegmentedController!
    private let tabControlContainer = UIView()
    private var navigationBarTitleWidthConstraint: NSLayoutConstraint?
    private let accountSwitcherButton = TopTabsAccountButton()
    private let bottomGradientView = TopTabsBottomGradientView()
    private let bottomBar = UIStackView()
    private let searchButton = TopTabsSearchButton()
    private let actionsButton = TopTabsActionsButton()
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private var actionsMenuInteraction: ContextMenuInteraction?
    private var baseAdditionalSafeAreaInsets: [ObjectIdentifier: UIEdgeInsets] = [:]
    private var accountObservation: ObserveToken?
    private var sharedNavigationPaths: [Page: [UIViewController]] = [:]
    private var activePage: Page = .wallet
    private let settingsDetailViewControllers = NSHashTable<UIViewController>.weakObjects()

    private var sharedMainNavigationController: WNavigationController? {
        return navigationController as? WNavigationController
    }

    var visibleContentProviderViewController: UIViewController {
        if drawerContainerViewController?.isDrawerOpen == true {
            return resolvedSettingsNavigationController
        }
        if let visibleViewController = sharedMainNavigationController?.visibleViewController,
           visibleViewController !== self {
            return visibleViewController
        }
        return page(for: selectedPage).contentViewController
    }

    var currentTabId: AppTabId {
        if drawerContainerViewController?.isDrawerOpen == true {
            return .settings
        }
        return switch selectedPage {
        case .explore: .explore
        case .wallet, .market: .wallet
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

    private var shouldUseFullWidthDrawerOpeningGesture: Bool {
        guard selectedPage == .wallet,
              let navigationController = navigationController(for: selectedPage) else {
            return false
        }
        if isSettingsDetail(navigationController.topViewController) {
            return true
        }
        return navigationController.viewControllers.count <= 1
    }

    var drawerOpeningGesturePriorityRegions: [DrawerOpeningGesturePriorityRegion] {
        guard selectedPage == .wallet,
              sharedMainNavigationController?.topViewController === self else {
            return []
        }
        return homeVC.drawerOpeningGesturePriorityRegions
    }

    var drawerSettingsViewController: UIViewController {
        resolvedSettingsNavigationController
    }

    init() {
        let homeVC = HomeVC(rootNavigationStyle: .topTabsNavigationBar)
        let settingsNavigationController = AppTabManager.shared.makeNavigationController(for: .settings, layout: .tab)
            ?? AppTabLazyNavigationController { SettingsVC() }
        let marketViewController = MarketVC(usesTopTabsChrome: true)
        let exploreViewController = ExploreTabVC(
            showsSearchBar: false,
            showsLargeTitle: false,
            usesTopTabsChrome: true
        )

        self.homeVC = homeVC
        self.settingsNavigationController = settingsNavigationController
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
        view.backgroundColor = .air.background

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(drawerCloseControlExperimentDidChange),
            name: DrawerCloseControlExperiment.didChangeNotification,
            object: nil
        )

        let pages = [walletPage, marketPage, explorePage]
        pages.forEach {
            addChild($0)
            $0.didMove(toParent: self)
        }

        configureNavigationControllers()
        pages.map(\.contentViewController).forEach(applyChromeInsets)
        configurePager()
        configureBottomBar()
        observeAccountSwitcher()
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
        bottomBarBottomConstraint?.constant = view.safeAreaInsets.bottom > 0 ? 2 : -16
    }

    func applyTabConfiguration(_ orderedIds: [AppTabId]) {
        // Top Tabs intentionally follows the experimental fixed order from the design.
    }

    func takeNavigationStack(for id: AppTabId, keepingRoot: Bool) -> [UIViewController]? {
        if id != .settings {
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
        guard let navigationController = navigationController(for: id) else { return nil }
        if navigationController.viewControllers.isEmpty,
           currentTabId == id,
           let lazyNavigationController = navigationController as? AppTabLazyNavigationController {
            lazyNavigationController.ensureRootViewControllerInstalled()
        }
        let stack = navigationController.viewControllers
        guard !stack.isEmpty else { return nil }
        stack.forEach(removeChrome)
        if keepingRoot, let rootViewController = stack.first {
            navigationController.setViewControllers([rootViewController], animated: false)
        } else {
            navigationController.setViewControllers([Self.makeNavigationStackPlaceholder()], animated: false)
        }
        return stack
    }

    func setNavigationStack(_ stack: [UIViewController], for id: AppTabId) {
        if id != .settings {
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
            return
        }
        guard !stack.isEmpty, let navigationController = navigationController(for: id) else { return }
        if id == .wallet, let homeVC = stack.first as? HomeVC {
            self.homeVC = homeVC
        }
        if let lazyNavigationController = navigationController as? AppTabLazyNavigationController {
            lazyNavigationController.setPreservedViewControllers(stack)
        } else {
            navigationController.setViewControllers(stack, animated: false)
        }
        stack.forEach(applyChromeInsets)
        updateRootChromeVisibilityForSelectedPage()
    }

    func setNavigationPath(_ path: [UIViewController], for id: AppTabId) {
        if id != .settings {
            guard let pageValue = pageValue(for: id) else { return }
            sharedNavigationPaths[pageValue] = path
            path.forEach(applyChromeInsets)
            if pageValue == activePage {
                installSharedNavigationPath(for: pageValue)
            }
            updateRootChromeVisibilityForSelectedPage()
            return
        }
        guard let navigationController = navigationController(for: id) else { return }
        if let lazyNavigationController = navigationController as? AppTabLazyNavigationController {
            lazyNavigationController.ensureRootViewControllerInstalled()
        }
        guard let rootViewController = navigationController.viewControllers.first else { return }
        let stack = [rootViewController] + path
        navigationController.setViewControllers(stack, animated: false)
        stack.forEach(applyChromeInsets)
        updateRootChromeVisibilityForSelectedPage()
    }

    @discardableResult
    func selectTab(_ id: AppTabId, popToRoot: Bool = false) -> Bool {
        if id == .settings {
            let navigationController = resolvedSettingsNavigationController
            if popToRoot {
                navigationController.popToRootViewController(animated: true)
            }
            drawerContainerViewController?.setDrawerOpen(true, animated: true)
            return true
        }

        let page: Page
        switch id {
        case .wallet: page = .wallet
        case .explore: page = .explore
        default: return false
        }
        drawerContainerViewController?.setDrawerOpen(false, animated: true)
        if page != activePage {
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

    func switchToSettings(path: [UIViewController]) {
        if !path.isEmpty, pushSettingsPathIntoMainArea(path, animated: true) {
            return
        }
        let navigationController = resolvedSettingsNavigationController
        guard let rootViewController = navigationController.viewControllers.first else { return }
        navigationController.setViewControllers([rootViewController] + path, animated: false)
        path.forEach(applyChromeInsets)
        guard selectTab(.settings) else { return }
        updateRootChromeVisibilityForSelectedPage()
    }

    @discardableResult
    func pushOnSettingsRoot(_ viewController: UIViewController, animated: Bool = true) -> Bool {
        if pushSettingsDetailIntoMainArea(viewController, animated: animated) {
            return true
        }
        let navigationController = resolvedSettingsNavigationController
        applyChromeInsets(to: viewController)
        navigationController.pushViewController(viewController, animated: animated)
        drawerContainerViewController?.setDrawerOpen(true, animated: true)
        return true
    }

    func scrollToTop() {
        if drawerContainerViewController?.isDrawerOpen == true {
            return
        }
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
                id: "market",
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
            style: .compactRootHeader,
            delegate: self
        )
        self.segmentedController = segmentedController
        if let drawerContainerViewController {
            drawerContainerViewController.shouldBeginOpeningGesture = { [weak self] in
                guard let self,
                      selectedPage == .wallet,
                      let navigationController = navigationController(for: selectedPage) else {
                    return false
                }
                return navigationController.viewControllers.count <= 1
                    || isSettingsDetail(navigationController.topViewController)
            }
            drawerContainerViewController.shouldUseFullWidthOpeningGesture = { [weak self] in
                self?.shouldUseFullWidthDrawerOpeningGesture == true
            }
            drawerContainerViewController.onWillOpen = { [weak self] in
                self?.configureSettingsDrawerNavigation()
            }
            segmentedController.scrollView.panGestureRecognizer.require(
                toFail: drawerContainerViewController.openingGestureRecognizer
            )
        }
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
        tabControlContainer.backgroundColor = .clear
        tabControlContainer.translatesAutoresizingMaskIntoConstraints = false
        tabControlContainer.addSubview(accountSwitcherButton)
        tabControlContainer.addSubview(segmentedControl)
        navigationItem.titleView = tabControlContainer

        let titleWidthConstraint = tabControlContainer.widthAnchor.constraint(
            equalToConstant: max(0, view.bounds.width - 32)
        )
        navigationBarTitleWidthConstraint = titleWidthConstraint

        NSLayoutConstraint.activate([
            titleWidthConstraint,
            tabControlContainer.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),

            accountSwitcherButton.leadingAnchor.constraint(equalTo: tabControlContainer.leadingAnchor),
            accountSwitcherButton.topAnchor.constraint(equalTo: tabControlContainer.topAnchor),
            accountSwitcherButton.widthAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),
            accountSwitcherButton.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),

            segmentedControl.leadingAnchor.constraint(
                equalTo: accountSwitcherButton.trailingAnchor,
                constant: topTabsNavigationBarSpacing
            ),
            segmentedControl.trailingAnchor.constraint(equalTo: tabControlContainer.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: tabControlContainer.topAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: topTabsNavigationBarHeight),
        ])
    }

    private func observeAccountSwitcher() {
        accountObservation = observe { [weak self] in
            guard let self else { return }
            accountSwitcherButton.configure(account: AccountStore.account)
        }
    }

    private func configureNavigationControllers() {
        settingsNavigationController.pushViewControllerInterceptor = { [weak self] viewController, animated in
            self?.pushSettingsDetailIntoMainArea(viewController, animated: animated) == true
        }
        sharedMainNavigationController?.onWillShowViewController = { [weak self] viewController in
            guard let self, let sharedMainNavigationController else { return }
            applyChromeInsets(to: viewController)
            updateRootChromeVisibility(
                for: sharedMainNavigationController,
                showing: viewController
            )
        }
        sharedMainNavigationController?.navigationTransitionAnimationController = nil
        sharedMainNavigationController?.navigationTransitionInteractionController = nil
        sharedMainNavigationController?.popViewControllerInterceptor = { [weak self] animated in
            guard let self,
                  let sharedMainNavigationController,
                  isSettingsDetail(sharedMainNavigationController.topViewController),
                  let drawerContainerViewController else {
                return false
            }
            drawerContainerViewController.setDrawerOpen(true, animated: animated)
            return true
        }
        settingsNavigationController.onWillShowViewController = { [weak self] viewController in
            self?.applyChromeInsets(to: viewController)
        }
        settingsNavigationController.viewControllers.forEach(applyChromeInsets)
    }

    private func updateRootChromeVisibility(
        for navigationController: WNavigationController,
        showing viewController: UIViewController
    ) {
        guard navigationController === self.navigationController(for: selectedPage) else {
            return
        }
        let isShowingRoot = navigationController.viewControllers.first === viewController
        bottomGradientView.isHidden = !isShowingRoot
        bottomBar.isHidden = !isShowingRoot
    }

    private func updateRootChromeVisibilityForSelectedPage() {
        guard let navigationController = navigationController(for: selectedPage),
              let viewController = navigationController.visibleViewController else {
            return
        }
        updateRootChromeVisibility(for: navigationController, showing: viewController)
    }

    private func applyChromeInsets(to viewController: UIViewController) {
        let identifier = ObjectIdentifier(viewController)
        let baseInsets = baseAdditionalSafeAreaInsets[identifier] ?? viewController.additionalSafeAreaInsets
        baseAdditionalSafeAreaInsets[identifier] = baseInsets
        let isRootViewController = [walletPage, marketPage, explorePage].contains {
            $0.contentViewController === viewController
        }
        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: baseInsets.top,
            left: baseInsets.left,
            bottom: baseInsets.bottom + (isRootViewController ? topTabsBottomChromeHeight : 0),
            right: baseInsets.right
        )
    }

    private func removeChrome(from viewController: UIViewController) {
        let identifier = ObjectIdentifier(viewController)
        if let baseInsets = baseAdditionalSafeAreaInsets.removeValue(forKey: identifier) {
            viewController.additionalSafeAreaInsets = baseInsets
        }
    }

    private func configureBottomBar() {
        searchButton.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(openSearch))
        )

        bottomGradientView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomGradientView)

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.axis = .horizontal
        bottomBar.alignment = .fill
        bottomBar.spacing = 12
        bottomBar.addArrangedSubview(searchButton)
        bottomBar.addArrangedSubview(actionsButton)
        view.addSubview(bottomBar)

        let bottomBarBottomConstraint = bottomBar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: 2
        )
        self.bottomBarBottomConstraint = bottomBarBottomConstraint
        NSLayoutConstraint.activate([
            bottomGradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomGradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomGradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomGradientView.heightAnchor.constraint(equalToConstant: topTabsBottomGradientHeight),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            bottomBarBottomConstraint,
            bottomBar.heightAnchor.constraint(equalToConstant: 48),
            actionsButton.widthAnchor.constraint(equalToConstant: 48),
        ])

        let interaction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: 24, cornerCurve: .continuous),
                showsBackdropCutout: true
            )
        ) { [weak self] _ in
            self?.makeActionsMenuConfiguration()
        }
        interaction.attach(to: actionsButton)
        actionsMenuInteraction = interaction
    }

    private func makeActionsMenuConfiguration() -> ContextMenuConfiguration {
        guard let account = AccountStore.account else {
            return ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: []),
                backdrop: .defaultBlurred()
            )
        }
        let accountContext = AccountContext(accountId: account.id)
        var items: [ContextMenuItem] = [
            actionMenuItem(
                title: lang("Fund"),
                iconName: "DepositIconLarge",
                action: { AppActions.showReceive(accountContext: accountContext, chain: nil) }
            ),
        ]
        if account.supportsSend {
            items.append(actionMenuItem(
                title: lang("Send"),
                iconName: "SendIconLarge",
                action: { AppActions.showSend(accountContext: accountContext, prefilledValues: .init()) }
            ))
        }
        if account.supportsSwap {
            items.append(actionMenuItem(
                title: lang("Swap"),
                iconName: "SwapIconLarge",
                action: {
                    AppActions.showSwap(
                        accountContext: accountContext,
                        defaultSellingToken: nil,
                        defaultBuyingToken: nil,
                        defaultSellingAmount: nil,
                        push: nil
                    )
                }
            ))
        }
        if account.supportsEarn {
            items.append(actionMenuItem(
                title: lang("Earn"),
                iconName: "EarnIconLarge",
                action: { AppActions.showEarn(accountContext: accountContext, tokenSlug: nil) }
            ))
        }
        items.append(actionMenuItem(
            title: lang("Scan QR Code"),
            iconName: "ScanIconLarge",
            action: { AppActions.scanAndHandleQR(accountContext: accountContext) }
        ))

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: ContextMenuStyle(
                minWidth: topTabsActionMenuWidth,
                maxWidth: topTabsActionMenuWidth,
                sourceSpacing: 10
            )
        )
    }

    private func actionMenuItem(
        title: String,
        iconName: String,
        action: @escaping @MainActor () -> Void
    ) -> ContextMenuItem {
        .custom(
            .swiftUI(
                preferredWidth: topTabsActionMenuWidth,
                sizing: .fixed(height: topTabsActionMenuRowHeight),
                interaction: .selectable(handler: action)
            ) { _ in
                TopTabsActionMenuRow(title: title, iconName: iconName)
            }
        )
    }

    @objc private func openSearch() {
        let viewController = ExploreSearchOverlayVC()
        viewController.modalPresentationStyle = .overFullScreen
        viewController.modalTransitionStyle = .crossDissolve
        present(viewController, animated: true)
    }

    @objc private func openSettings() {
        selectTab(.settings)
    }

    @objc private func drawerCloseControlExperimentDidChange() {
        configureSettingsDrawerNavigation()
    }

    private var resolvedSettingsNavigationController: WNavigationController {
        if let lazyNavigationController = settingsNavigationController as? AppTabLazyNavigationController {
            lazyNavigationController.ensureRootViewControllerInstalled()
        }
        configureSettingsDrawerNavigation()
        settingsNavigationController.viewControllers.forEach(applyChromeInsets)
        return settingsNavigationController
    }

    private func configureSettingsDrawerNavigation() {
        guard let settingsViewController = settingsNavigationController.viewControllers.first as? SettingsVC else {
            return
        }
        settingsViewController.presentationStyle = .drawer
        settingsViewController.drawerCloseControl = switch DrawerCloseControlExperiment.variant {
        case .closeButton:
            .closeButton
        case .currentTabTitle:
            .mainTabTitle(selectedPage.title)
        }
        settingsViewController.onDrawerClose = { [weak self] in
            self?.closeSettingsDrawerAndReturnToMainTab()
        }
    }

    private func closeSettingsDrawerAndReturnToMainTab() {
        guard let drawerContainerViewController else { return }
        drawerContainerViewController.setDrawerOpen(false, animated: true)
        removeSettingsDetailsFromMainArea(animated: true)
    }

    private func pushSettingsPathIntoMainArea(
        _ path: [UIViewController],
        animated: Bool
    ) -> Bool {
        guard let firstViewController = path.first,
              let navigationController = navigationController(for: selectedPage),
              let drawerContainerViewController else {
            return false
        }

        if path.count == 1 {
            return pushSettingsDetailIntoMainArea(firstViewController, animated: animated)
        }

        path.forEach(applyChromeInsets)
        let showSettingsPath = { [self] in
            settingsDetailViewControllers.removeAllObjects()
            markAsSettingsDetail(firstViewController)
            navigationController.setViewControllers([self] + path, animated: false)
        }
        if animated, navigationController.viewIfLoaded?.window != nil {
            drawerContainerViewController.setDrawerOpen(false, animated: true)
            performSettingsCrossfade(in: navigationController, changes: showSettingsPath)
        } else {
            showSettingsPath()
            drawerContainerViewController.setDrawerOpen(false, animated: false)
        }
        return true
    }

    private func pushSettingsDetailIntoMainArea(
        _ viewController: UIViewController,
        animated: Bool
    ) -> Bool {
        guard let navigationController = navigationController(for: selectedPage),
              let drawerContainerViewController else {
            return false
        }
        markAsSettingsDetail(viewController)
        applyChromeInsets(to: viewController)

        let previousSettingsDetail = navigationController.topViewController.flatMap { topViewController in
            isSettingsDetail(topViewController) ? topViewController : nil
        }
        let pushSettingsDetail = {
            navigationController.pushViewController(viewController, animated: false)
        }
        let replaceSettingsDetail = { [self] in
            if let previousSettingsDetail {
                settingsDetailViewControllers.remove(previousSettingsDetail)
            }
            navigationController.setViewControllers(
                Array(navigationController.viewControllers.dropLast()) + [viewController],
                animated: false
            )
        }
        if animated, navigationController.viewIfLoaded?.window != nil {
            if let previousSettingsDetail {
                var crossfadeFinished = false
                var drawerCloseFinished = false
                let finishReplacement = { [weak self, weak navigationController, weak previousSettingsDetail] in
                    guard crossfadeFinished,
                          drawerCloseFinished,
                          let self,
                          let navigationController,
                          let previousSettingsDetail else {
                        return
                    }
                    settingsDetailViewControllers.remove(previousSettingsDetail)
                    navigationController.setViewControllers(
                        navigationController.viewControllers.filter { $0 !== previousSettingsDetail },
                        animated: false
                    )
                }
                drawerContainerViewController.setDrawerOpen(false, animated: true) {
                    drawerCloseFinished = true
                    finishReplacement()
                }
                performSettingsCrossfade(
                    in: navigationController,
                    changes: pushSettingsDetail,
                    completion: { _ in
                        crossfadeFinished = true
                        finishReplacement()
                    }
                )
            } else {
                drawerContainerViewController.setDrawerOpen(false, animated: true)
                performSettingsCrossfade(in: navigationController, changes: pushSettingsDetail)
            }
        } else {
            if previousSettingsDetail != nil {
                replaceSettingsDetail()
            } else {
                pushSettingsDetail()
            }
            drawerContainerViewController.setDrawerOpen(false, animated: false)
        }
        return true
    }

    private func markAsSettingsDetail(_ viewController: UIViewController) {
        settingsDetailViewControllers.add(viewController)
    }

    private func isSettingsDetail(_ viewController: UIViewController?) -> Bool {
        guard let viewController else { return false }
        return settingsDetailViewControllers.allObjects.contains { $0 === viewController }
    }

    private func removeSettingsDetailsFromMainArea(animated: Bool) {
        guard let navigationController = sharedMainNavigationController else {
            return
        }
        let removedViewControllers = Array(navigationController.viewControllers.dropFirst())
        guard removedViewControllers.contains(where: isSettingsDetail) else {
            sharedNavigationPaths[activePage] = []
            settingsDetailViewControllers.removeAllObjects()
            return
        }
        let popToSegmentedRoot = { [self] in
            navigationController.setViewControllers([self], animated: false)
            sharedNavigationPaths[activePage] = []
            settingsDetailViewControllers.removeAllObjects()
        }
        if animated, navigationController.view.window != nil {
            performSettingsCrossfade(in: navigationController, changes: popToSegmentedRoot)
        } else {
            popToSegmentedRoot()
        }
    }

    private func performSettingsCrossfade(
        in navigationController: WNavigationController,
        changes: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        let configuration = drawerContainerViewController?.configuration
        let slideDuration = max(
            configuration?.minimumTransitionDuration ?? 0,
            configuration?.transitionDuration ?? 0
        )
        UIView.transition(
            with: navigationController.view,
            duration: min(0.1, slideDuration / 4),
            options: [
                .transitionCrossDissolve,
                .allowAnimatedContent,
                .allowUserInteraction,
                .beginFromCurrentState,
            ],
            animations: changes,
            completion: completion
        )
    }

    private func captureSharedNavigationPath(for page: Page) {
        guard let sharedMainNavigationController else { return }
        sharedNavigationPaths[page] = Array(sharedMainNavigationController.viewControllers.dropFirst())
    }

    private func installSharedNavigationPath(for page: Page) {
        guard let sharedMainNavigationController else { return }
        let path = sharedNavigationPaths[page] ?? []
        sharedMainNavigationController.setViewControllers([self] + path, animated: false)
        updateRootChromeVisibilityForSelectedPage()
    }

    private func navigationController(for id: AppTabId) -> WNavigationController? {
        if id != .settings {
            return sharedMainNavigationController
        }
        return settingsNavigationController
    }

    private func navigationController(for page: Page) -> WNavigationController? {
        sharedMainNavigationController
    }

    private func page(for id: AppTabId) -> TopTabsPageViewController? {
        return switch id {
        case .wallet: walletPage
        case .explore: explorePage
        default: nil
        }
    }

    private func pageValue(for id: AppTabId) -> Page? {
        return switch id {
        case .wallet: .wallet
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

    private static func makeNavigationStackPlaceholder() -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        return viewController
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
        updateRootChromeVisibilityForSelectedPage()
    }
}

@MainActor
private final class TopTabsAccountButton: UIControl {
    private let iconView = IconView(size: topTabsNavigationBarHeight)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(account: MAccount?) {
        iconView.config(with: account)
        accessibilityLabel = lang("Settings")
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
private final class TopTabsSearchButton: UIControl {
    private let effectView = UIVisualEffectView()
    private let magnifyingGlass = UIImageView(image: UIImage(
        systemName: "magnifyingglass",
        withConfiguration: UIImage.SymbolConfiguration(
            font: WTypography.uiFont(.supportingEmphasized, content: .technical)
        )
    ))
    private let titleLabel = UILabel()
    private let microphone = UIImageView(image: UIImage(
        systemName: "microphone",
        withConfiguration: UIImage.SymbolConfiguration(
            font: WTypography.uiFont(.bodyEmphasized, content: .technical)
        )
    ))

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = lang("Search or Ask")
        accessibilityTraits = .button

        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effectView.effect = effect
            effectView.cornerConfiguration = .corners(radius: 24)
        } else {
            effectView.effect = UIBlurEffect(style: .systemMaterial)
        }
        effectView.isUserInteractionEnabled = true
        addSubview(effectView)

        magnifyingGlass.tintColor = .label
        magnifyingGlass.contentMode = .scaleAspectFit
        titleLabel.text = lang("Search or Ask")
        titleLabel.applyTextStyle(.body)
        titleLabel.textColor = .tertiaryLabel
        microphone.tintColor = .secondaryLabel
        microphone.contentMode = .scaleAspectFit

        let stackView = UIStackView(arrangedSubviews: [magnifyingGlass, titleLabel, microphone])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.isUserInteractionEnabled = false
        addSubview(stackView)

        effectView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            magnifyingGlass.widthAnchor.constraint(equalToConstant: 20),
            microphone.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #unavailable(iOS 26) {
            effectView.layer.cornerRadius = bounds.height / 2
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
        }
    }
}

@MainActor
private final class TopTabsActionsButton: UIButton {
    private let effectView = UIVisualEffectView()
    private let tintView = UIView()
    private let iconView = TopTabsActionsGlyphView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = lang("Actions")

        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = AirTintColor
            effectView.effect = effect
            effectView.cornerConfiguration = .corners(radius: 24)
        } else {
            effectView.effect = UIBlurEffect(style: .systemMaterial)
        }
        effectView.isUserInteractionEnabled = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(effectView, at: 0)

        tintView.backgroundColor = AirTintColor
        tintView.isHidden = IOS_26_MODE_ENABLED
        tintView.isUserInteractionEnabled = false
        tintView.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(tintView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tintView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateTintColor()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #unavailable(iOS 26) {
            effectView.layer.cornerRadius = bounds.height / 2
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
        }
    }

    private func updateTintColor() {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = tintColor
            effectView.effect = effect
        }
        tintView.backgroundColor = tintColor
    }
}

private struct TopTabsActionMenuRow: View {
    let title: String
    let iconName: String

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: .airBundle(iconName))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundStyle(Color.primary)

            Text(title)
                .textStyle(.bodyEmphasized)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

@MainActor
private final class TopTabsActionsGlyphView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        UIColor.white.setFill()
        let radius: CGFloat = 3.25
        for center in [
            CGPoint(x: 12.25, y: 12.25),
            CGPoint(x: 23.75, y: 12.25),
            CGPoint(x: 12.25, y: 23.75),
            CGPoint(x: 23.75, y: 23.75),
        ] {
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ).fill()
        }
    }
}

@MainActor
private final class TopTabsBottomGradientView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(gradientLayer)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

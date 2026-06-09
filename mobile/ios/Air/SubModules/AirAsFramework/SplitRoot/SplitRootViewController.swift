import UIKit
import UIBrowser
import UIAgent
import UIComponents
import UIHome
import UISettings
import UIAssets
import WalletCore
import WalletContext
import SwiftNavigation

private let sidebarEdgeFadeWidth: CGFloat = 32

private final class LazySplitRootNavigationController: WNavigationController {
    private let makeRootViewController: () -> UIViewController
    private var didInstallRootViewController = false

    init(makeRootViewController: @escaping () -> UIViewController) {
        self.makeRootViewController = makeRootViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ensureRootViewControllerInstalled()
    }

    func ensureRootViewControllerInstalled() {
        guard !didInstallRootViewController else { return }
        didInstallRootViewController = true
        viewControllers = [makeRootViewController()]
    }

    func resetRootViewController() {
        didInstallRootViewController = true
        viewControllers = [makeRootViewController()]
    }

    func setPreservedViewControllers(_ viewControllers: [UIViewController]) {
        didInstallRootViewController = true
        self.viewControllers = viewControllers
    }
}

@MainActor
final class SplitRootViewController: UISplitViewController, VisibleContentProviding {

    private let viewModel = SplitRootViewModel()

    private let sidebarViewController: SplitRootSidebarViewController
    private let sidebarNavigationController: WNavigationController
    private var sidebarEdgeCoverEntries: [(navigationController: WNavigationController, view: EdgeGradientView, color: UIColor)] = []

    private(set) var homeNavigationController: WNavigationController
    private(set) var agentNavigationController: WNavigationController
    private(set) var exploreNavigationController: WNavigationController
    private(set) var settingsNavigationController: WNavigationController

    var visibleContentProviderViewController: UIViewController {
        currentNavigationController.visibleViewController ?? currentNavigationController
    }

    private var selectedTab: SplitRootTab { viewModel.selectedTab }
    var currentTab: SplitRootTab { selectedTab }

    func takeNavigationStack(for tab: SplitRootTab, keepingRoot: Bool) -> [UIViewController]? {
        let navigationController = navigationController(for: tab)
        if navigationController.viewControllers.isEmpty,
           selectedTab == tab,
           let lazyNavigationController = navigationController as? LazySplitRootNavigationController {
            lazyNavigationController.ensureRootViewControllerInstalled()
        }
        let stack = navigationController.viewControllers
        guard !stack.isEmpty else { return nil }
        if keepingRoot, let rootViewController = stack.first {
            navigationController.setViewControllers([rootViewController], animated: false)
        } else {
            navigationController.setViewControllers([Self.makeNavigationStackPlaceholder()], animated: false)
        }
        return stack
    }

    func setNavigationStack(_ stack: [UIViewController], for tab: SplitRootTab) {
        guard !stack.isEmpty else { return }
        let navigationController = navigationController(for: tab)
        if let lazyNavigationController = navigationController as? LazySplitRootNavigationController {
            lazyNavigationController.setPreservedViewControllers(stack)
        } else {
            navigationController.setViewControllers(stack, animated: false)
        }
        if selectedTab == tab {
            onTabSelect(tab: tab)
        }
    }

    init() {
        self.sidebarViewController = SplitRootSidebarViewController(viewModel: viewModel)
        self.sidebarNavigationController = WNavigationController(rootViewController: sidebarViewController)

        self.homeNavigationController = WNavigationController(rootViewController: SplitHomeVC())
        self.agentNavigationController = LazySplitRootNavigationController {
            AgentEntryPoint.makeRootViewController()
        }
        self.exploreNavigationController = LazySplitRootNavigationController {
            ExploreTabVC()
        }
        self.settingsNavigationController = LazySplitRootNavigationController {
            SettingsVC()
        }

        super.init(style: .doubleColumn)
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
        let screenSize = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let isMini = screenSize < 1150
        preferredPrimaryColumnWidthFraction = isMini ? 0.34 : 0.29

        setViewController(sidebarNavigationController, for: .primary)
        setViewController(homeNavigationController, for: .secondary)
        sidebarViewController.setSelectedTab(.home)

        view.backgroundColor = .black
        installSidebarEdgeCover(in: homeNavigationController, color: .air.groupedBackground)
        installSidebarEdgeCover(in: exploreNavigationController, color: .air.background)

        observe { [weak self] in
            guard let self else { return }
            let selectedTab = viewModel.selectedTab
            onTabSelect(tab: selectedTab)
        }
        viewModel.onCurrentTabTap = { [weak self] tab in
            guard let self else { return }
            let nc = navigationController(for: tab)
            showDetailViewController(nc, sender: self)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSidebarEdgeCoverFrames()
    }

    func select(tab: SplitRootTab, popToRoot: Bool = false) {
        viewModel.selectedTab = tab
        if popToRoot {
            let nc = navigationController(for: tab)
            nc.popToRootViewController(animated: true)
        }
    }

    func onTabSelect(tab: SplitRootTab) {
        let nc = navigationController(for: tab)
        if isCollapsed {
            if viewController(for: .secondary) !== nc {
                showDetailViewController(nc, sender: self)
            }
        } else if viewController(for: .secondary) !== nc {
            setViewController(nc, for: .secondary)
        }
    }

    func isHomeRootSelected() -> Bool {
        selectedTab == .home && homeNavigationController.viewControllers.first is SplitHomeVC
    }

    func pushOnHome(_ viewController: UIViewController) -> Bool {
        guard selectedTab == .home else {
            return false
        }
        homeNavigationController.pushViewController(viewController, animated: true)
        return true
    }

    func showAgent() {
        select(tab: .agent)
    }

    func debugOnly_resetAgentRoot() {
        guard let agentNavigationController = agentNavigationController as? LazySplitRootNavigationController else {
            return
        }
        agentNavigationController.resetRootViewController()
    }

    func showExplore() {
        select(tab: .explore)
    }

    func showHome(popToRoot: Bool) {
        select(tab: .home, popToRoot: popToRoot)
        if let rootViewController = view.window?.rootViewController, rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: true)
        }
    }

    func showSettings(path: [UIViewController]) {
        select(tab: .settings, popToRoot: false)
        (settingsNavigationController as? LazySplitRootNavigationController)?.ensureRootViewControllerInstalled()
        guard let rootViewController = settingsNavigationController.viewControllers.first else { return }
        settingsNavigationController.setViewControllers([rootViewController] + path, animated: false)
    }

    func showTemporaryViewAccount(accountId: String) {
        select(tab: .home, popToRoot: false)
        focusSidebarAccount(accountId: accountId, animated: true)

        if let splitHomeVC = homeNavigationController.topViewController as? SplitHomeVC,
           isTemporarySplitHome(splitHomeVC, accountId: accountId) {
            return
        }

        dismissTemporaryViewAccountIfNeeded(animated: false)
        let vc = SplitHomeVC(accountSource: .accountId(accountId))
        homeNavigationController.pushViewController(vc, animated: true)
    }

    func dismissTemporaryViewAccountIfNeeded(animated: Bool) {
        let hasTemporaryHomeInStack = homeNavigationController.viewControllers.contains { viewController in
            guard let splitHomeVC = viewController as? SplitHomeVC else { return false }
            guard case .accountId = splitHomeVC.splitHomeAccountContext.source else { return false }
            return true
        }
        guard hasTemporaryHomeInStack else { return }
        homeNavigationController.popToRootViewController(animated: animated)
        syncSidebarFocusWithHomeStack(animated: animated)
    }

    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
        let nc = currentNavigationController
        if nc.showExistingAssetsTab(accountSource: accountSource, selectedTab: selectedTab, animated: true) {
            return
        }

        let shouldPushCollection = shouldPushNftCollectionFullscreen(
            accountSource: accountSource,
            selectedTab: selectedTab,
            collectionsFilter: collectionsFilter
        )

        if shouldPushCollection, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
            nc.pushViewController(NftsFullScreenVC(accountSource: accountSource, filter: collectionsFilter), animated: true)
            return
        }
        let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTab: selectedTab)
        nc.pushViewController(assetsVC, animated: true)
        if shouldPushCollection {
            nc.pushViewController(NftsFullScreenVC(accountSource: accountSource, filter: collectionsFilter), animated: false)
        }
    }

    func focusSidebarAccount(accountId: String?, animated: Bool) {
        sidebarViewController.focusAccount(accountId, animated: animated)
    }

    func syncSidebarFocusWithHomeStack(animated: Bool) {
        guard selectedTab == .home else {
            focusSidebarAccount(accountId: nil, animated: animated)
            return
        }
        guard let splitHomeVC = homeNavigationController.topViewController as? SplitHomeVC,
              case .accountId(let accountId) = splitHomeVC.splitHomeAccountContext.source else {
            focusSidebarAccount(accountId: nil, animated: animated)
            return
        }
        focusSidebarAccount(accountId: accountId, animated: animated)
    }

    private var currentNavigationController: WNavigationController {
        navigationController(for: selectedTab)
    }

    private func isTemporarySplitHome(_ splitHomeVC: SplitHomeVC, accountId: String) -> Bool {
        guard case .accountId(let splitHomeAccountId) = splitHomeVC.splitHomeAccountContext.source else { return false }
        guard splitHomeVC.splitHomeAccountContext.account.isTemporaryView else { return false }
        return splitHomeAccountId == accountId
    }

    private func navigationController(for tab: SplitRootTab) -> WNavigationController {
        switch tab {
        case .home:
            homeNavigationController
        case .agent:
            agentNavigationController
        case .explore:
            exploreNavigationController
        case .settings:
            settingsNavigationController
        }
    }

    private static func makeNavigationStackPlaceholder() -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        return viewController
    }

    private func installSidebarEdgeCover(in navigationController: WNavigationController, color: UIColor) {
        let edgeCoverView = EdgeGradientView()
        edgeCoverView.color = color.withAlphaComponent(0.8)
        edgeCoverView.isHidden = true
        navigationController.view.clipsToBounds = false
        navigationController.view.addSubview(edgeCoverView)
        sidebarEdgeCoverEntries.append((navigationController, edgeCoverView, color))
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

        for (navigationController, edgeCoverView, color) in sidebarEdgeCoverEntries {
            guard navigationController.view.window != nil else {
                edgeCoverView.isHidden = true
                continue
            }
            edgeCoverView.color = color.withAlphaComponent(0.8)
            edgeCoverView.direction = direction
            edgeCoverView.solidEdgeLength = outerGap
            edgeCoverView.frame = navigationController.view.convert(targetFrame, from: view)
            edgeCoverView.isHidden = false
            navigationController.view.bringSubviewToFront(edgeCoverView)
        }
    }

    private func hideSidebarEdgeCovers() {
        for entry in sidebarEdgeCoverEntries {
            entry.view.isHidden = true
        }
    }
}

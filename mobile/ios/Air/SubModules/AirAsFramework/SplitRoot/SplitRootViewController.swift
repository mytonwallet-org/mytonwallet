import UIKit
import UIComponents
import UIHome
import UIAssets
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

    private let viewModel: SplitRootViewModel

    private let sidebarViewController: SplitRootSidebarViewController
    private let sidebarNavigationController: WNavigationController
    private var sidebarEdgeCoverEntries: [SidebarEdgeCoverEntry] = []

    /// All live navigation controllers keyed by their tab id.
    private var navControllersByTabId: [AppTabId: WNavigationController]

    var visibleContentProviderViewController: UIViewController {
        currentNavigationController.visibleViewController ?? currentNavigationController
    }

    private var selectedTab: AppTabId { viewModel.selectedTab }
    var currentTabId: AppTabId { selectedTab }

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

    init() {
        self.navControllersByTabId = [:]

        let viewModel = SplitRootViewModel()
        self.viewModel = viewModel
        self.sidebarViewController = SplitRootSidebarViewController(viewModel: viewModel)
        self.sidebarNavigationController = WNavigationController(rootViewController: sidebarViewController)

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
        updatePrimaryColumnWidthFraction()

        setViewController(sidebarNavigationController, for: .primary)
        // Secondary column and tab-specific setup (edge covers, sidebar selection) are
        // deferred to applyTabConfiguration, called by AdaptiveRootViewController right
        // after loadViewIfNeeded(), so nav controllers are not needed here.

        view.backgroundColor = .black

        observe { [weak self] in
            guard let self else { return }
            let selectedTab = viewModel.selectedTab
            onTabSelect(tab: selectedTab)
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
        if popToRoot, let nc = navControllersByTabId[tab] {
            nc.popToRootViewController(animated: true)
        }
    }

    func onTabSelect(tab: AppTabId) {
        guard let nc = navControllersByTabId[tab] else { return }
        if isCollapsed {
            if viewController(for: .secondary) !== nc {
                showDetailViewController(nc, sender: self)
            }
        } else if viewController(for: .secondary) !== nc {
            setViewController(nc, for: .secondary)
        }
    }

    func isHomeRootSelected() -> Bool {
        selectedTab == .wallet && navControllersByTabId[.wallet]?.viewControllers.first is SplitHomeVC
    }

    func pushOnHome(_ viewController: UIViewController) -> Bool {
        guard selectedTab == .wallet, let homeNC = navControllersByTabId[.wallet] else { return false }
        homeNC.pushViewController(viewController, animated: true)
        return true
    }

    func showAgent() {
        select(tab: .agent)
    }

    func debugOnly_resetAgentRoot() {
        guard let agentNC = navControllersByTabId[.agent] as? AppTabLazyNavigationController else { return }
        agentNC.resetRootViewController()
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
        select(tab: .settings, popToRoot: false)
        guard let settingsNC = navControllersByTabId[.settings] else { return }
        (settingsNC as? AppTabLazyNavigationController)?.ensureRootViewControllerInstalled()
        guard let rootViewController = settingsNC.viewControllers.first else { return }
        settingsNC.setViewControllers([rootViewController] + path, animated: false)
    }

    func showTemporaryViewAccount(accountId: String) {
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

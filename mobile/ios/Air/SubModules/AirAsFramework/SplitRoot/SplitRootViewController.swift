import UIKit
import UIBrowser
import UIComponents
import UIHome
import UISettings
import UIAssets
import WalletCore
import WalletContext
import SwiftNavigation

@MainActor
final class SplitRootViewController: UISplitViewController, VisibleContentProviding {

    private let viewModel = SplitRootViewModel()
    
    private let sidebarViewController: SplitRootSidebarViewController
    private let sidebarNavigationController: WNavigationController
    
    private(set) var homeNavigationController: WNavigationController
    private(set) var exploreNavigationController: WNavigationController
    private(set) var settingsNavigationController: WNavigationController
    
    var visibleContentProviderViewController: UIViewController {
        currentNavigationController.visibleViewController ?? currentNavigationController
    }
    
    private var selectedTab: SplitRootTab { viewModel.selectedTab }
    
    init() {
        self.sidebarViewController = SplitRootSidebarViewController(viewModel: viewModel)
        self.sidebarNavigationController = WNavigationController(rootViewController: sidebarViewController)
        
        self.homeNavigationController = WNavigationController(rootViewController: SplitHomeVC())
        self.exploreNavigationController = WNavigationController(rootViewController: ExploreTabVC())
        self.settingsNavigationController = WNavigationController(rootViewController: SettingsVC())
        
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
    
    func showExplore() {
        select(tab: .explore)
    }
    
    func showHome(popToRoot: Bool) {
        select(tab: .home, popToRoot: popToRoot)
        if let rootViewController = view.window?.rootViewController, rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: true)
        }
    }
    
    func showImportWalletVersion() {
        select(tab: .settings, popToRoot: false)
        settingsNavigationController.pushViewController(WalletVersionsVC(), animated: true)
    }
    
    func showTemporaryViewAccount(accountId: String) {
        select(tab: .home, popToRoot: false)
        sidebarViewController.focusTemporaryAccount(accountId)
        
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
            return splitHomeVC.splitHomeAccountContext.account.isTemporaryView
        }
        guard hasTemporaryHomeInStack else { return }
        homeNavigationController.popToRootViewController(animated: animated)
    }
    
    func showAssets(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
        let nc = currentNavigationController
        if collectionsFilter != .none, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
            nc.pushViewController(NftsVC(accountSource: accountSource, mode: .fullScreenFiltered, filter: collectionsFilter), animated: true)
            return
        }
        let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTabIndex: index)
        nc.pushViewController(assetsVC, animated: true)
        if collectionsFilter != .none {
            nc.pushViewController(NftsVC(accountSource: accountSource, mode: .fullScreenFiltered, filter: collectionsFilter), animated: false)
        }
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
        case .explore:
            exploreNavigationController
        case .settings:
            settingsNavigationController
        }
    }
}

import UIKit
import UIHome
import UISettings
import UIAssets
import UIComponents
import WalletCore
import WalletContext
import UICreateWallet

@MainActor
protocol RootContainerRouting {
    func isHomeRootSelected() -> Bool
    func pushOnHome(_ viewController: UIViewController) -> Bool
    func showAddWallet(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool)
    func showAssets(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter)
    func showExplore()
    func showHome(popToRoot: Bool)
    func showImportWalletVersion()
    func showTemporaryViewAccount(accountId: String)
}

@MainActor
struct TabRootContainerRouter: RootContainerRouting {
    private var tabVC: HomeTabBarController? {
        for window in UIApplication.shared.sceneWindows {
            if let tabVC = window.rootViewController?.descendantViewController(of: HomeTabBarController.self) {
                return tabVC
            }
        }
        return nil
    }
    
    func isHomeRootSelected() -> Bool {
        guard let nav = tabVC?.selectedViewController as? UINavigationController else {
            return false
        }
        return nav.viewControllers.first is HomeVC
    }
    
    func pushOnHome(_ viewController: UIViewController) -> Bool {
        guard let nav = tabVC?.selectedViewController as? UINavigationController,
              nav.viewControllers.first is HomeVC else {
            return false
        }
        nav.pushViewController(viewController, animated: true)
        return true
    }

    func showAddWallet(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool) {
        presentAddWalletModally(
            network: network,
            showCreateWallet: showCreateWallet,
            showSwitchToOtherVersion: showSwitchToOtherVersion
        )
    }
    
    func showAssets(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
        presentAssetsModally(accountSource: accountSource, selectedTab: index, collectionsFilter: collectionsFilter)
    }
    
    func showExplore() {
        tabVC?.switchToExplore()
    }
    
    func showHome(popToRoot: Bool) {
        tabVC?.switchToHome(popToRoot: popToRoot)
    }
    
    func showImportWalletVersion() {
        let settingsVC = tabVC?.viewControllers?
            .compactMap { $0 as? UINavigationController }
            .first { nc in nc.viewControllers.first is SettingsVC }
        settingsVC?.pushViewController(WalletVersionsVC(), animated: true)
    }
    
    func showTemporaryViewAccount(accountId: String) {
        tabVC?.switchToHome(popToRoot: false)
        tabVC?.homeVC?.navigationController?.pushViewController(HomeVC(accountSource: .accountId(accountId)), animated: true)
    }
}

@MainActor
struct SplitRootContainerRouter: RootContainerRouting {
    var isAvailable: Bool {
        splitVC != nil
    }
    
    private var splitVC: SplitRootViewController? {
        for window in UIApplication.shared.sceneWindows {
            if let splitVC = window.rootViewController?.descendantViewController(of: SplitRootViewController.self) {
                return splitVC
            }
        }
        return nil
    }
    
    func isHomeRootSelected() -> Bool {
        splitVC?.isHomeRootSelected() == true
    }
    
    func pushOnHome(_ viewController: UIViewController) -> Bool {
        splitVC?.pushOnHome(viewController) == true
    }

    func showAddWallet(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool) {
        let vc = AccountTypePickerVC(
            network: network,
            showCreateWallet: showCreateWallet,
            showSwitchToOtherVersion: showSwitchToOtherVersion,
        )
        let navigationController = WNavigationController(rootViewController: vc)
        navigationController.modalPresentationStyle = .formSheet
        topViewController()?.present(navigationController, animated: true)
    }
    
    func showAssets(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
        guard let splitVC, !splitVC.isCollapsed else {
            presentAssetsModally(accountSource: accountSource, selectedTab: index, collectionsFilter: collectionsFilter)
            return
        }
        splitVC.showAssets(accountSource: accountSource, selectedTab: index, collectionsFilter: collectionsFilter)
    }
    
    func showExplore() {
        splitVC?.showExplore()
    }
    
    func showHome(popToRoot: Bool) {
        splitVC?.showHome(popToRoot: popToRoot)
    }
    
    func showImportWalletVersion() {
        splitVC?.showImportWalletVersion()
    }
    
    func showTemporaryViewAccount(accountId: String) {
        splitVC?.showTemporaryViewAccount(accountId: accountId)
    }
}

@MainActor
private func presentAddWalletModally(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool) {
    let vc = AccountTypePickerVC(
        network: network,
        showCreateWallet: showCreateWallet,
        showSwitchToOtherVersion: showSwitchToOtherVersion
    )
    let navigationController = WNavigationController(rootViewController: vc)
    topViewController()?.present(navigationController, animated: true)
}

@MainActor
private func presentAssetsModally(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
    let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTabIndex: index)
    let topVC = topViewController()
    if collectionsFilter != .none, let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
        nc.pushViewController(NftsVC(accountSource: accountSource, mode: .fullScreenFiltered, filter: collectionsFilter), animated: true)
    } else if collectionsFilter != .none {
        let nc = WNavigationController(rootViewController: assetsVC)
        nc.pushViewController(NftsVC(accountSource: accountSource, mode: .fullScreenFiltered, filter: collectionsFilter), animated: false)
        topVC?.present(nc, animated: true)
        assetsVC.view.layoutIfNeeded()
    } else {
        let nc = WNavigationController(rootViewController: assetsVC)
        topVC?.present(nc, animated: true)
    }
}

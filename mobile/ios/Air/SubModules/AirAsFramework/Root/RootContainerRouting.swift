import UIKit
import UIHome
import UIAssets
import UIComponents
import WalletCore
import WalletContext
import UICreateWallet

@MainActor
protocol RootContainerRouting {
    func isHomeRootSelected() -> Bool
    func pushOnHome(_ viewController: UIViewController) -> Bool
    func showAddWallet(network: ApiNetwork)
    func showAgent()
    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter)
    func showExplore()
    func showHome(popToRoot: Bool)
    func showSettings(path: [UIViewController])
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

    func showAddWallet(network: ApiNetwork) {
        presentAddWalletModally(network: network)
    }

    func showAgent() {
        tabVC?.switchToAgent()
    }
    
    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
        presentAssetsModally(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
    }
    
    func showExplore() {
        tabVC?.switchToExplore()
    }
    
    func showHome(popToRoot: Bool) {
        tabVC?.switchToHome(popToRoot: popToRoot)
    }
    
    func showSettings(path: [UIViewController]) {
        tabVC?.switchToSettings(path: path)
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

    func showAddWallet(network: ApiNetwork) {
        let vc = AccountTypePickerVC(network: network)
        let navigationController = WNavigationController(rootViewController: vc)
        navigationController.modalPresentationStyle = .formSheet
        topViewController()?.present(navigationController, animated: true)
    }

    func showAgent() {
        splitVC?.showAgent()
    }
    
    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
        guard let splitVC, !splitVC.isCollapsed else {
            presentAssetsModally(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
            return
        }
        splitVC.showAssets(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
    }
    
    func showExplore() {
        splitVC?.showExplore()
    }
    
    func showHome(popToRoot: Bool) {
        splitVC?.showHome(popToRoot: popToRoot)
    }
    
    func showSettings(path: [UIViewController]) {
        splitVC?.showSettings(path: path)
    }
    
    func showTemporaryViewAccount(accountId: String) {
        splitVC?.showTemporaryViewAccount(accountId: accountId)
    }
}

@MainActor
private func presentAddWalletModally(network: ApiNetwork) {
    let vc = AccountTypePickerVC(network: network)
    let navigationController = WNavigationController(rootViewController: vc)
    topViewController()?.present(navigationController, animated: true)
}

@MainActor
private func presentAssetsModally(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
    let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTab: selectedTab)
    let topVC = topViewController()
    if collectionsFilter != .none, let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
        nc.pushViewController(NftsFullScreenVC(accountSource: accountSource, filter: collectionsFilter), animated: true)
    } else if collectionsFilter != .none {
        let nc = WNavigationController(rootViewController: assetsVC)
        nc.pushViewController(NftsFullScreenVC(accountSource: accountSource, filter: collectionsFilter), animated: false)
        topVC?.present(nc, animated: true)
        assetsVC.view.layoutIfNeeded()
    } else {
        let nc = WNavigationController(rootViewController: assetsVC)
        topVC?.present(nc, animated: true)
    }
}

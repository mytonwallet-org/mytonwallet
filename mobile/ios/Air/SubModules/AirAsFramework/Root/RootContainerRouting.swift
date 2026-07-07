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

extension RootContainerRouting {
    @MainActor
    func showTab(_ id: AppTabId, popToRoot: Bool = false) {
        guard AppTabManager.shared.contains(id) else {
            presentTabModally(id, path: [])
            return
        }
        if let tabVC = findActiveViewController(of: HomeTabBarController.self) {
            tabVC.selectTab(id, popToRoot: popToRoot)
        } else if let splitVC = findActiveViewController(of: SplitRootViewController.self) {
            splitVC.select(tab: id, popToRoot: popToRoot)
        }
    }

    @MainActor
    private func presentTabModally(_ id: AppTabId, path: [UIViewController]) {
        guard let nc = AppTabManager.shared.makeNavigationController(for: id, layout: .tab) else { return }
        if !path.isEmpty, let root = nc.viewControllers.first {
            nc.setViewControllers([root] + path, animated: false)
        }
        nc.modalPresentationStyle = .fullScreen
        topViewController()?.present(nc, animated: true)
    }
}


@MainActor
struct TabRootContainerRouter: RootContainerRouting {
    private var tabVC: HomeTabBarController? {
        findActiveViewController()
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
        showTab(.agent)
    }

    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
        presentAssetsModally(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
    }

    func showExplore() {
        showTab(.explore)
    }

    func showHome(popToRoot: Bool) {
        tabVC?.switchToHome(popToRoot: popToRoot)
    }

    func showSettings(path: [UIViewController]) {
        if AppTabManager.shared.contains(.settings) {
            tabVC?.switchToSettings(path: path)
        } else {
            guard let nc = AppTabManager.shared.makeNavigationController(for: .settings, layout: .tab) else { return }
            if !path.isEmpty, let root = nc.viewControllers.first {
                nc.setViewControllers([root] + path, animated: false)
            }
            nc.modalPresentationStyle = .fullScreen
            topViewController()?.present(nc, animated: true)
        }
    }

    func showTemporaryViewAccount(accountId: String) {
        if let rootVC = tabVC?.view.window?.rootViewController, rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
        showTab(.wallet)
        tabVC?.homeVC?.navigationController?.pushViewController(HomeVC(accountSource: .accountId(accountId)), animated: true)
    }
}

@MainActor
struct SplitRootContainerRouter: RootContainerRouting {
    var isAvailable: Bool {
        splitVC != nil
    }

    private var splitVC: SplitRootViewController? {
        findActiveViewController()
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
        showTab(.agent)
    }

    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
        guard let splitVC, !splitVC.isCollapsed else {
            presentAssetsModally(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
            return
        }
        splitVC.showAssets(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
    }

    func showExplore() {
        showTab(.explore)
    }

    func showHome(popToRoot: Bool) {
        if AppTabManager.shared.contains(.wallet) {
            splitVC?.showHome(popToRoot: popToRoot)
        } else {
            showTab(.wallet, popToRoot: popToRoot)
        }
    }

    func showSettings(path: [UIViewController]) {
        if AppTabManager.shared.contains(.settings) {
            splitVC?.showSettings(path: path)
        } else {
            guard let nc = AppTabManager.shared.makeNavigationController(for: .settings, layout: .split) else { return }
            if !path.isEmpty, let root = nc.viewControllers.first {
                nc.setViewControllers([root] + path, animated: false)
            }
            nc.modalPresentationStyle = .fullScreen
            topViewController()?.present(nc, animated: true)
        }
    }

    func showTemporaryViewAccount(accountId: String) {
        splitVC?.showTemporaryViewAccount(accountId: accountId)
    }
}

@MainActor
private func findActiveViewController<T: UIViewController>(of type: T.Type = T.self) -> T? {
    for window in UIApplication.shared.sceneWindows {
        if let vc = window.rootViewController?.descendantViewController(of: type) {
            return vc
        }
    }
    return nil
}

@MainActor
private func presentAddWalletModally(network: ApiNetwork) {
    let vc = AccountTypePickerVC(network: network)
    let navigationController = WNavigationController(rootViewController: vc)
    topViewController()?.present(navigationController, animated: true)
}

@MainActor
private func presentAssetsModally(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
    let topVC = topViewController()
    if let nc = topVC as? WNavigationController, nc.showExistingAssetsTab(accountSource: accountSource, selectedTab: selectedTab, animated: true) {
        return
    }

    let shouldPushCollection = shouldPushNftCollectionFullscreen(
        accountSource: accountSource,
        selectedTab: selectedTab,
        collectionsFilter: collectionsFilter
    )

    if shouldPushCollection, let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
        nc.pushViewController(NftsFullScreenVC(accountSource: accountSource, filter: collectionsFilter), animated: true)
    } else if shouldPushCollection {
        let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTab: selectedTab)
        let nc = WNavigationController(rootViewController: assetsVC)
        nc.pushViewController(NftsFullScreenVC(accountSource: accountSource, filter: collectionsFilter), animated: false)
        topVC?.present(nc, animated: true)
        assetsVC.view.layoutIfNeeded()
    } else {
        let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTab: selectedTab)
        let nc = WNavigationController(rootViewController: assetsVC)
        topVC?.present(nc, animated: true)
    }
}

@MainActor
func shouldPushNftCollectionFullscreen(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) -> Bool {
    guard collectionsFilter != .none else { return false }
    guard case .nftCollectionFilter = selectedTab else { return true }
    return !AssetsTabVC.canShow(accountSource: accountSource, tab: selectedTab)
}

extension WNavigationController {
    @MainActor
    @discardableResult
    func showExistingAssetsTab(accountSource: AccountSource, selectedTab: DisplayAssetTab, animated: Bool) -> Bool {
        guard let assetsVC = viewControllers.compactMap({ $0 as? AssetsTabVC }).last,
              assetsVC.show(accountSource: accountSource, tab: selectedTab, animated: animated) else {
            return false
        }
        if topViewController !== assetsVC {
            popToViewController(assetsVC, animated: animated)
        }
        return true
    }
}

import UIKit
import UIAgent
import UIHome
import UIAssets
import UIComponents
import UISettings
import WalletCore
import WalletContext
import UICreateWallet

@MainActor
protocol RootContainerRouting {
    func isHomeRootSelected() -> Bool
    func pushOnHome(_ viewController: UIViewController) -> Bool
    func showAddWallet(network: ApiNetwork)
    func showAgent()
    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter, initialPosition: AssetListInitialPosition?)
    func showExplore()
    func showHome(popToRoot: Bool)
    func showImportWalletVersion()
    func showSettings(path: [UIViewController])
    func showTemporaryViewAccount(accountId: String)
}

extension RootContainerRouting {
    @MainActor
    func showTab(_ id: AppTabId, popToRoot: Bool = false) {
        if let topTabsVC = findActiveViewController(of: TopTabsRootViewController.self),
           topTabsVC.selectTab(id, popToRoot: popToRoot) {
            return
        }
        guard AppTabManager.shared.contains(id) else {
            presentTabModally(id, path: [])
            return
        }
        if let splitVC = findActiveViewController(of: SplitRootViewController.self) {
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
struct TopTabsRootContainerRouter: RootContainerRouting {
    private var topTabsVC: TopTabsRootViewController? {
        findActiveViewController()
    }

    func isHomeRootSelected() -> Bool {
        topTabsVC?.isHomeRootSelected == true
    }

    func pushOnHome(_ viewController: UIViewController) -> Bool {
        guard let topTabsVC,
              topTabsVC.currentTabId == .wallet,
              let navigationController = topTabsVC.homeVC.navigationController else {
            return false
        }
        navigationController.pushViewController(viewController, animated: true)
        return true
    }

    func showAddWallet(network: ApiNetwork) {
        presentAddWalletModally(network: network)
    }

    func showAgent() {
        topTabsVC?.navigationController?.pushViewController(
            AgentEntryPoint.makeRootViewController(),
            animated: true
        )
    }

    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter, initialPosition: AssetListInitialPosition?) {
        let navigationController = (topWViewController()?.navigationController as? WNavigationController)
            ?? (topTabsVC?.navigationController as? WNavigationController)
        navigationController?.showAssets(
            accountSource: accountSource,
            selectedTab: selectedTab,
            collectionsFilter: collectionsFilter,
            initialPosition: initialPosition
        )
    }

    func showExplore() {
        showTab(.explore)
    }

    func showHome(popToRoot: Bool) {
        topTabsVC?.switchToHome(popToRoot: popToRoot)
    }

    func showImportWalletVersion() {
        showSettings(path: [WalletVersionsVC()])
    }

    func showSettings(path: [UIViewController]) {
        topTabsVC?.switchToSettings(path: path)
    }

    func showTemporaryViewAccount(accountId: String) {
        let viewController = HomeVC(
            accountSource: .accountId(accountId),
            rootNavigationStyle: .topTabsNavigationBar,
            showsActionsRow: WalletActionButtonsSettings.showsActionButtonsRow
        )
        if topTabsVC?.pushFromSearch(viewController) == true { return }
        if let rootVC = topTabsVC?.view.window?.rootViewController, rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
        showTab(.wallet)
        topTabsVC?.homeVC.navigationController?.pushViewController(
            viewController,
            animated: true
        )
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

    func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter, initialPosition: AssetListInitialPosition?) {
        splitVC?.showAssets(
            accountSource: accountSource,
            selectedTab: selectedTab,
            collectionsFilter: collectionsFilter,
            initialPosition: initialPosition
        )
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

    func showImportWalletVersion() {
        showSettings(path: [WalletVersionsVC()])
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
func shouldPushNftCollectionFullscreen(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) -> Bool {
    guard collectionsFilter != .none else { return false }
    guard case .nftCollectionFilter = selectedTab else { return true }
    return !AssetsTabVC.canShow(accountSource: accountSource, tab: selectedTab)
}

extension WNavigationController {
    @MainActor
    func showAssets(
        accountSource: AccountSource,
        selectedTab: DisplayAssetTab,
        collectionsFilter: NftCollectionFilter,
        initialPosition: AssetListInitialPosition?
    ) {
        if showExistingAssetsTab(
            accountSource: accountSource,
            selectedTab: selectedTab,
            initialPosition: initialPosition,
            animated: true
        ) {
            return
        }

        let shouldPushCollection = shouldPushNftCollectionFullscreen(
            accountSource: accountSource,
            selectedTab: selectedTab,
            collectionsFilter: collectionsFilter
        )
        if shouldPushCollection, (visibleViewController is AssetsTabVC || visibleViewController is NftDetailsVC) {
            pushViewController(
                NftsFullScreenVC(
                    accountSource: accountSource,
                    filter: collectionsFilter,
                    initialNftID: initialPosition?.nftID
                ),
                animated: true
            )
            return
        }

        let assetsVC = AssetsTabVC(
            accountSource: accountSource,
            defaultTab: selectedTab,
            initialPosition: initialPosition
        )
        if shouldPushCollection {
            let collectionVC = NftsFullScreenVC(
                accountSource: accountSource,
                filter: collectionsFilter,
                initialNftID: initialPosition?.nftID
            )
            setViewControllers(viewControllers + [assetsVC, collectionVC], animated: true)
        } else {
            pushViewController(assetsVC, animated: true)
        }
    }

    @MainActor
    @discardableResult
    func showExistingAssetsTab(
        accountSource: AccountSource,
        selectedTab: DisplayAssetTab,
        initialPosition: AssetListInitialPosition? = nil,
        animated: Bool
    ) -> Bool {
        guard let assetsVC = viewControllers.compactMap({ $0 as? AssetsTabVC }).last,
              assetsVC.show(
                accountSource: accountSource,
                tab: selectedTab,
                initialPosition: initialPosition,
                animated: animated
              ) else {
            return false
        }
        if topViewController !== assetsVC {
            popToViewController(assetsVC, animated: animated)
        }
        return true
    }
}


import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import UICreateWallet
import UIHome
import UISwap
import UITransaction
import UIQRScan
import UISend
import UIAssets
import UISettings
import UIReceive
import UIEarn
import UIToken
import UIInAppBrowser
import UniformTypeIdentifiers

@MainActor func configureAppActions() {
    AppActions = AppActionsImpl.self
}

private class AppActionsImpl: AppActionsProtocol {
    static func copyString(_ string: String?, toastMessage: String) {
        if let string {
            UIPasteboard.general.setItems([[
                    UTType.plainText.identifier: string
                ]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date(timeIntervalSinceNow: 180.0),
                ]
            )
            topWViewController()?.showToast(animationName: "Copy", message: toastMessage)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
    
    static func lockApp(animated: Bool) {
        let windows = UIApplication.shared.sceneWindows
        let tabVC = windows.compactMap { $0.rootViewController as? HomeTabBarController }.first
        if let tabVC {
            tabVC._showLock(animated: animated)
        }
    }
    
    static func openInBrowser(_ url: URL, title: String?, injectTonConnect: Bool) {
        InAppBrowserSupport.shared.openInBrowser(url, title: title, injectTonConnect: injectTonConnect)
    }
    
    static func pushTransactionSuccess(activity: ApiActivity) {
        let vc = ActivityVC(activity: activity)
        if let nc = topWViewController()?.navigationController {
            nc.pushViewController(vc, animated: true, completion: {
                nc.viewControllers = [vc]
                if let sheet = nc.sheetPresentationController {
                    sheet.animateChanges {
                        sheet.selectedDetentIdentifier = .init("mid")
                    }
                }
            })
        }
    }
    
    static func repeatActivity(_ activity: ApiActivity) {
        if AccountStore.account?.supportsSend != true {
            topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("Read-only account"), nil))
            return
        }
        let vc: UIViewController? = if case .transaction(let transaction) = activity, !transaction.isIncoming {
            if transaction.isStaking {
                EarnRootVC(token: TokenStore.tokens[transaction.slug])
            } else {
                SendVC(prefilledValues: .init(
                    address: transaction.toAddress,
                    amount: transaction.amount == 0 ? nil : abs(transaction.amount),
                    token: transaction.slug,
                    commentOrMemo: transaction.comment
                ))
            }
        } else if case .swap(let swap) = activity {
            SwapVC(defaultSellingToken: swap.from, defaultBuyingToken: swap.to, defaultSellingAmount: swap.fromAmount.value)
        } else { nil }
        if let vc {
            topWViewController()?.presentingViewController?.dismiss(animated: true, completion: {
                topViewController()?.present(vc, animated: true)
            })
        }
    }
    
    static func scanQR() {
        let qrScanVC = QRScanVC(callback: { result in
            switch result {
            case .url(let url):
                let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: url) ?? false
                if !deeplinkHandled {
                    topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("This QR Code is not supported"), nil))
                }
                
            case .address(address: let addr, possibleChains: let chains):
                AppActions.showSend(prefilledValues: .init(
                    address: addr,
                    token: chains.first?.tokenSlug
                ))
                
            @unknown default:
                break
            }
        })
        topViewController()?.present(WNavigationController(rootViewController: qrScanVC), animated: true)
    }
    
    static func setSensitiveDataIsHidden(_ newValue: Bool) {
        AppStorageHelper.isSensitiveDataHidden = newValue
        let window = UIApplication.shared.sceneKeyWindow
        window?.updateSensitiveData()
    }
    
    static func shareUrl(_ url: URL) {
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        topViewController()?.present(activityViewController, animated: true)
    }
    
    static func showActivityDetails(accountId: String, activity: ApiActivity) {
        Task {
            let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: activity.id)
            let vc = ActivityVC(activity: updatedActivity ?? activity)
            topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
        }
    }
    
    static func showAddWallet(showCreateWallet: Bool, showSwitchToOtherVersion: Bool) {
        let vc = AccountTypePickerVC(showCreateWallet: showCreateWallet, showSwitchToOtherVersion: showSwitchToOtherVersion)
        topViewController()?.present(vc, animated: true)
    }
    
    static func showAssets(selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
        let assetsVC = AssetsTabVC(defaultTabIndex: index)
        let topVC = topViewController()
        if collectionsFilter != .none, let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
            nc.pushViewController(NftsVC(compactMode: false, filter: collectionsFilter), animated: true)
        } else if collectionsFilter != .none {
            let nc = WNavigationController()
            nc.viewControllers = [assetsVC, NftsVC(compactMode: false, filter: collectionsFilter)]
            topVC?.present(nc, animated: true)
        } else {
            let nc = WNavigationController(rootViewController: assetsVC)
            topVC?.present(nc, animated: true)
        }
    }
    
    static func showBuyWithCard(chain: ApiChain?, push: Bool?) {
        if AccountStore.account?.network != .mainnet {
            topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("Buying with card is not supported in Testnet."), nil))
        }
        let buyWithCardVC = BuyWithCardVC(chain: chain ?? .ton)
        pushIfNeeded(buyWithCardVC, push: push)
    }
    
    static func showConnectedDapps(push: Bool) {
        let vc = ConnectedAppsVC(isModal: !push)
        pushIfNeeded(vc, push: push)
    }
    
    static func showCrossChainSwapVC(_ transaction: WalletCore.ApiActivity) {
        let vc = CrossChainSwapVC(transaction: transaction)
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }
    
    static func showEarn(token: ApiToken?) {
        if AccountStore.account?.supportsEarn != true {
            topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("Staking is not supported in Testnet."), nil))
            return
        }
        let earnVC = EarnRootVC(token: token)
        topViewController()?.present(WNavigationController(rootViewController: earnVC), animated: true)
    }
    
    static func showError(error: Error?) {
        if let error {
            topViewController()?.showAlert(error: error)
        }
    }
    
    static func showHiddenNfts() {
        let hiddenVC = HiddenNftsVC()
        let topVC = topViewController()
        if let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC || nc.visibleViewController is AssetsAndActivityVC) {
            nc.pushViewController(hiddenVC, animated: true)
        } else if let vc = topWViewController() as? AssetsAndActivityVC {
            vc.navigationController?.pushViewController(hiddenVC, animated: true)
        } else {
            let assetsVC = AssetsTabVC(defaultTabIndex: 1)
            let nc = WNavigationController()
            nc.viewControllers = [assetsVC, hiddenVC]
            topVC?.present(nc, animated: true)
        }
    }
    
    static func showImportWalletVersion() -> () {
        let windows = UIApplication.shared.sceneWindows
        let tabVC = windows.compactMap { $0.rootViewController as? HomeTabBarController }.first
        let settingsVC = tabVC?.viewControllers?
            .compactMap { $0 as? UINavigationController}
            .first { nc in nc.viewControllers.first is SettingsVC }
        if let settingsVC {
            settingsVC.pushViewController(WalletVersionsVC(), animated: true)
        }
    }
    
    static func showReceive(chain: ApiChain?, showBuyOptions: Bool?, title: String?) {
        let receiveVC = ReceiveVC(chain: chain, showBuyOptions: showBuyOptions ?? true, title: title)
        topViewController()?.present(WNavigationController(rootViewController: receiveVC), animated: true)
    }
    
    static func showSend(prefilledValues: SendPrefilledValues?) {
        if AccountStore.account?.supportsSend != true {
            topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("Read-only account"), nil))
            return
        }
        topViewController()?.present(SendVC(prefilledValues: prefilledValues), animated: true)
    }
    
    static func showSwap(defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?) {
        if AccountStore.account?.supportsSwap != true {
            topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("Swap is not supported on this account."), nil))
            return
        }
        let swapVC = SwapVC(defaultSellingToken: defaultSellingToken, defaultBuyingToken: defaultBuyingToken, defaultSellingAmount: defaultSellingAmount)
        pushIfNeeded(swapVC, push: push)
    }
    
    static func showToken(token: ApiToken, isInModal: Bool) {
        guard let accountId = AccountStore.accountId else { return }
        Task {
            let tokenVC: TokenVC = await TokenVC(accountId: accountId, token: token, isInModal: isInModal)
            topWViewController()?.navigationController?.pushViewController(tokenVC, animated: true)
        }
    }
    
    static func showUpgradeCard() {
        AppActions.openInBrowser(URL(string:  "https://getgems.io/collection/EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM")!, title: "MyTonWallet NFT Cards", injectTonConnect: true)
    }
    
    static func transitionToNewRootViewController(_ newRootViewController: UIViewController, animationDuration: Double?) {
        if let window = topViewController()?.view.window {
            if let animationDuration {
                UIView.transition(with: window, duration: animationDuration , options: [.transitionCrossDissolve]) {
                    window.rootViewController = newRootViewController
                }
            } else {
                window.rootViewController = newRootViewController
            }
        }
    }
}

// MARK: - Helpers

@MainActor private func pushIfNeeded(_ vc: UIViewController, push: Bool?) {
    if push == true, let nc = topWViewController()?.navigationController {
        nc.pushViewController(vc, animated: true)
    } else {
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }
}


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
import Dependencies

@MainActor func configureAppActions() {
    AppActions = AppActionsImpl.self
}

@MainActor
private class AppActionsImpl: AppActionsProtocol {
    
    @Dependency(\.sensitiveData) private static var sensitiveData
    
    static var tabVC: HomeTabBarController? {
        let windows = UIApplication.shared.sceneWindows
        return windows.compactMap { $0.rootViewController as? HomeTabBarController }.first
    }
    
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
            Haptics.play(.lightTap)
        }
    }
    
    static func saveTemporaryViewAccount(accountId: String) {
        Task {
            do {
                try await AccountStore.saveTemporaryViewAccount(accountId: accountId)
                topWViewController()?.showToast(message: lang("Account saved successfully!"))
                Haptics.play(.success)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    static func lockApp(animated: Bool) {
        if let tabVC {
            tabVC._showLock(animated: animated)
        }
    }
    
    static func openInBrowser(_ url: URL, title: String?, injectTonConnect: Bool) {
        InAppBrowserSupport.shared.openInBrowser(url, title: title, injectTonConnect: injectTonConnect)
    }
    
    static func openTipsChannel() {
        let channel = Language.current == .ru ? MTW_TIPS_CHANNEL_NAME_RU : MTW_TIPS_CHANNEL_NAME
        UIApplication.shared.open(URL(string: "https://t.me/\(channel)")!)
    }
    
    static func pushTransactionSuccess(activity: ApiActivity) {
        let vc = ActivityVC(activity: activity, accountId: nil)
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
        var vc: UIViewController?
        switch activity {
        case .transaction(let transaction):
            if transaction.isStaking {
                vc = EarnRootVC(tokenSlug: transaction.slug)
            } else if transaction.type == nil && transaction.nft == nil && !transaction.isIncoming {
                vc = SendVC(prefilledValues: .init(
                    address: transaction.toAddress,
                    amount: transaction.amount == 0 ? nil : abs(transaction.amount),
                    token: transaction.slug,
                    commentOrMemo: transaction.comment
                ))
            }
        case .swap(let swap):
            vc = SwapVC(defaultSellingToken: swap.from, defaultBuyingToken: swap.to, defaultSellingAmount: swap.fromAmount.value)
        }
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
            }
        })
        topViewController()?.present(WNavigationController(rootViewController: qrScanVC), animated: true)
    }
    
    static func setSensitiveDataIsHidden(_ newValue: Bool) {
        sensitiveData.isHidden = newValue
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
            let vc = ActivityVC(activity: updatedActivity ?? activity, accountId: accountId)
            topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
        }
    }
    
    static func showActivityDetailsById(chain: ApiChain, txId: String) {
        Task {
            do {
                let walletAddress = AccountStore.account?.addressByChain[chain.rawValue] ?? ""
                let activities = try await Api.fetchTransactionById(chain: chain, network: .mainnet, txHash: txId, walletAddress: walletAddress)
                // only single activities supported right now
                guard activities.count == 1 else { throw DisplayError(text: lang("Transaction not found")) }
                let activity = activities[0]
                showActivityDetails(accountId: AccountStore.currentAccountId, activity: activity)
            } catch {
                showError(error: DisplayError(text: lang("Transaction not found")))
            }
        }
    }
    
    static func showAddToken() {
        let assets = AssetsAndActivityVC()
        _ = assets.view
        let add = TokenSelectionVC(
            showMyAssets: false,
            title: lang("Add Token"),
            delegate: assets,
            isModal: true,
            onlyTonChain: true
        )
        let nc = WNavigationController()
        nc.viewControllers = [assets, add]
        topViewController()?.present(nc, animated: true)
    }
    
    static func showAddWallet(showCreateWallet: Bool, showSwitchToOtherVersion: Bool) {
        let vc = AccountTypePickerVC(showCreateWallet: showCreateWallet, showSwitchToOtherVersion: showSwitchToOtherVersion)
        topViewController()?.present(vc, animated: true)
    }
    
    static func showAssets(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
        let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTabIndex: index)
        let topVC = topViewController()
        if collectionsFilter != .none, let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC) {
            nc.pushViewController(NftsVC(accountSource: accountSource, compactMode: false, filter: collectionsFilter), animated: true)
        } else if collectionsFilter != .none {
            let nc = WNavigationController()
            nc.viewControllers = [assetsVC, NftsVC(accountSource: accountSource, compactMode: false, filter: collectionsFilter)]
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
    
    static func showCrossChainSwapVC(_ transaction: WalletCore.ApiActivity, accountId: String?) {
        if let swap = transaction.swap {
            let vc = CrossChainSwapVC(swap: swap, accountId: accountId)
            topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
        }
    }
    
    static func showCustomizeWallet(accountId: String?) {
        let vc = CustomizeWalletVC(accountId: accountId)
        if let settingsVC = topWViewController() as? AppearanceSettingsVC, let nc = settingsVC.navigationController {
            nc.pushViewController(vc, animated: true)
        } else {
            let nc = WNavigationController(rootViewController: vc)
            topViewController()?.present(nc, animated: true)
        }
    }
    
    static func showDeleteAccount(accountId: String) {
        if let account = AccountStore.accountsById[accountId] {
            showDeleteAccountAlert(accountToDelete: account, isCurrentAccount: AccountStore.accountId == account.id)
        }
    }
    
    static func showEarn(tokenSlug: String?) {
        let earnVC = EarnRootVC(tokenSlug: tokenSlug)
        topViewController()?.present(WNavigationController(rootViewController: earnVC), animated: true)
    }
    
    static func showError(error: Error?) {
        if let error {
            topViewController()?.showAlert(error: error)
        }
    }
    
    static func showExplore() {
        tabVC?.switchToExplore()
    }
    
    static func showHiddenNfts(accountSource: AccountSource) {
        let hiddenVC = HiddenNftsVC()
        let topVC = topViewController()
        if let nc = topVC as? WNavigationController, (nc.visibleViewController is AssetsTabVC || nc.visibleViewController is NftDetailsVC || nc.visibleViewController is AssetsAndActivityVC) {
            nc.pushViewController(hiddenVC, animated: true)
        } else if let vc = topWViewController() as? AssetsAndActivityVC {
            vc.navigationController?.pushViewController(hiddenVC, animated: true)
        } else {
            let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTabIndex: 1)
            let nc = WNavigationController()
            nc.viewControllers = [assetsVC, hiddenVC]
            topVC?.present(nc, animated: true)
        }
    }
    
    static func showHome(popToRoot: Bool) {
        tabVC?.switchToHome(popToRoot: popToRoot)
    }

    static func showImportWalletVersion() -> () {
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
    
    static func showRenameAccount(accountId: String) {
        if let account = AccountStore.accountsById[accountId] {
            let alert = makeRenameAccountAlertController(account: account)
            topViewController()?.present(alert, animated: true)
        }
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
    
    static func showTemporaryViewAccount(addressOrDomainByChain: [String: String]) {
        Task { @MainActor in
            do {
                if addressOrDomainByChain.isEmpty {
                    throw DisplayError(text: lang("$no_valid_view_addresses"))
                }
                // TODO: Show loading indicator
                let account = try await AccountStore.importTemporaryViewAccountOrActivateFirstMatching(network: .mainnet, addressOrDomainByChain: addressOrDomainByChain)
                tabVC?.switchToHome(popToRoot: false)
                tabVC?.homeVC?.navigationController?.pushViewController(HomeVC(accountId: account.id), animated: true)
                
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    static func showToken(token: ApiToken, isInModal: Bool) {
        guard let accountId = AccountStore.accountId else { return }
        Task {
            let tokenVC: TokenVC = await TokenVC(accountId: accountId, token: token, isInModal: isInModal)
            topWViewController()?.navigationController?.pushViewController(tokenVC, animated: true)
        }
    }

    static func showTokenByAddress(chain: String, tokenAddress: String) {
        guard let accountId = AccountStore.accountId else { return }
        guard let apiChain = ApiChain(rawValue: chain) else { return }

        Task {
            do {
                let slug = try await Api.buildTokenSlug(chain: apiChain, tokenAddress: tokenAddress)
                guard let token = TokenStore.getToken(slug: slug) else {
                    await MainActor.run {
                        topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("$unknown_token_address"), nil))
                    }
                    return
                }
                await MainActor.run {
                    presentOrPushToken(accountId: accountId, token: token)
                }
            } catch {
                await MainActor.run {
                    topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("$unknown_token_address"), nil))
                }
            }
        }
    }

    static func showTokenBySlug(_ slug: String) {
        guard let accountId = AccountStore.accountId else { return }
        guard let token = TokenStore.getToken(slug: slug) else {
            topViewController()?.showAlert(error: BridgeCallError.customMessage(lang("$unknown_token_address"), nil))
            return
        }
        presentOrPushToken(accountId: accountId, token: token)
    }

    private static func presentOrPushToken(accountId: String, token: ApiToken) {
        Task {
            let tokenVC: TokenVC = await TokenVC(accountId: accountId,
                                                 token: token,
                                                 isInModal: tabVC?.selectedViewController?.children.first is HomeVC != true)
            if let nav = (topViewController() as? HomeTabBarController)?.selectedViewController as? UINavigationController,
               nav.viewControllers.first is HomeVC {
                nav.pushViewController(tokenVC, animated: true)
            } else {
                topViewController()?.present(WNavigationController(rootViewController: tokenVC), animated: true)
            }
        }
    }
    
    static func showUpgradeCard() {
        AppActions.openInBrowser(URL(string:  "https://getgems.io/collection/EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM")!, title: "MyTonWallet NFT Cards", injectTonConnect: true)
    }
    
    static func showWalletSettings() {
        let vc = WalletSettingsVC()
        let nc = WNavigationController(rootViewController: vc)
        topViewController()?.present(nc, animated: true)
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

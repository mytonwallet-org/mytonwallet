
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
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
    _ = RootStateCoordinator.shared
}

private let log = Log("AppActions")

@MainActor
private class AppActionsImpl: AppActionsProtocol {
    
    @Dependency(\.sensitiveData) private static var sensitiveData
    private static var rootContainerRouter: any RootContainerRouting {
        let splitRouter = SplitRootContainerRouter()
        if splitRouter.isAvailable {
            return splitRouter
        }
        return TabRootContainerRouter()
    }
    
    static var rootContainerVC: RootContainerVC? {
        let windows = UIApplication.shared.sceneWindows
        return windows.compactMap { $0.rootViewController?.descendantViewController(of: RootContainerVC.self) }.first
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
            AppActions.showToast(animationName: "Copy", message: toastMessage)
            Haptics.play(.lightTap)
        }
    }
    
    static func saveTemporaryViewAccount(accountId: String) {
        Task {
            do {
                try await AccountStore.saveTemporaryViewAccount(accountId: accountId)
                AppActions.showToast(message: lang("Account Saved"))
                Haptics.play(.success)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    static func lockApp(animated: Bool) {
        guard AuthSupport.accountsSupportAppLock else { return }
        if let rootContainerVC {
            rootContainerVC.showLock(animated: animated, onUnlock: {
                AirLauncher.appUnlocked = true
                WalletContextManager.delegate?.walletIsReady(isReady: true)
            })
            AirLauncher.appUnlocked = false
        }
    }
    
    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool) {
        let url = url.isSubproject ? url.appendingSubprojectContext() : url
        InAppBrowserSupport.shared.openInBrowser(url, title: title, injectDappConnect: injectDappConnect)
    }
    
    static func openTipsChannel() {
        let channel = Language.current == .ru ? MTW_TIPS_CHANNEL_NAME_RU : MTW_TIPS_CHANNEL_NAME
        UIApplication.shared.open(URL(string: "https://t.me/\(channel)")!)
    }
    
    static func repeatActivity(_ activity: ApiActivity) {
        if AccountStore.account?.supportsSend != true {
            AppActions.showError(error: BridgeCallError.customMessage(lang("Read-only account"), nil))
            return
        }
        let action = {
            switch activity {
            case .transaction(let transaction):
                if transaction.isStaking {
                    AppActions.showEarn(tokenSlug: transaction.slug)
                } else if transaction.type == nil && transaction.nft == nil && !transaction.isIncoming {
                    AppActions.showSend(prefilledValues: .init(
                        address: transaction.toAddress,
                        amount: transaction.amount == 0 ? nil : abs(transaction.amount),
                        token: transaction.slug,
                        commentOrMemo: transaction.comment
                    ))
                }
            case .swap(let swap):
                AppActions.showSwap(defaultSellingToken: swap.from, defaultBuyingToken: swap.to, defaultSellingAmount: swap.fromAmount.value, push: nil)
            }
        }
        if let presenting = topWViewController()?.presentingViewController {
            presenting.dismiss(animated: true, completion: action)
        } else {
            action()
        }
    }
    
    static func scanQR() async -> ScanResult? {
        return await withCheckedContinuation { continuation in
            let qrScanVC = QRScanVC(callback: { result in
                continuation.resume(returning: result)
            })
            topViewController()?.present(WNavigationController(rootViewController: qrScanVC), animated: true)
        }
    }
    
    static func setSensitiveDataIsHidden(_ newValue: Bool) {
        sensitiveData.isHidden = newValue
        let window = UIApplication.shared.sceneKeyWindow
        window?.updateSensitiveData()
    }
    
    static func shareUrl(_ url: URL) {
        guard let topVC = topViewController() else { return }
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = topVC.view
        topVC.present(activityViewController, animated: true)
    }
    
    static func showActivityDetails(accountId: String, activity: ApiActivity, context: ActivityDetailsContext) {
        Task {
            let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: activity.id)
            let vc = ActivityVC(activity: updatedActivity ?? activity, accountSource: .accountId(accountId), context: context)
            
            if context.isTransactionConfirmation {
                guard let navigationController = topViewController() as? UINavigationController else { return }
                let coordinator = ContentReplaceAnimationCoordinator(navigationController: navigationController)
                vc.navigationItem.hidesBackButton = true
                coordinator.replaceTop(with: vc) {
                    vc.animateToCollapsed()
                }
            } else if let listVC = topWViewController() as? ActivityDetailsListVC {
                listVC.navigationController?.pushViewController(vc, animated: true)
            } else {
                topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
            }
        }
    }
    
    static func showActivityDetailsById(chain: ApiChain, txId: String, showError: Bool) {
        Task {
            do {
                guard let account = AccountStore.account else { return }
                let walletAddress = account.getAddress(chain: chain) ?? ""
                let activities = try await Api.fetchTransactionById(chain: chain, network: account.network, txId: txId, walletAddress: walletAddress)
                presentActivities(activities, accountId: account.id, showError: showError)
            } catch {
                if showError {
                    AppActions.showError(error: DisplayError(text: lang("Transfer not found")))
                }
            }
        }
    }

    static func showAnyAccountTx(accountId: String, chain: ApiChain, txId: String, showError: Bool) {
        Task {
            do {
                let account = try await AccountStore.activateAccount(accountId: accountId)
                let normalizedTxId = normalizeNotificationTxId(txId)
                let walletAddress = account.getAddress(chain: chain) ?? ""
                let activities = try await Api.fetchTransactionById(
                    chain: chain,
                    network: account.network,
                    txHash: normalizedTxId,
                    walletAddress: walletAddress
                )
                presentActivities(activities, accountId: account.id, showError: showError)
            } catch {
                if showError {
                    AppActions.showError(error: DisplayError(text: lang("Transfer not found")))
                }
            }
        }
    }

    private static func presentActivities(_ activities: [ApiActivity], accountId: String, showError: Bool) {
        switch activities.count {
        case 0:
            if showError {
                AppActions.showError(error: DisplayError(text: lang("Transfer not found")))
            }
        case 1:
            AppActions.showActivityDetails(accountId: accountId, activity: activities[0], context: .external)
        default:
            let vc = ActivityDetailsListVC(accountContext: AccountContext(source: .accountId(accountId)), activities: activities, context: .external)
            let nc = UINavigationController(rootViewController: vc)
            topViewController()?.present(nc, animated: true)
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
            onlySupportedChains: true
        )
        let nc = WNavigationController()
        nc.viewControllers = [assets, add]
        topViewController()?.present(nc, animated: true)
    }
    
    static func showAddWallet(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool) {
        rootContainerRouter.showAddWallet(
            network: network,
            showCreateWallet: showCreateWallet,
            showSwitchToOtherVersion: showSwitchToOtherVersion
        )
    }
    
    static func showAssets(accountSource: AccountSource, selectedTab index: Int, collectionsFilter: NftCollectionFilter) {
        rootContainerRouter.showAssets(accountSource: accountSource, selectedTab: index, collectionsFilter: collectionsFilter)
    }

    static func showAssetsAndActivity() {
        let vc = AssetsAndActivityVC()
        let nc = WNavigationController(rootViewController: vc)
        topViewController()?.present(nc, animated: true)
    }
    
    static func showBuyWithCard(chain: ApiChain?, push: Bool?) {
        guard let account = AccountStore.account else { return }
        guard account.network == .mainnet else {
            AppActions.showError(error: DisplayError(text: lang("Buying with card is not supported in Testnet.")))
            return
        }
        let buyWithCardVC = BuyWithCardVC(chain: chain ?? account.firstChain)
        pushIfNeeded(buyWithCardVC, push: push)
    }
    
    static func showConnectedDapps(push: Bool) {
        let vc = ConnectedAppsVC(isModal: !push)
        pushIfNeeded(vc, push: push)
    }
    
    static func showCrossChainSwapVC(_ transaction: WalletCore.ApiActivity, accountId: String?) {
        if let swap = transaction.swap {
            let vc = CrosschainToWalletVC(swap: swap, accountId: accountId)
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
        rootContainerRouter.showExplore()
    }
    
    static func showExploreSite(siteHost: String) {
        Task { @MainActor in
            do {
                let siteHost = siteHost.lowercased()
                if let subprojectURL = URL(string: "https://\(siteHost)"), subprojectURL.isSubproject {
                    AppActions.openInBrowser(subprojectURL, title: nil, injectDappConnect: true)
                    return
                }
                let result = try await Api.loadExploreSites(langCode: LocalizationSupport.shared.langCode)
                if let site = result.sites.first(where: { $0.siteHost == siteHost }),
                   let url = URL(string: site.url) {
                    if site.shouldOpenExternally {
                        await UIApplication.shared.open(url)
                    } else {
                        AppActions.openInBrowser(url, title: site.name, injectDappConnect: true)
                    }
                } else {
                    AppActions.showExplore()
                }
            } catch {
                AppActions.showExplore()
            }
        }
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
        rootContainerRouter.showHome(popToRoot: popToRoot)
    }

    static func showImportWalletVersion() -> () {
        rootContainerRouter.showImportWalletVersion()
    }

    static func showLinkDomain(accountSource: AccountSource, nftAddress: String) {
        let vc = LinkDomainVC(accountSource: accountSource, nftAddress: nftAddress)
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }

    static func showNftByAddress(_ nftAddress: String) {
        guard let account = AccountStore.account else { return }
        let accountId = account.id
        let network = account.network

        Task {
            do {
                guard let nft = try await Api.fetchNftByAddress(network: network, nftAddress: nftAddress) else {
                    AppActions.showError(error: DisplayError(text: lang("$nft_not_found")))
                    return
                }
                let nftVC = NftDetailsVC(accountId: accountId, nft: nft, listContext: .none, fixedNfts: [nft])
                topViewController()?.present(WNavigationController(rootViewController: nftVC), animated: true)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    static func showReceive(chain: ApiChain?, title: String?) {
        let receiveVC = ReceiveVC(chain: chain, title: title)
        topViewController()?.present(WNavigationController(rootViewController: receiveVC), animated: true)
    }

    static func showRenewDomain(accountSource: AccountSource, nftsToRenew: [String]) {
        let vc = RenewDomainVC(accountSource: accountSource, nftsToRenew: nftsToRenew)
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }
    
    static func showRenameAccount(accountId: String) {
        if let account = AccountStore.accountsById[accountId] {
            let alert = makeRenameAccountAlertController(account: account)
            topViewController()?.present(alert, animated: true)
        }
    }
    
    static func showSaveAddressDialog(accountContext: AccountContext, chain: ApiChain, address: String) {
        let alert = makeSaveAddressAlertController(accountContext: accountContext, chain: chain, address: address)
        topViewController()?.present(alert, animated: true)
    }
    
    static func showSend(prefilledValues: SendPrefilledValues) {
        if AccountStore.account?.supportsSend != true {
            AppActions.showError(error: BridgeCallError.customMessage(lang("Read-only account"), nil))
            return
        }
        topViewController()?.present(SendVC(prefilledValues: prefilledValues), animated: true)
    }
    
    static func showSell(account: MAccount?, tokenSlug: String?) {
        guard let account = account ?? AccountStore.account else { return }
        let tokenSlug = tokenSlug ?? TONCOIN_SLUG
        let vc = SellVC(account: account, tokenSlug: tokenSlug)
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }
    
    static func showSwap(defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?) {
        if AccountStore.account?.supportsSwap != true {
            AppActions.showError(error: BridgeCallError.customMessage(lang("Swap is not supported on this account."), nil))
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
                rootContainerRouter.showTemporaryViewAccount(accountId: account.id)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    static func showToast(animationName: String?, message: String, duration: Double, tapAction: (() -> ())?) {
        topWViewController()?.showToast(animationName: animationName, message: message, duration: duration, tapAction: tapAction)
    }
    
    static func showToken(accountSource: AccountSource, token: ApiToken, isInModal: Bool) {
        Task {
            let tokenVC: TokenVC = await TokenVC(accountSource: accountSource, token: token, isInModal: isInModal)
            topWViewController()?.navigationController?.pushViewController(tokenVC, animated: true)
        }
    }

    static func showTokenByAddress(chain: ApiChain, tokenAddress: String) {
        guard AccountStore.accountId != nil else { return }
        guard chain.isSupported else { return }

        Task {
            do {
                let slug = try await Api.buildTokenSlug(chain: chain, tokenAddress: tokenAddress)
                guard let token = TokenStore.getToken(slug: slug) else {
                    await MainActor.run {
                        AppActions.showError(error: BridgeCallError.customMessage(lang("$unknown_token_address"), nil))
                    }
                    return
                }
                await MainActor.run {
                    presentOrPushToken(accountSource: .current, token: token)
                }
            } catch {
                await MainActor.run {
                    AppActions.showError(error: BridgeCallError.customMessage(lang("$unknown_token_address"), nil))
                }
            }
        }
    }

    static func showTokenBySlug(_ slug: String) {
        guard let token = TokenStore.getToken(slug: slug) else {
            AppActions.showError(error: BridgeCallError.customMessage(lang("$unknown_token_address"), nil))
            return
        }
        presentOrPushToken(accountSource: .current, token: token)
    }

    private static func presentOrPushToken(accountSource: AccountSource, token: ApiToken) {
        Task {
            let tokenVC: TokenVC = await TokenVC(accountSource: accountSource,
                                                 token: token,
                                                 isInModal: !rootContainerRouter.isHomeRootSelected())
            if !rootContainerRouter.pushOnHome(tokenVC) {
                topViewController()?.present(WNavigationController(rootViewController: tokenVC), animated: true)
            }
        }
    }
    
    static func showUpgradeCard() {
        log.info("showUpgradeCard - switchToCapacitor")
        AppActions.openInBrowser(URL(string:  "https://getgems.io/collection/EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM")!, title: "MyTonWallet NFT Cards", injectDappConnect: true)
    }
    
    static func showWalletSettings() {
        let vc = WalletSettingsVC()
        let nc = WNavigationController(rootViewController: vc)
        topViewController()?.present(nc, animated: true)
    }
    
    static func transitionToRootState(_ rootState: AppRootState, animationDuration: Double?) {
        RootStateCoordinator.shared.transition(to: rootState, animationDuration: animationDuration)
    }
}

// MARK: - Subproject Context

private extension URL {
    func appendingSubprojectContext() -> URL {
        let theme = AppStorageHelper.activeNightMode.rawValue
        let lang = LocalizationSupport.shared.langCode
        let baseCurrency = TokenStore.baseCurrency.rawValue

        let addresses = AccountStore.account?.orderedChains
            .map { "\($0.0.rawValue):\($0.1.address)" }
            .joined(separator: ",")

        var params = "theme=\(theme)&lang=\(lang)&baseCurrency=\(baseCurrency)"
        if let addresses, !addresses.isEmpty {
            params += "&addresses=\(addresses)"
        }

        return URL(string: "\(absoluteString)#\(params)") ?? self
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

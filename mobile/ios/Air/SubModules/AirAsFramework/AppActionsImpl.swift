
import Foundation
import UIKit
import SwiftUI
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
import UIHome
import UIToken
import UIInAppBrowser
import UIPortfolio
import UIPasscode
import UniformTypeIdentifiers
import Dependencies

@MainActor func configureAppActions() {
    AppActions = AppActionsImpl.self
    _ = RootStateCoordinator.shared
}

private let log = Log("AppActions")
private let portfolioURL = URL(string: "https://portfolio.mywallet.io/")!

private func isPortfolioHomeURL(_ url: URL) -> Bool {
    url.host == portfolioURL.host && (url.path.isEmpty || url.path == "/")
}

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
            AppActions.showToast(icon: .animatedCopy, message: toastMessage)
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
        AirLauncher.lockApp(animated: animated)
    }
    
    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool, historyTag: String?) {
        let url = url.isSubproject ? url.appendingSubprojectContext() : url
        if isPortfolioHomeURL(url) {
            showPortfolio(accountContext: AccountContext(source: .current))
            return
        }
        InAppBrowserSupport.shared.openInBrowser(url, title: title, injectDappConnect: injectDappConnect, historyTag: historyTag)
    }
    
    static func openTipsChannel() {
        let channel = Language.current == .ru ? MTW_TIPS_CHANNEL_NAME_RU : MTW_TIPS_CHANNEL_NAME
        UIApplication.shared.open(URL(string: "https://t.me/\(channel)")!)
    }

    static func authorizeProtectedAction<HeaderView: View, Result: MfaProtectedActionResult>(
        on viewController: UIViewController,
        account: MAccount,
        title: String,
        headerView: HeaderView,
        passwordAction: @escaping (String) async throws -> Result,
        ledgerSignData: (() async throws -> SignData)?,
        ledgerFromAddress: String?,
        presentationStyle: ProtectedActionPresentationStyle,
        useBioOnPresent: Bool,
        completionBehavior: ProtectedActionCompletionBehavior,
        prefersNavigationTitleWithCustomHeader: Bool,
        mfaTitle: String?
    ) async throws -> Result? {
        try await ProtectedActionPresenter.authorizeProtectedAction(
            on: viewController,
            account: account,
            title: title,
            headerView: headerView,
            passwordAction: passwordAction,
            ledgerSignData: ledgerSignData,
            ledgerFromAddress: ledgerFromAddress,
            presentationStyle: presentationStyle,
            useBioOnPresent: useBioOnPresent,
            completionBehavior: completionBehavior,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
            mfaTitle: mfaTitle
        )
    }
    
    static func repeatActivity(accountContext: AccountContext, _ activity: ApiActivity) {
        let action = {
            switch activity {
            case .transaction(let transaction):
                guard accountContext.account.supportsSend else {
                    AppActions.showError(error: DisplayError(text: lang("Read-only account")))
                    return
                }
                if transaction.isStaking {
                    guard accountContext.account.supportsEarn else {
                        AppActions.showError(error: DisplayError(text: lang("Earn is not supported on this account.")))
                        return
                    }
                    let tokenSlug = stakingTokenSlug(for: transaction, accountContext: accountContext)
                    switch transaction.type {
                    case .unstake, .unstakeRequest:
                        showEarn(accountContext: accountContext, tokenSlug: tokenSlug, initialAction: .unstake)
                    default:
                        AppActions.showEarn(accountContext: accountContext, tokenSlug: tokenSlug)
                    }
                } else if transaction.type == nil && transaction.nft == nil && !transaction.isIncoming {
                    AppActions.showSend(accountContext: accountContext, prefilledValues: .init(
                        address: transaction.toAddress,
                        amount: transaction.amount == 0 ? nil : abs(transaction.amount),
                        token: transaction.slug,
                        commentOrMemo: transaction.comment
                    ))
                }
            case .swap(let swap):
                guard accountContext.account.supportsSwap else {
                    AppActions.showError(error: DisplayError(text: lang("Swap is not supported on this account.")))
                    return
                }
                AppActions.showSwap(
                    accountContext: accountContext,
                    defaultSellingToken: swap.from,
                    defaultBuyingToken: swap.to,
                    defaultSellingAmount: swap.fromAmount.value,
                    push: nil
                )
            }
        }
        if let presenting = topWViewController()?.presentingViewController {
            presenting.dismiss(animated: true, completion: action)
        } else {
            action()
        }
    }

    private static func stakingTokenSlug(for transaction: ApiTransactionActivity, accountContext: AccountContext) -> String {
        if let tokenSlug = stakingTokenSlugMatchingTransactionAddress(for: transaction, stakingData: accountContext.stakingData) {
            return tokenSlug
        }
        return StakingConfig.config(forTokenSlug: transaction.slug)?.baseTokenSlug ?? transaction.slug
    }

    private static func stakingTokenSlugMatchingTransactionAddress(for transaction: ApiTransactionActivity, stakingData: MStakingData?) -> String? {
        guard let stakingData else { return nil }
        let addresses = Set([transaction.fromAddress, transaction.toAddress, transaction.normalizedAddress]
            .compactMap { $0 }
            .filter { !$0.isEmpty })
        guard !addresses.isEmpty else { return nil }
        let states = stakingData.stateById.values
        if let state = states.first(where: { $0.tokenSlug != TONCOIN_SLUG && stakingState($0, matchesAny: addresses) }) {
            return state.tokenSlug
        }
        if StakingConfig.config(forTokenSlug: transaction.slug) == nil,
           let state = states.first(where: { stakingState($0, matchesAny: addresses) }) {
            return state.tokenSlug
        }
        return nil
    }

    private static func stakingState(_ state: ApiStakingState, matchesAny addresses: Set<String>) -> Bool {
        return switch state {
        case .liquid(let liquid):
            contains(liquid.pool, in: addresses)
        case .nominators(let nominators):
            contains(nominators.pool, in: addresses)
        case .jetton(let jetton):
            contains(jetton.pool, in: addresses) ||
            contains(jetton.stakeWalletAddress, in: addresses) ||
            contains(jetton.tokenAddress, in: addresses) ||
            (jetton.poolWallets?.contains { addresses.contains($0) } ?? false)
        case .ethena(let ethena):
            contains(ethena.pool, in: addresses) ||
            contains(ethena.tsUsdeWalletAddress, in: addresses) ||
            contains(ApiToken.TON_TSUSDE.tokenAddress, in: addresses)
        case .unknown:
            false
        }
    }

    private static func contains(_ address: String?, in addresses: Set<String>) -> Bool {
        address.map { addresses.contains($0) } ?? false
    }
    
    static func scanAndHandleQR(accountContext: AccountContext) {
        Task {
            if let result = await scanQR() {
                handleScanResult(result, accountContext: accountContext)
            }
        }
    }
    
    static func scanQR() async -> ScanResult? {
        return await withCheckedContinuation { continuation in
            guard let topVC = topViewController() else {
                continuation.resume(returning: nil)
                return
            }
            let qrScanVC = QRScanVC(callback: { result in
                continuation.resume(returning: result)
            })
            topVC.present(WNavigationController(rootViewController: qrScanVC), animated: true)
        }
    }
    
    private static func handleScanResult(_ result: ScanResult, accountContext: AccountContext) {
        switch result {
        case .url(let url):
            let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: url, source: .qrScan) ?? false
            if !deeplinkHandled {
                AppActions.showError(error: DisplayError(text: lang("This QR Code is not supported")))
            }

        case .address(address: let address, possibleChains: let chains):
            AppActions.showSend(accountContext: accountContext, prefilledValues: .init(
                address: address,
                token: chains.first?.nativeToken.slug
            ))
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
        topVC.presentActivityViewController(activityViewController)
    }
    
    static func showActivityDetails(accountId: String, activity: ApiActivity, context: ActivityDetailsContext) {
        Task {
            let updatedActivity = await ActivityStore.getActivity(accountId: accountId, activityId: activity.id)
            let vc = ActivityVC(activity: updatedActivity ?? activity, accountSource: .accountId(accountId), context: context)
            
            if context.isTransactionConfirmation {
                guard let navigationController = topViewController() as? UINavigationController else { return }
                let coordinator = ContentReplaceAnimationCoordinator()
                vc.navigationItem.hidesBackButton = true
                coordinator.replaceNavigationTop(with: vc, in: navigationController) {
                    vc.animateToCollapsed()
                }
            } else if let listVC = topWViewController() as? ActivityDetailsListVC {
                listVC.navigationController?.pushViewController(vc, animated: true)
            } else {
                let navigationController = WNavigationController(rootViewController: vc)
                navigationController.isExtraSheetDimmingEnabled = true
                topViewController()?.present(navigationController, animated: true)
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
            delegate: nil,
            isModal: true,
            onlySupportedChains: true
        )
        let nc = WNavigationController()
        nc.viewControllers = [assets, add]
        topViewController()?.present(nc, animated: true)
    }
    
    static func showAddWallet(network: ApiNetwork) {
        rootContainerRouter.showAddWallet(network: network)
    }
    
    static func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) {
        rootContainerRouter.showAssets(accountSource: accountSource, selectedTab: selectedTab, collectionsFilter: collectionsFilter)
    }

    static func showAssetsAndActivity() {
        let vc = AssetsAndActivityVC()
        let nc = WNavigationController(rootViewController: vc)
        topViewController()?.present(nc, animated: true)
    }
    
    static func showBuyWithCard(accountContext: AccountContext, chain: ApiChain?, push: Bool?) {
        guard accountContext.account.network == .mainnet else {
            AppActions.showError(error: DisplayError(text: lang("Buying with card is not supported in Testnet.")))
            return
        }
        let chain = chain ?? accountContext.account.firstChain
        guard chain.isOnrampSupported else {
            AppActions.showError(error: DisplayError(text: lang("Buying with card is not supported for this chain.")))
            return
        }
        let buyWithCardVC = BuyWithCardVC(accountContext: accountContext, chain: chain)
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
    
    static func showCustomizeAppTabs() {
        let vc = CustomizeAppTabsVC()
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

    static func showAgent() {
        rootContainerRouter.showAgent()
    }
    
    static func showEarn(accountContext: AccountContext, tokenSlug: String?) {
        showEarn(accountContext: accountContext, tokenSlug: tokenSlug, initialAction: nil)
    }

    private static func showEarn(accountContext: AccountContext, tokenSlug: String?, initialAction: EarnInitialAction?) {
        let earnVC = EarnRootVC(accountContext: accountContext, tokenSlug: tokenSlug, initialAction: initialAction)
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
        if let nc = topVC as? WNavigationController {
            nc.pushViewController(hiddenVC, animated: true)
        } else if let vc = topWViewController(), let nc = vc.navigationController {
            nc.pushViewController(hiddenVC, animated: true)
        } else if rootContainerRouter.pushOnHome(hiddenVC) {
            return
        } else {
            let assetsVC = AssetsTabVC(accountSource: accountSource, defaultTab: .nfts)
            let nc = WNavigationController()
            nc.viewControllers = [assetsVC, hiddenVC]
            topVC?.present(nc, animated: true)
        }
    }
    
    static func showHome(popToRoot: Bool) {
        rootContainerRouter.showHome(popToRoot: popToRoot)
    }

    static func showLinkDomain(accountSource: AccountSource, nftAddress: String) {
        showLinkDomain(accountSource: accountSource, nftAddress: nftAddress, nft: nil)
    }

    static func showLinkDomain(accountSource: AccountSource, nftAddress: String, nft: ApiNft?) {
        let vc = LinkDomainVC(accountSource: accountSource, nftAddress: nftAddress, nft: nft)
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }

    static func showNft(accountContext: AccountContext, nft: ApiNft, isExpanded: Bool) {
        let accountId = accountContext.account.id
        let nftVC = NftDetailsVC(accountId: accountId, source: .singleNft(nft), isExpanded: isExpanded)
        let nav = WNavigationController(rootViewController: nftVC)
        nav.modalPresentationStyle = .overFullScreen
        topViewController()?.present(nav, animated: true)
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
                let nftVC = NftDetailsVC(accountId: accountId, source: .singleNft(nft), isExpanded: true)
                pushIfNeeded(nftVC, push: true)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }

    static func showPromotion(_ promotion: ApiPromotion) {
        guard promotion.modal != nil else { return }
        let vc = PromotionVC(promotion: promotion)
        let nc = WNavigationController(rootViewController: vc)
        if let sheet = nc.sheetPresentationController {
            sheet.prefersGrabberVisible = false
            if #available(iOS 26.1, *) {
                sheet.backgroundEffect = UIColorEffect(color: .air.sheetBackground)
            }
        }
        topViewController()?.present(nc, animated: true)
    }

    static func showPortfolio(accountContext: AccountContext) {
        let vc = PortfolioVC(accountContext: accountContext)
        pushIfNeeded(vc, push: true)
    }
    
    static func showReceive(accountContext: AccountContext, chain: ApiChain?) {
        let receiveVC = ReceiveVC(accountContext: accountContext, chain: chain)
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

    static func showSettings(section: AppSettingsSection?) {
        guard let path = settingsPath(for: section) else { return }
        rootContainerRouter.showSettings(path: path)
    }
    
    static func showSend(accountContext: AccountContext, prefilledValues: SendPrefilledValues) {
        if accountContext.account.supportsSend != true {
            AppActions.showError(error: DisplayError(text: lang("Read-only account")))
            return
        }
        if prefilledValues.nfts?.contains(where: \.isOnSale) == true {
            AppActions.showToast(message: lang("For sale. Cannot be sent and burned"))
            return
        }
        let isAccountSwitchingAllowed = accountContext.source == .current
        let sendAccountContext = AccountContext(accountId: accountContext.account.id)
        topViewController()?.present(
            SendVC(
                accountContext: sendAccountContext,
                prefilledValues: prefilledValues,
                isAccountSwitchingAllowed: isAccountSwitchingAllowed
            ),
            animated: true
        )
    }
    
    static func showSell(accountContext: AccountContext, tokenSlug: String?) {
        let tokenSlug = tokenSlug ?? TONCOIN_SLUG
        guard getChainBySlug(tokenSlug)?.isOfframpSupported == true else {
            AppActions.showError(error: DisplayError(text: lang("Selling is not supported for this token.")))
            return
        }
        let vc = SellVC(accountContext: accountContext, tokenSlug: tokenSlug)
        topViewController()?.present(WNavigationController(rootViewController: vc), animated: true)
    }
    
    static func showSwap(accountContext: AccountContext, defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?) {
        if accountContext.account.supportsSwap != true {
            AppActions.showError(error: DisplayError(text: lang("Swap is not supported on this account.")))
            return
        }
        let isAccountSwitchingAllowed = accountContext.source == .current
        let swapAccountContext = AccountContext(accountId: accountContext.account.id)
        let swapVC = SwapVC(
            accountContext: swapAccountContext,
            defaultSellingToken: defaultSellingToken,
            defaultBuyingToken: defaultBuyingToken,
            defaultSellingAmount: defaultSellingAmount,
            isAccountSwitchingAllowed: isAccountSwitchingAllowed
        )
        pushIfNeeded(swapVC, push: push)
    }
    
    static func showTemporaryViewAccount(network: ApiNetwork, addressOrDomainByChain: [String: String]) {
        Task { @MainActor in
            do {
                if addressOrDomainByChain.isEmpty {
                    throw DisplayError(text: lang("$no_valid_view_addresses"))
                }
                // TODO: Show loading indicator
                let account = try await AccountStore.importTemporaryViewAccountOrActivateFirstMatching(network: network, addressOrDomainByChain: addressOrDomainByChain)
                rootContainerRouter.showTemporaryViewAccount(accountId: account.id)
                if network == .testnet {
                    AppActions.showToast(message: lang("Testnet Version"))
                }
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    static func showToast(_ config: ToastConfig) {
        topWViewController()?.showToast(config)
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
                        AppActions.showError(error: DisplayError(text: lang("$unknown_token_address")))
                    }
                    return
                }
                await MainActor.run {
                    presentOrPushToken(accountSource: .current, token: token)
                }
            } catch {
                await MainActor.run {
                    AppActions.showError(error: DisplayError(text: lang("$unknown_token_address")))
                }
            }
        }
    }

    static func showTokenBySlug(_ slug: String) {
        guard let token = TokenStore.getToken(slug: slug) else {
            AppActions.showError(error: DisplayError(text: lang("$unknown_token_address")))
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
        AppActions.openInBrowser(URL(string:  "https://getgems.io/collection/EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM")!, title: "My Wallet NFT Cards", injectDappConnect: true)
    }
    
    static func showWalletSettings() {
        let vc = WalletSettingsVC()
        let nc = WNavigationController(rootViewController: vc)
        topViewController()?.present(nc, animated: true)
    }
    
    static func transitionToRootState(_ rootState: AppRootState, animationDuration: Double?) {
        RootStateCoordinator.shared.transition(to: rootState, animationDuration: animationDuration)
    }

    private static func settingsPath(for section: AppSettingsSection?) -> [UIViewController]? {
        switch section {
        case nil:
            return []
        case .appearance:
            return [AppearanceSettingsVC()]
        case .assets:
            return [AssetsAndActivityVC()]
        case .language:
            return [LanguageVC()]
        case .notifications:
            return [NotificationsSettingsVC()]
        case .dapps:
            guard AccountStore.account?.isView != true else { return nil }
            return [ConnectedAppsVC(isModal: false)]
        case .walletVersions:
            guard AccountStore.walletVersionsData?.versions.isEmpty == false else { return nil }
            return [WalletVersionsVC()]
        case .disclaimer:
            return [UseResponsiblyVC()]
        case .about:
            return [AboutVC(showLegalSection: true)]
        case .hiddenNfts:
            return [AssetsAndActivityVC(), HiddenNftsVC()]
        }
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

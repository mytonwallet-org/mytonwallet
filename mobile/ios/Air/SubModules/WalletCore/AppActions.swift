
import UIKit
import SwiftUI
import WalletContext
import WalletCoreTypes

@MainActor
public struct ActivityDetailsPresentation {
    public let viewController: UIViewController
    public let animateAlongside: () -> Void

    public init(
        viewController: UIViewController,
        animateAlongside: @escaping () -> Void
    ) {
        self.viewController = viewController
        self.animateAlongside = animateAlongside
    }
}

// Please keep methods in alphabetical order

@MainActor public protocol AppActionsProtocol {
    static func copyString(_ string: String?, toastMessage: String)
    static func hideAndReportNft(accountId: String, nft: ApiNft, onConfirmed: (() -> Void)?)
    static func hideNft(accountId: String, nft: ApiNft, onHidden: (() -> Void)?)
    static func lockApp(animated: Bool)
    static func makeProtectedActionActivityDetailsPresentation(accountId: String, activity: ApiActivity, context: ActivityDetailsContext) async throws -> ActivityDetailsPresentation
    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool, historyTag: String?)
    static func openTipsChannel()
    static func repeatActivity(accountContext: AccountContext, _ activity: ApiActivity)
    static func reportNft(accountId: String, nft: ApiNft, onConfirmed: (() -> Void)?)
    static func saveTemporaryViewAccount(accountId: String)
    static func scanAndHandleQR(accountContext: AccountContext)
    static func scanQR() async -> ScanResult?
    static func setSensitiveDataIsHidden(_ newValue: Bool)
    static func shareUrl(_ url: URL)
    static func showActivityDetails(accountId: String, activity: ApiActivity, context: ActivityDetailsContext)
    static func showActivityDetailsById(chain: ApiChain, txId: String, showError: Bool)
    static func showAddToken()
    static func showAddWallet(network: ApiNetwork)
    static func showAnyAccountTx(accountId: String, chain: ApiChain, txId: String, showError: Bool)
    static func showAgent()
    static func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter)
    static func showAssetsAndActivity()
    static func showBuyWithCard(accountContext: AccountContext, chain: ApiChain?, push: Bool?)
    static func showConnectedDapps(push: Bool)
    static func showCrossChainSwapVC(_ transaction: ApiActivity, accountId: String?)
    static func showCustomizeAppTabs()
    static func showCustomizeWallet(accountId: String?)
    static func showDebugView()
    static func showDeleteAccount(accountId: String)
    static func showEarn(accountContext: AccountContext, tokenSlug: String?)
    static func showError(error: Error?)
    static func showExplore()
    static func showExploreSite(siteHost: String)
    static func showHiddenNfts(accountSource: AccountSource) -> ()
    static func showHome(popToRoot: Bool)
    static func showLinkDomain(accountSource: AccountSource, nftAddress: String)
    static func showLinkDomain(accountSource: AccountSource, nftAddress: String, nft: ApiNft?)
    static func showNft(accountContext: AccountContext, nft: ApiNft, isExpanded: Bool)
    static func showNftByAddress(_ nftAddress: String)
    static func showPromotion(_ promotion: ApiPromotion)
    static func showPortfolio(accountContext: AccountContext)
    static func showReceive(accountContext: AccountContext, chain: ApiChain?)
    static func showRenewDomain(accountSource: AccountSource, nftsToRenew: [String])
    static func showRenameAccount(accountId: String)
    static func showSaveAddressDialog(accountContext: AccountContext, chain: ApiChain, address: String)
    static func showSettings(section: AppSettingsSection?)
    static func showSend(accountContext: AccountContext, prefilledValues: SendPrefilledValues)
    static func showSell(accountContext: AccountContext, tokenSlug: String?)
    static func showSwap(accountContext: AccountContext, defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?)
    static func showTemporaryViewAccount(network: ApiNetwork, addressOrDomainByChain: [String: String])
    static func showToast(_ config: ToastConfig)
    static func showToken(accountSource: AccountSource, token: ApiToken, isInModal: Bool)
    static func showTokenByAddress(chain: ApiChain, tokenAddress: String)
    static func showTokenBySlug(_ slug: String)
    static func showUpgradeCard()
    static func showWalletSettings()
    static func transitionToRootState(_ rootState: AppRootState, animationDuration: Double?)
}

@MainActor public var AppActions: any AppActionsProtocol.Type = DummyAppActionProtocolImpl.self

public extension AppActionsProtocol {
    static func openInBrowser(_ url: URL) {
        Self.openInBrowser(url, title: nil, injectDappConnect: true, historyTag: nil)
    }

    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool) {
        Self.openInBrowser(url, title: title, injectDappConnect: injectDappConnect, historyTag: nil)
    }

    static func showToast(style: ToastStyle? = nil, icon: ToastIcon? = nil, message: String, duration: Double? = nil,
                          transition: ToastTransition? = nil, actionTitle: String? = nil, action: (() -> ())? = nil) {
        showToast(.init(
            style: style, icon: icon, message: message,
            duration: duration, transition: transition,
            actionTitle: actionTitle, action: action)
        )
    }
    
    static func showMultisend() {
        guard let url = URL(string: MYTONWALLET_MULTISEND_DAPP_URL) else {
            assertionFailure()
            return
        }
        Self.openInBrowser(url, title: lang("Multisend"), injectDappConnect: true)
    }
}

private class DummyAppActionProtocolImpl: AppActionsProtocol {
    static func copyString(_ string: String?, toastMessage: String) { }
    static func hideAndReportNft(accountId: String, nft: ApiNft, onConfirmed: (() -> Void)?) { onConfirmed?() }
    static func hideNft(accountId: String, nft: ApiNft, onHidden: (() -> Void)?) { onHidden?() }
    static func lockApp(animated: Bool) { }
    static func makeProtectedActionActivityDetailsPresentation(accountId: String, activity: ApiActivity, context: ActivityDetailsContext) async throws -> ActivityDetailsPresentation {
        ActivityDetailsPresentation(viewController: UIViewController(), animateAlongside: {})
    }
    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool, historyTag: String?) { }
    static func openTipsChannel() { }
    static func repeatActivity(accountContext: AccountContext, _ activity: ApiActivity) { }
    static func reportNft(accountId: String, nft: ApiNft, onConfirmed: (() -> Void)?) { onConfirmed?() }
    static func scanAndHandleQR(accountContext: AccountContext) { }
    static func scanQR() async -> ScanResult? { nil }
    static func saveTemporaryViewAccount(accountId: String) { }
    static func setSensitiveDataIsHidden(_ newValue: Bool) { }
    static func shareUrl(_ url: URL) { }
    static func showActivityDetails(accountId: String, activity: ApiActivity, context: ActivityDetailsContext) { }
    static func showActivityDetailsById(chain: ApiChain, txId: String, showError: Bool) { }
    static func showAddToken() { }
    static func showAddWallet(network: ApiNetwork) { }
    static func showAnyAccountTx(accountId: String, chain: ApiChain, txId: String, showError: Bool) { }
    static func showAgent() { }
    static func showAssets(accountSource: AccountSource, selectedTab: DisplayAssetTab, collectionsFilter: NftCollectionFilter) { }
    static func showAssetsAndActivity() { }
    static func showBuyWithCard(accountContext: AccountContext, chain: ApiChain?, push: Bool?) { }
    static func showConnectedDapps(push: Bool) { }
    static func showCrossChainSwapVC(_ transaction: ApiActivity, accountId: String?) { }
    static func showCustomizeWallet(accountId: String?) { }
    static func showCustomizeAppTabs() { }
    static func showDebugView() { }
    static func showDeleteAccount(accountId: String) { }
    static func showEarn(accountContext: AccountContext, tokenSlug: String?) { }
    static func showError(error: Error?) { }
    static func showExplore() { }
    static func showExploreSite(siteHost: String) { }
    static func showHiddenNfts(accountSource: AccountSource) -> () { }
    static func showHome(popToRoot: Bool) { }
    static func showLinkDomain(accountSource: AccountSource, nftAddress: String) { }
    static func showLinkDomain(accountSource: AccountSource, nftAddress: String, nft: ApiNft?) { }
    static func showNft(accountContext: AccountContext, nft: ApiNft, isExpanded: Bool) { }
    static func showNftByAddress(_ nftAddress: String) { }
    static func showPromotion(_ promotion: ApiPromotion) { }
    static func showPortfolio(accountContext: AccountContext) { }
    static func showReceive(accountContext: AccountContext, chain: ApiChain?) { }
    static func showRenewDomain(accountSource: AccountSource, nftsToRenew: [String]) { }
    static func showRenameAccount(accountId: String) { }
    static func showSaveAddressDialog(accountContext: AccountContext, chain: ApiChain, address: String) { }
    static func showSettings(section: AppSettingsSection?) { }
    static func showSend(accountContext: AccountContext, prefilledValues: SendPrefilledValues) { }
    static func showSell(accountContext: AccountContext, tokenSlug: String?) { }
    static func showSwap(accountContext: AccountContext, defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?) { }
    static func showTemporaryViewAccount(network: ApiNetwork, addressOrDomainByChain: [String: String]) { }
    static func showToast(_ config: ToastConfig) { }
    static func showToken(accountSource: AccountSource, token: ApiToken, isInModal: Bool) { }
    static func showTokenByAddress(chain: ApiChain, tokenAddress: String) { }
    static func showTokenBySlug(_ slug: String) { }
    static func showUpgradeCard() { }
    static func showWalletSettings() { }
    static func transitionToRootState(_ rootState: AppRootState, animationDuration: Double?) { }
}

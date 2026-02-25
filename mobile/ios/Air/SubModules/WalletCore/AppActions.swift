
import UIKit
import WalletContext

// Please keep methods in alphabetical order

@MainActor public protocol AppActionsProtocol {
    static func copyString(_ string: String?, toastMessage: String)
    static func lockApp(animated: Bool)
    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool)
    static func openTipsChannel()
    static func repeatActivity(_ activity: ApiActivity)
    static func saveTemporaryViewAccount(accountId: String)
    static func scanQR() async -> ScanResult?
    static func setSensitiveDataIsHidden(_ newValue: Bool)
    static func shareUrl(_ url: URL)
    static func showActivityDetails(accountId: String, activity: ApiActivity, context: ActivityDetailsContext)
    static func showActivityDetailsById(chain: ApiChain, txId: String, showError: Bool)
    static func showAddToken()
    static func showAddWallet(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool)
    static func showAnyAccountTx(accountId: String, chain: ApiChain, txId: String, showError: Bool)
    static func showAssets(accountSource: AccountSource, selectedTab: Int, collectionsFilter: NftCollectionFilter)
    static func showAssetsAndActivity()
    static func showBuyWithCard(chain: ApiChain?, push: Bool?)
    static func showConnectedDapps(push: Bool)
    static func showCrossChainSwapVC(_ transaction: ApiActivity, accountId: String?)
    static func showCustomizeWallet(accountId: String?)
    static func showDeleteAccount(accountId: String)
    static func showEarn(tokenSlug: String?)
    static func showError(error: Error?)
    static func showExplore()
    static func showExploreSite(siteHost: String)
    static func showHiddenNfts(accountSource: AccountSource) -> ()
    static func showHome(popToRoot: Bool)
    static func showImportWalletVersion() -> ()
    static func showLinkDomain(accountSource: AccountSource, nftAddress: String)
    static func showNftByAddress(_ nftAddress: String)
    static func showReceive(chain: ApiChain?, title: String?)
    static func showRenewDomain(accountSource: AccountSource, nftsToRenew: [String])
    static func showRenameAccount(accountId: String)
    static func showSaveAddressDialog(accountContext: AccountContext, chain: ApiChain, address: String)
    static func showSend(prefilledValues: SendPrefilledValues)
    static func showSell(account: MAccount?, tokenSlug: String?)
    static func showSwap(defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?)
    static func showTemporaryViewAccount(addressOrDomainByChain: [String: String])
    static func showToast(animationName: String?, message: String, duration: Double, tapAction: (() -> ())?)
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
        Self.openInBrowser(url, title: nil, injectDappConnect: true)
    }
    static func showToast(animationName: String? = nil, message: String, duration: Double? = nil, tapAction: (() -> ())? = nil) {
        showToast(animationName: animationName, message: message, duration: duration ?? 3, tapAction: tapAction)
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
    static func lockApp(animated: Bool) { }
    static func openInBrowser(_ url: URL, title: String?, injectDappConnect: Bool) { }
    static func openTipsChannel() { }
    static func repeatActivity(_ activity: ApiActivity) { }
    static func scanQR() async -> ScanResult? { nil }
    static func saveTemporaryViewAccount(accountId: String) { }
    static func setSensitiveDataIsHidden(_ newValue: Bool) { }
    static func shareUrl(_ url: URL) { }
    static func showActivityDetails(accountId: String, activity: ApiActivity, context: ActivityDetailsContext) { }
    static func showActivityDetailsById(chain: ApiChain, txId: String, showError: Bool) { }
    static func showAddToken() { }
    static func showAddWallet(network: ApiNetwork, showCreateWallet: Bool, showSwitchToOtherVersion: Bool) { }
    static func showAnyAccountTx(accountId: String, chain: ApiChain, txId: String, showError: Bool) { }
    static func showAssets(accountSource: AccountSource, selectedTab: Int, collectionsFilter: NftCollectionFilter) { }
    static func showAssetsAndActivity() { }
    static func showBuyWithCard(chain: ApiChain?, push: Bool?) { }
    static func showConnectedDapps(push: Bool) { }
    static func showCrossChainSwapVC(_ transaction: ApiActivity, accountId: String?) { }
    static func showCustomizeWallet(accountId: String?) { }
    static func showDeleteAccount(accountId: String) { }
    static func showEarn(tokenSlug: String?) { }
    static func showError(error: Error?) { }
    static func showExplore() { }
    static func showExploreSite(siteHost: String) { }
    static func showHiddenNfts(accountSource: AccountSource) -> () { }
    static func showHome(popToRoot: Bool) { }
    static func showImportWalletVersion() -> () { }
    static func showLinkDomain(accountSource: AccountSource, nftAddress: String) { }
    static func showNftByAddress(_ nftAddress: String) { }
    static func showReceive(chain: ApiChain?, title: String?) { }
    static func showRenewDomain(accountSource: AccountSource, nftsToRenew: [String]) { }
    static func showRenameAccount(accountId: String) { }
    static func showSaveAddressDialog(accountContext: AccountContext, chain: ApiChain, address: String) { }
    static func showSend(prefilledValues: SendPrefilledValues) { }
    static func showSell(account: MAccount?, tokenSlug: String?) { }
    static func showSwap(defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?) { }
    static func showTemporaryViewAccount(addressOrDomainByChain: [String: String]) { }
    static func showToast(animationName: String?, message: String, duration: Double, tapAction: (() -> ())?) { }
    static func showToken(accountSource: AccountSource, token: ApiToken, isInModal: Bool) { }
    static func showTokenByAddress(chain: ApiChain, tokenAddress: String) { }
    static func showTokenBySlug(_ slug: String) { }
    static func showUpgradeCard() { }
    static func showWalletSettings() { }
    static func transitionToRootState(_ rootState: AppRootState, animationDuration: Double?) { }
}

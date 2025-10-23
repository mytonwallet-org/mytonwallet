
import UIKit
import WalletContext

@MainActor public protocol AppActionsProtocol {
    static func copyString(_ string: String?, toastMessage: String)
    static func lockApp(animated: Bool)
    static func openInBrowser(_ url: URL, title: String?, injectTonConnect: Bool)
    static func openTipsChannel()
    static func pushTransactionSuccess(activity: ApiActivity)
    static func repeatActivity(_ activity: ApiActivity)
    static func scanQR() -> ()
    static func setSensitiveDataIsHidden(_ newValue: Bool)
    static func shareUrl(_ url: URL)
    static func showActivityDetails(accountId: String, activity: ApiActivity)
    static func showAddToken()
    static func showAddWallet(showCreateWallet: Bool, showSwitchToOtherVersion: Bool)
    static func showAssets(selectedTab: Int, collectionsFilter: NftCollectionFilter) -> ()
    static func showBuyWithCard(chain: ApiChain?, push: Bool?)
    static func showConnectedDapps(push: Bool)
    static func showCrossChainSwapVC(_ transaction: ApiActivity)
    static func showEarn(token: ApiToken?)
    static func showError(error: Error?)
    static func showHiddenNfts() -> ()
    static func showImportWalletVersion() -> ()
    static func showReceive(chain: ApiChain?, showBuyOptions: Bool?, title: String?)
    static func showSend(prefilledValues: SendPrefilledValues?)
    static func showSwap(defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?)
    static func showToken(token: ApiToken, isInModal: Bool)
    static func showUpgradeCard()
    static func transitionToNewRootViewController(_ newRootController: UIViewController, animationDuration: Double?)
}

@MainActor public var AppActions: any AppActionsProtocol.Type = DummyAppActionProtocolImpl.self

public extension AppActionsProtocol {
    static func openInBrowser(_ url: URL) {
        Self.openInBrowser(url, title: nil, injectTonConnect: true)
    }
}

private class DummyAppActionProtocolImpl: AppActionsProtocol {
    static func copyString(_ string: String?, toastMessage: String) { }
    static func lockApp(animated: Bool) { }
    static func openInBrowser(_ url: URL, title: String?, injectTonConnect: Bool) { }
    static func openTipsChannel() { }
    static func pushTransactionSuccess(activity: ApiActivity) { }
    static func repeatActivity(_ activity: ApiActivity) { }
    static func scanQR() -> () { }
    static func setSensitiveDataIsHidden(_ newValue: Bool) { }
    static func shareUrl(_ url: URL) { }
    static func showActivityDetails(accountId: String, activity: ApiActivity) { }
    static func showAddToken() { }
    static func showAddWallet(showCreateWallet: Bool, showSwitchToOtherVersion: Bool) { }
    static func showAssets(selectedTab: Int, collectionsFilter: NftCollectionFilter) -> () { }
    static func showBuyWithCard(chain: ApiChain?, push: Bool?) { }
    static func showConnectedDapps(push: Bool) { }
    static func showCrossChainSwapVC(_ transaction: ApiActivity) { }
    static func showEarn(token: ApiToken?) { }
    static func showError(error: Error?) { }
    static func showHiddenNfts() -> () { }
    static func showImportWalletVersion() -> () { }
    static func showReceive(chain: ApiChain?, showBuyOptions: Bool?, title: String?) { }
    static func showSend(prefilledValues: SendPrefilledValues?) { }
    static func showSwap(defaultSellingToken: String?, defaultBuyingToken: String?, defaultSellingAmount: Double?, push: Bool?) { }
    static func showToken(token: ApiToken, isInModal: Bool) { }
    static func showUpgradeCard() { }
    static func transitionToNewRootViewController(_ newRootController: UIViewController, animationDuration: Double?) { }
}

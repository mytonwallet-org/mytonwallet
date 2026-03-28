import UIKit
import WalletCore
import WalletContext

enum SplitHomeActionItem: CaseIterable, Hashable, Sendable {
    case buy
    case deposit
    case earn
    case scan
    case sell
    case send
    case swap

    var title: String {
        switch self {
        case .buy: lang("Buy")
        case .deposit: lang("Fund")
        case .earn: lang("Earn")
        case .scan: lang("Scan")
        case .sell: lang("Sell")
        case .send: lang("Send")
        case .swap: lang("Swap")
        }
    }
    
    var image: UIImage? {
        switch self {
        case .buy: .airBundle("BuyIconLarge")
        case .deposit: .airBundle("DepositIconLarge")
        case .earn: .airBundle("EarnIconLarge")
        case .scan: .airBundle("ScanIconLarge")
        case .sell: .airBundle("SellIconLarge")
        case .send: .airBundle("SendIconLarge")
        case .swap: .airBundle("SwapIconLarge")
        }
    }
    
    @MainActor func perform(accountContext: AccountContext) {
        switch self {
        case .buy: AppActions.showBuyWithCard(accountContext: accountContext, chain: nil, push: nil)
        case .deposit: AppActions.showReceive(accountContext: accountContext, chain: nil, title: nil)
        case .earn: AppActions.showEarn(accountContext: accountContext, tokenSlug: nil)
        case .scan: onScan(accountContext: accountContext)
        case .sell: AppActions.showSell(accountContext: accountContext, tokenSlug: nil)
        case .send: AppActions.showSend(accountContext: accountContext, prefilledValues: .init())
        case .swap: AppActions.showSwap(accountContext: accountContext, defaultSellingToken: nil, defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
        }
    }
    
    @MainActor private func onScan(accountContext: AccountContext) {
        Task {
            if let result = await AppActions.scanQR() {
                switch result {
                case .url(let url):
                    let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: url) ?? false
                    if !deeplinkHandled {
                        AppActions.showError(error: BridgeCallError.customMessage(lang("This QR Code is not supported"), nil))
                    }
                case .address(address: let address, possibleChains: let chains):
                    AppActions.showSend(accountContext: accountContext, prefilledValues: .init(address: address, token: chains.first?.nativeToken.slug))
                }
            }
        }
    }
}

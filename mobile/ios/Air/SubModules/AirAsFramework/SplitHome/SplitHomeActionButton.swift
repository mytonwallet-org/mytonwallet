import UIKit
import WalletCore
import WalletContext

@MainActor enum SplitHomeActionItem: CaseIterable, Hashable {
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
    
    func perform() {
        switch self {
        case .buy: AppActions.showBuyWithCard(chain: nil, push: nil)
        case .deposit: AppActions.showReceive(chain: nil, title: nil)
        case .earn: AppActions.showEarn(tokenSlug: nil)
        case .scan: onScan()
        case .sell: AppActions.showSell(account: nil, tokenSlug: nil)
        case .send: AppActions.showSend(prefilledValues: .init())
        case .swap: AppActions.showSwap(defaultSellingToken: nil, defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
        }
    }
    
    private func onScan() {
        Task {
            if let result = await AppActions.scanQR() {
                switch result {
                case .url(let url):
                    let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: url) ?? false
                    if !deeplinkHandled {
                        AppActions.showError(error: BridgeCallError.customMessage(lang("This QR Code is not supported"), nil))
                    }
                case .address(address: let address, possibleChains: let chains):
                    AppActions.showSend(prefilledValues: .init(address: address, token: chains.first?.nativeToken.slug))
                }
            }
        }
    }
}

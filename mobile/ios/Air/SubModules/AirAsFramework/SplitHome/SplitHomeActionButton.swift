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
        case .swap: lang("Trade")
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

    @MainActor
    static func availableItems(for account: MAccount) -> [Self] {
        if account.isView {
            var items: [Self] = account.supportsReceive ? [.deposit] : []
            items.append(.scan)
            return items
        }

        var items: [Self] = [.deposit]
        if !ConfigStore.shared.shouldRestrictSwapsAndOnRamp,
           OnRampCurrencyPolicy.defaultChain(for: account) != nil {
            items.append(.buy)
        }
        if account.supportsSend {
            items.append(.send)
            if !ConfigStore.shared.shouldRestrictSell {
                items.append(.sell)
            }
        }
        if account.supportsSwap {
            items.append(.swap)
        }
        if account.supportsEarn {
            items.append(.earn)
        }
        items.append(.scan)
        return items
    }
    
    @MainActor func perform(accountContext: AccountContext) {
        switch self {
        case .buy: AppActions.showBuyWithCard(accountContext: accountContext, chain: nil, push: nil)
        case .deposit: AppActions.showReceive(accountContext: accountContext, chain: nil)
        case .earn: AppActions.showEarn(accountContext: accountContext, tokenSlug: nil)
        case .scan: AppActions.scanAndHandleQR(accountContext: accountContext)
        case .sell: AppActions.showSell(accountContext: accountContext, tokenSlug: nil)
        case .send: AppActions.showSend(accountContext: accountContext, prefilledValues: .init())
        case .swap:
            Task {
                await AppActions.showSwap(accountContext: accountContext, defaultSellingToken: nil, defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
            }
        }
    }
    
}

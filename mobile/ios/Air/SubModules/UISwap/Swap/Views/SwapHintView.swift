import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct SwapHintView: View {
    var hint: SwapHint
    var onAction: () -> Void

    var body: some View {
        let content = SwapHintContent(hint: hint)
        WarningView(header: content.title, text: content.message, kind: .warning, actionTitle: content.actionTitle, onAction: onAction)
    }
}

struct SwapHintContent {
    let hint: SwapHint
    var tradeDirection: TokenTradeDirection? = nil

    var title: String {
        switch hint {
        case .receive, .belowMinimum:
            lang("Add funds to swap")
        case .intermediate:
            lang(tradeDirection == nil ? "Direct swap unavailable" : "Direct exchange unavailable")
        case .external:
            lang("Swap on an external service")
        }
    }

    var message: String {
        switch hint {
        case .receive(_, let hasAlternativeToken):
            if hasAlternativeToken {
                lang("Buy crypto or choose another token to sell.")
            } else {
                lang("Buy with a card or receive crypto to fund this swap.")
            }
        case .belowMinimum:
            lang("Your balances are small. Add funds or choose another token to swap.")
        case .intermediate(let token, let buyingToken):
            if tradeDirection == .sell {
                L10n.toReceiveBuyTokenFirstReceiveTokenThenExchangeItForBuyToken(buyToken: buyingToken.symbol, token: token.symbol)
            } else {
                L10n.toBuyBuyTokenFirstBuyTokenThenSwapItForBuyToken(buyToken: buyingToken.symbol, token: token.symbol)
            }
        case .external(let providerName, _):
            L10n.openProviderToSwapThisPairInTheBrowser(provider: providerName)
        }
    }

    var actionTitle: String {
        switch hint {
        case .receive, .belowMinimum:
            lang("Fund")
        case .intermediate(let token, _):
            tradeDirection == .sell ? L10n.receiveValue(value: token.symbol) : L10n.buyToken(token: token.symbol)
        case .external(let providerName, _):
            L10n.openProvider(provider: providerName)
        }
    }
}

#Preview("Swap hints") {
    ScrollView {
        VStack(spacing: 16) {
            SwapHintView(hint: .receive(chain: .solana, hasAlternativeToken: false), onAction: {})
            SwapHintView(hint: .receive(chain: .solana, hasAlternativeToken: true), onAction: {})
            SwapHintView(hint: .belowMinimum(chain: .solana), onAction: {})
            SwapHintView(hint: .intermediate(token: ApiChain.solana.nativeToken, buyingToken: ApiToken(
                slug: "solana-preview-nvdax", name: "NVIDIA", symbol: "NVDAx", decimals: 9, chain: .solana
            )), onAction: {})
            SwapHintView(hint: .external(providerName: "1inch", url: URL(string: "https://example.com/swap")!), onAction: {})
        }
        .padding(16)
    }
    .background(Color.air.sheetBackground)
}

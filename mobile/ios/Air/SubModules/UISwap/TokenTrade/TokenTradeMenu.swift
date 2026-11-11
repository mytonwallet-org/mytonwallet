import ContextMenuKit
import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

@MainActor
enum TokenTradeMenu {
    static func configuration(model: TokenTradeModel, showSlippage: @escaping () -> Void,
                              showProvider: @escaping () -> Void) -> ContextMenuConfiguration {
        var items: [ContextMenuItem] = [TradeInfoMenu.row(title: lang("Exchange Rate"), value: { model.rateText })]
        if model.cardCurrency == nil {
            if model.swap.quotedRoute == .dex {
                items += [
                    TradeInfoMenu.row(title: lang("Price Impact"), value: {
                        model.swap.detailsVM.displayEstimate.map { formatPercent($0.impact / 100, decimals: 1, showPlus: false) } ?? "—"
                    }, help: lang("$swap_price_impact_tooltip1") + "\n\n" + lang("$swap_price_impact_tooltip2")),
                    TradeInfoMenu.row(title: lang("Minimum Received"), value: {
                        guard let estimate = model.swap.detailsVM.displayEstimate,
                              let token = model.swap.input.buyingToken else { return "—" }
                        return TokenAmount.fromDouble(estimate.toMinAmount.value, token).formatted(.defaultAdaptive, roundHalfUp: false)
                    }, help: lang("$swap_minimum_received_tooltip2")),
                    .separator,
                    TradeInfoMenu.row(title: lang("Slippage"), value: {
                        formatBigIntText(model.swap.slippage, tokenDecimals: SLIPPAGE_DECIMALS) + "%"
                    }, action: showSlippage),
                ]
            } else {
                items.append(TradeInfoMenu.row(title: lang("Cross-chain Provider"), value: {
                    model.swap.estimateState.cexEstimate?.providerName ?? "—"
                }, action: showProvider, showsChevron: false, showsInfo: true))
            }
        }
        if model.estimateDebugSummary != nil {
            items += [
                .separator,
                .custom(.swiftUI(preferredWidth: 242, sizing: .automatic(minHeight: 0)) { _ in
                    WithPerceptionTracking {
                        if let estimateDebugSummary = model.estimateDebugSummary {
                            Text(estimateDebugSummary)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.air.secondaryLabel)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                        }
                    }
                }),
            ]
        }
        return TradeInfoMenu.configuration(items: items)
    }

}

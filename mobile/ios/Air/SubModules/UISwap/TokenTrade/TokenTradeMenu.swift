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
        var items: [ContextMenuItem] = [row(title: lang("Exchange Rate"), value: { model.rateText })]
        if model.cardCurrency == nil {
            if model.swap.swapType.route == .dex {
                items += [
                    row(title: lang("Price Impact"), value: {
                        model.swap.detailsVM.displayEstimate.map { formatPercent($0.impact / 100, decimals: 1, showPlus: false) } ?? "—"
                    }, help: lang("$swap_price_impact_tooltip1") + "\n\n" + lang("$swap_price_impact_tooltip2")),
                    row(title: lang("Minimum Received"), value: {
                        guard let estimate = model.swap.detailsVM.displayEstimate,
                              let token = model.swap.input.buyingToken else { return "—" }
                        return TokenAmount.fromDouble(estimate.toMinAmount.value, token).formatted(.defaultAdaptive, roundHalfUp: false)
                    }, help: lang("$swap_minimum_received_tooltip2")),
                    .separator,
                    row(title: lang("Slippage"), value: {
                        formatBigIntText(model.swap.slippage, tokenDecimals: SLIPPAGE_DECIMALS) + "%"
                    }, action: showSlippage),
                ]
            } else {
                items.append(row(title: lang("Cross-chain Provider"), value: {
                    model.swap.estimateState.cexEstimate?.providerName ?? "—"
                }, action: showProvider, showsChevron: false, showsInfo: true))
            }
        }
        return ContextMenuConfiguration(rootPage: ContextMenuPage(items: items), backdrop: .none,
            style: ContextMenuStyle(minWidth: 242, maxWidth: 300, glassTint: .strong,
                                    listVerticalPadding: 10, separatorHeight: 20))
    }

    private static func row(title: String, value: @escaping () -> String, help: String? = nil,
                            action: (() -> Void)? = nil, showsChevron: Bool = true,
                            showsInfo: Bool = false) -> ContextMenuItem {
        .custom(.swiftUI(preferredWidth: 242, sizing: .automatic(minHeight: 60),
                        interaction: action.map { .selectable(allowsContentInteraction: true, handler: $0) } ?? .contentHandlesTouches) { _ in
            WithPerceptionTracking {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .lastTextBaseline, spacing: 5) {
                            Text(title)
                                .font(.system(size: 17))
                                .foregroundStyle(Color.air.primaryLabel)
                            if let help {
                                Button {
                                    topViewController()?.showAlert(title: title, text: help, button: lang("OK"))
                                } label: {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.air.secondaryLabel.opacity(0.6))
                                        .padding(6)
                                        .contentShape(.rect)
                                }
                                .padding(-6)
                                .buttonStyle(.plain)
                                .accessibilityLabel(title + ", " + lang("Info"))
                            } else if showsInfo {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.air.secondaryLabel.opacity(0.6))
                            }
                        }
                        Text(value().nilIfEmpty ?? "—")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.air.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if action != nil, showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.air.primaryLabel)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
        })
    }
}

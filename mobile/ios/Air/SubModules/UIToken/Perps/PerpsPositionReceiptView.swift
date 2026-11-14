import Perception
import SwiftUI
import UIComponents
import WalletContext

@Perceptible @MainActor
final class PerpsPositionReceiptPresentation {
    var data: PerpsPositionReceiptDisplayData
    var detailsExpanded = false
    var canCollapse = true

    init(data: PerpsPositionReceiptDisplayData) { self.data = data }
}

struct PerpsPositionReceiptView: View {
    let presentation: PerpsPositionReceiptPresentation
    let onDetails: () -> Void
    let onShare: (() -> Void)?
    let onHeightChange: (CGFloat) -> Void

    private var data: PerpsPositionReceiptDisplayData { presentation.data }
    private var paymentTitle: String {
        if case .opened = data.event { return lang("You Pay") }
        return lang("You Paid")
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: data.event.isLiquidated ? 20 : 16) {
                VStack(spacing: presentation.detailsExpanded && !data.event.isLiquidated ? 8 : 4) {
                    if case .balanceWithdrawal(let withdrawal) = data.event {
                        PerpsWithdrawalSummaryView(amount: withdrawal.receiveAmount, accessibilityPrefix: "perps.receipt")
                    } else {
                        PerpsPositionSummaryView(token: data.token, direction: data.direction, leverage: data.leverage,
                                                 margin: presentation.detailsExpanded ? data.expandedSummaryAmount : data.summaryAmount,
                                                 previousMargin: data.summaryPreviousMargin,
                                                 showsPlus: data.event.showsPlus, isLoss: data.event.isLiquidated && presentation.detailsExpanded,
                                                 isEstimated: presentation.detailsExpanded ? data.expandedSummaryIsEstimated : data.isEstimated,
                                                 shouldHideUnavailableAmount: true,
                                                 spacing: presentation.detailsExpanded ? 28 : 24,
                                                 backgroundColor: .air.sheetBackground, accessibilityPrefix: "perps.receipt")
                    }
                    if let title = presentation.detailsExpanded ? data.expandedSummaryTitle : data.summaryTitle {
                        Text(title)
                            .textStyle(.subheadline)
                            .foregroundStyle(Color.air.secondaryLabel)
                            .accessibilityIdentifier("perps.receipt.summaryTitle")
                    }
                    if let message = data.status.message {
                        TradeNoticeView(title: "", message: message, isWarning: true)
                            .padding(.top, 12)
                    }
                    ReceiptActionsView(onDetails: presentation.canCollapse || data.status.message != nil ? onDetails : nil,
                                       onShare: data.canShare ? onShare : nil,
                                       detailsExpanded: presentation.detailsExpanded, accessibilityPrefix: "perps.receipt",
                                       shareIconName: "PerpsReceiptShare")
                        .padding(.vertical, 16)
                }
                .padding(.bottom, presentation.detailsExpanded ? 0 : 8)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeightChange)
                if presentation.detailsExpanded {
                    VStack(spacing: 20) {
                        details
                        PerpsRemainingCollateralView(remainingCollateral: data.remainingCollateral)
                        if let transferID = data.transferID, !transferID.isEmpty {
                            PerpsTransferIDSection(hash: transferID)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .contentTransition(.numericText())
            .alignedToHostTop()
        }
    }

    @ViewBuilder private var details: some View {
        switch data.event {
        case .opened, .increased, .leverageChanged:
            PerpsPositionMetricsView(tokenName: data.token.name, positionSize: data.positionSize,
                                     price: data.price, liquidationPrice: data.liquidationPrice,
                                     paymentAmount: data.paymentAmount, fee: data.fee,
                                     feeRows: data.feeRows, areFeesEstimated: data.feesAreEstimated,
                                     previous: data.event.previous,
                                     paymentTitle: paymentTitle, isTradeSize: data.isTradeSize)
        case .reduced(let previous, let profitLoss, let entryPrice):
            profitLossRow(profitLoss)
                .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: data.positionSizeTitle,
                                   info: data.isTradeSize ? nil : lang("$perps_position_size_change_hint"), value: data.positionSize,
                                   previousValue: data.isTradeSize ? nil : previous.positionSize)
                AssetInfoMetricRow(title: lang("Entry / Exit Price"), value: entryPrice + " / " + data.price)
                AssetInfoMetricRow(title: lang("Liquidation Price"), info: lang("$perps_liquidation_price_hint"),
                                   value: data.liquidationPrice ?? "—", previousValue: data.liquidationPrice == nil ? nil : previous.liquidationPrice)
            }
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: lang("You Received"), value: data.paymentAmount)
                PerpsFeeSummaryRow(fee: data.fee, rows: data.feeRows, isEstimated: data.feesAreEstimated)
            }
        case .balanceWithdrawal(let withdrawal):
            PerpsBalanceWithdrawalDetailsSection(data: withdrawal, note: data.balanceWithdrawalNote)
        case .closed(let outcome), .liquidated(let outcome):
            if data.event.isLiquidated {
                TradeNoticeView(title: lang("$perps_liquidated_title"), message: lang("$perps_liquidated_message"), isWarning: true)
            }
            ForEach(data.outcomeSections, id: \.first?.id) { fields in
                InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                    ForEach(fields) { field in
                        AssetInfoMetricRow(title: field.title, info: field.info, value: field.value,
                                           valueColor: field.id == "profitLoss" ? outcome.profitLoss.tone.color : .air.primaryLabel)
                    }
                    if fields.first?.id == "received", !data.availableFeeRows.isEmpty {
                        PerpsFeeSummaryRow(fee: data.fee, rows: data.availableFeeRows, isEstimated: data.feesAreEstimated)
                    }
                }
            }
        }
    }

    private func profitLossRow(_ value: PerpsPositionDisplayData.Value) -> some View {
        AssetInfoMetricRow(title: lang(value.tone == .negative ? "Loss" : "Profit"),
                           info: lang(value.tone == .negative ? "$perps_loss_hint" : "$perps_profit_hint"),
                           value: value.text, valueColor: value.tone.color)
    }
}

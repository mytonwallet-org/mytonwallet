import Perception
import SwiftUI
import UIComponents
import WalletContext

struct PerpsOrderReviewView: View {
    let state: PerpsOrderReviewState

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 20) {
                PerpsPositionSummaryView(token: state.data.token, direction: state.data.direction,
                                         leverage: state.data.leverage, margin: state.data.margin,
                                         previousMargin: state.data.mode.previous?.margin,
                                         showsPlus: state.data.mode.operation == .close,
                                         isEstimated: state.data.isEstimated,
                                         accessibilityPrefix: "perps.review")
                if case .close(let closing) = state.data.mode {
                    closingDetails(closing)
                } else {
                    PerpsPositionMetricsView(tokenName: state.data.token.name, positionSize: state.data.positionSize,
                                             price: state.data.price, liquidationPrice: state.data.liquidationPrice,
                                             paymentAmount: state.data.paymentAmount, fee: state.data.fee,
                                             feeRows: state.data.feeRows, areFeesEstimated: true, previous: state.data.mode.previous,
                                             paymentTitle: lang(state.data.mode.operation == .reduce ? "You Receive" : "You Pay"))
                    riskNotice
                    if let accountNotice = state.data.accountNotice {
                        TradeNoticeView(title: "", message: accountNotice, isWarning: false)
                            .accessibilityIdentifier("perps.review.accountMode")
                    }
                }
                PerpsRemainingCollateralView(remainingCollateral: state.data.remainingCollateral)
                if case .unavailable(let message) = state.data.status {
                    TradeNoticeView(title: "", message: message, isWarning: true)
                        .accessibilityIdentifier("perps.review.unavailable")
                } else if let notice = state.data.notice {
                    TradeNoticeView(title: "", message: notice, isWarning: false)
                        .accessibilityIdentifier("perps.review.updated")
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func closingDetails(_ closing: PerpsPositionClosing) -> some View {
        VStack(spacing: 20) {
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: lang("Invested"), info: lang("$perps_invested_hint"), value: closing.invested)
                AssetInfoMetricRow(title: lang("Current Value"), info: lang("$perps_current_value_hint"), value: closing.currentValue)
            }
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: L10n.perpsPriceWhenOpened(asset: state.data.token.name), value: closing.entryPrice)
                AssetInfoMetricRow(title: L10n.perpsPriceNow(asset: state.data.token.name), value: state.data.price)
            }
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: lang("You Receive"), value: state.data.paymentAmount)
                    .accessibilityIdentifier("perps.review.payment")
                PerpsFeeSummaryRow(fee: state.data.fee, rows: state.data.feeRows, isEstimated: true)
            }
        }
    }

    private var riskNotice: some View {
        HStack(spacing: 12) {
            Image("PerpsLiquidationWarning", bundle: AirBundle)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            Text(lang("$perps_liquidation_acknowledgment"))
                .textStyle(.footnote)
                .foregroundStyle(Color.air.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
        .accessibilityIdentifier("perps.review.risk")
    }
}

struct PerpsOrderReviewFooter: View {
    let state: PerpsOrderReviewState

    var body: some View {
        WithPerceptionTracking {
            TradeContinueButton(configuration: .init(title: .text(lang("Confirm")), isEnabled: state.canConfirm,
                                                      showLoading: state.data.status == .loading),
                                tintColor: AirTintColor, accessibilityIdentifier: "perps.review.confirm") {
                state.confirm()
            }
            .frame(height: 52)
        }
    }
}

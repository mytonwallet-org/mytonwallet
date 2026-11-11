import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct PerpsPositionView: View {
    let data: PerpsPositionDisplayData

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                TokenHeroView(token: data.market.token, size: 60, shouldShowChain: false)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Group {
                        if data.equity.optionalAmount != nil {
                            AmountText(amount: data.equity, format: .init(preset: .defaultAdaptive),
                                       integerFont: .compactRounded(ofSize: 36, weight: .bold),
                                       fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                                       symbolFont: .compactRounded(ofSize: 32, weight: .bold),
                                       integerColor: .label, fractionColor: .air.secondaryLabel, symbolColor: .air.secondaryLabel)
                        } else {
                            Text("—").textStyle(.largeTitle, content: .technical)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(lang("Equity"))
                    .accessibilityValue(data.equity.optionalAmount != nil ? data.equity.formatted(.defaultAdaptive) : lang("Unavailable"))
                    .accessibilityIdentifier("perps.position.equity")
                    HStack(spacing: 2) {
                        if data.profitLoss.tone != .neutral {
                            Image(systemName: data.profitLoss.tone == .positive ? "arrow.up" : "arrow.down")
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: data.profitLoss.text)
                    }
                    .textStyle(.body, content: .technical)
                    .foregroundStyle(data.profitLoss.tone.color)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lang("Profit and Loss"))
                    .accessibilityValue(data.profitLoss.text)
                    .accessibilityIdentifier("perps.position.profitLoss")
                }
                .mask { LoadingShineMask(isActive: data.market.isStale) }
            }
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: lang("Invested"), info: lang("$perps_invested_hint"), value: data.invested, isStale: data.market.isStale)
                AssetInfoMetricRow(title: lang("Entry Price"), info: lang("$perps_entry_price_hint"), value: data.entryPrice, isStale: data.market.isStale)
                AssetInfoMetricRow(title: lang("Liquidation Price"), info: lang("$perps_liquidation_price_hint"), value: data.liquidationPrice ?? "—", isStale: data.market.isStale)
                AssetInfoMetricRow(title: lang("Position Size"), info: lang("$perps_position_size_details_hint"), value: data.positionSize, isStale: data.market.isStale)
                AssetInfoMetricRow(title: lang("Funding Payments"), info: lang("$perps_funding_payments_hint"),
                                   value: data.fundingPayments.text, valueColor: data.fundingPayments.tone.color, isStale: data.market.isStale)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

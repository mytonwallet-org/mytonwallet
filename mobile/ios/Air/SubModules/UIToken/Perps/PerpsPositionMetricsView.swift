import SwiftUI
import UIComponents
import WalletContext

struct PerpsPositionMetricsView: View {
    let tokenName: String
    let positionSize: String
    let price: String
    let liquidationPrice: String?
    let paymentAmount: String
    var fee: String? = nil
    var feeExplanation: String? = nil
    var previous: PerpsPositionChange? = nil
    var paymentTitle: String = lang("You Pay")
    var entryPrice: String? = nil
    var isTradeSize = false

    var body: some View {
        VStack(spacing: 20) {
            AssetInfoMetricRow(title: lang(isTradeSize ? "Trade Size" : "Position Size"),
                               info: isTradeSize ? nil : lang(previous == nil ? "$perps_position_size_details_hint" : "$perps_position_size_change_hint"), value: positionSize,
                               previousValue: isTradeSize ? nil : previous?.positionSize)
                .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
            VStack(spacing: 0) {
                AssetInfoMetricRow(title: entryPrice == nil ? L10n.perpsAssetPrice(asset: tokenName) : lang("Entry / Exit Price"),
                                   value: entryPrice.map { $0 + " / " + price } ?? price)
                Divider().padding(.horizontal, 16)
                AssetInfoMetricRow(title: lang("Liquidation Price"), info: lang("$perps_liquidation_price_hint"),
                                   value: liquidationPrice ?? "—", previousValue: liquidationPrice == nil ? nil : previous?.liquidationPrice)
            }
            .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
            VStack(spacing: 0) {
                AssetInfoMetricRow(title: paymentTitle, value: paymentAmount)
                if let fee {
                    Divider().padding(.horizontal, 16)
                    AssetInfoMetricRow(title: lang("Fees"), info: lang("$perps_fees_hint"), value: fee)
                }
            }
            .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
        }
    }
}

struct PerpsFeeDetailsView: View {
    let rows: [PerpsFeeRow]
    let remainingCollateral: String?
    var isEstimated = true

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 12) {
                InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                    ForEach(rows) { row in
                        AssetInfoMetricRow(title: row.title, info: row.id == "total" ? lang("$perps_fees_hint") : nil, value: row.value)
                            .accessibilityIdentifier("perps.fees." + row.id)
                    }
                }
                if isEstimated {
                    Text(lang("PerpsFeeEstimateHint"))
                        .textStyle(.footnote)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                }
            }
        }
        if let remainingCollateral {
            AssetInfoMetricRow(title: lang("PerpsUnallocatedCollateral"), info: lang("PerpsUnallocatedCollateralHint"), value: remainingCollateral)
                .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
                .accessibilityIdentifier("perps.remainingCollateral")
        }
    }

}

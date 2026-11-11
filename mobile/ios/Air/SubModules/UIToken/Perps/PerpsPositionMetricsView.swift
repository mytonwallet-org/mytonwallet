import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct PerpsPositionMetricsView: View {
    let tokenName: String
    let positionSize: String
    let price: String
    let liquidationPrice: String?
    let paymentAmount: String
    let fee: String?
    var feeRows: [PerpsFeeRow] = []
    var areFeesEstimated = false
    var previous: PerpsPositionChange? = nil
    var paymentTitle: String = lang("You Pay")
    var isTradeSize = false

    var body: some View {
        VStack(spacing: 20) {
            AssetInfoMetricRow(title: lang(isTradeSize ? "Trade Size" : "Position Size"),
                               info: isTradeSize ? nil : lang(previous == nil ? "$perps_position_size_details_hint" : "$perps_position_size_change_hint"), value: positionSize,
                               previousValue: isTradeSize ? nil : previous?.positionSize)
                .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
            VStack(spacing: 0) {
                AssetInfoMetricRow(title: L10n.perpsAssetPrice(asset: tokenName), value: price)
                Divider().padding(.horizontal, 16)
                AssetInfoMetricRow(title: lang("Liquidation Price"), info: lang("$perps_liquidation_price_hint"),
                                   value: liquidationPrice ?? "—", previousValue: liquidationPrice == nil ? nil : previous?.liquidationPrice)
            }
            .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
            VStack(spacing: 0) {
                AssetInfoMetricRow(title: paymentTitle, value: paymentAmount)
                Divider().padding(.horizontal, 16)
                PerpsFeeSummaryRow(fee: fee, rows: feeRows, isEstimated: areFeesEstimated)
            }
            .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
        }
    }
}

struct PerpsFeeSummaryRow: View {
    let fee: String?
    var rows: [PerpsFeeRow] = []
    var isEstimated = false

    var body: some View {
        AssetInfoMetricRow(title: lang("Fee"), info: hint, value: fee ?? "—")
            .accessibilityIdentifier("perps.fees.summary")
    }

    var hint: String {
        var sections: [String] = []
        if fee == nil {
            sections.append(lang("PerpsFeesAtExecution"))
        }
        if !rows.isEmpty {
            sections.append(rows.map { $0.title + ": " + $0.value }.joined(separator: "\n"))
        } else if fee != nil {
            sections.append(lang("$perps_fees_hint"))
        }
        if isEstimated {
            sections.append(lang("PerpsFeeEstimateHint"))
        }
        return sections.joined(separator: "\n\n")
    }
}

struct PerpsRemainingCollateralView: View {
    let remainingCollateral: String?

    var body: some View {
        if let remainingCollateral {
            AssetInfoMetricRow(title: lang("PerpsUnallocatedCollateral"), info: lang("PerpsUnallocatedCollateralHint"), value: remainingCollateral)
                .background(Color.air.groupedItem, in: .rect(cornerRadius: 26))
                .accessibilityIdentifier("perps.remainingCollateral")
        }
    }
}

/// The Arbitrum transaction that moved this trade's USDC.
struct PerpsTransferIDSection: View {
    let hash: String

    var body: some View {
        InsetSection(horizontalPadding: 0) {
            InsetDetailCell {
                Text(lang("Transfer ID"))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .fixedSize()
                    .accessibilityHidden(true)
            } value: {
                TappableTransactionId(chain: .arbitrum, txId: hash, isTraceId: false)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lang("Transfer ID") + ", " + hash)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .accessibilityIdentifier("perps.transferID")
    }
}

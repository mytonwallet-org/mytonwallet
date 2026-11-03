import ProtectedAction
import SwiftUI
import UIComponents
import WalletContext

/// Reuse with the existing ProtectedAction/UnlockVC authentication flow. It only renders the quote.
public struct PerpsTradeConfirmationHeader: ConfirmationContent {
    public let data: PerpsOrderReviewDisplayData

    public init(data: PerpsOrderReviewDisplayData) { self.data = data }

    public var body: some View {
        PerpsPositionSummaryView(token: data.token, direction: data.direction, leverage: data.leverage,
                                 margin: data.margin, previousMargin: data.mode.previous?.margin,
                                 showsPlus: data.mode.operation == .close, isEstimated: data.isEstimated,
                                 accessibilityPrefix: "perps.authentication")
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, minHeight: 238)
    }

    public var compactRepresentation: some View {
        HStack(spacing: 12) {
            TokenHeroView(token: data.token, size: 48, shouldShowChain: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(data.mode.title).textStyle(.bodyStrong)
                Text(amountDescription)
                    .textStyle(.body, content: data.margin.optionalAmount == nil ? .default : .technical)
            }
            Spacer(minLength: 0)
        }
    }

    private var amountDescription: String {
        guard data.margin.optionalAmount != nil else { return lang("Unavailable") }
        let previous = data.mode.previous.flatMap { previous in
            previous.margin.optionalAmount.map { _ in previous.margin.formatted(.defaultAdaptive) + " → " }
        } ?? ""
        return previous + (data.isEstimated ? "≈ " : "") + data.margin.formatted(.defaultAdaptive, showPlus: data.mode.operation == .close)
    }
}

import ProtectedAction
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

public struct PerpsWithdrawalConfirmationHeader: ConfirmationContent {
    private let amount: TokenAmount
    private let title: String
    private let description: String?
    private let accessibilityPrefix: String

    public init(amount: TokenAmount, title: String, description: String? = nil, accessibilityPrefix: String) {
        self.amount = amount
        self.title = title
        self.description = description
        self.accessibilityPrefix = accessibilityPrefix
    }

    public var body: some View {
        VStack(spacing: 12) {
            PerpsWithdrawalSummaryView(amount: amount, caption: description == nil ? title : nil,
                                       accessibilityPrefix: accessibilityPrefix)
            if let description {
                Text(description)
                    .font17h22()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, minHeight: 238)
    }

    public var compactRepresentation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TokenHeroView(token: amount.type, size: 48, shouldShowChain: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).textStyle(.bodyStrong)
                    Text(verbatim: amount.optionalAmount == nil ? lang("Unavailable") : amount.formatted(.defaultAdaptive))
                        .textStyle(.body, content: .technical)
                }
                Spacer(minLength: 0)
            }
            if let description {
                Text(description)
                    .textStyle(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PerpsWithdrawalSummaryView: View {
    let amount: TokenAmount
    var caption: String? = nil
    let accessibilityPrefix: String

    var body: some View {
        VStack(spacing: 0) {
            TokenHeroView(token: amount.type, size: 80, shouldShowChain: false)
                .accessibilityHidden(true)
                .padding(.bottom, 24)
            amountView
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier(accessibilityPrefix + ".receive")
            if let caption {
                Text(caption)
                    .font17h22()
                    .padding(.top, 12)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var amountView: some View {
        if amount.optionalAmount != nil {
            AmountText(
                amount: amount,
                format: .init(preset: .defaultAdaptive),
                integerFont: .compactRounded(ofSize: 34, weight: .bold),
                fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                symbolFont: .compactRounded(ofSize: 28, weight: .bold),
                integerColor: .label,
                fractionColor: abs(amount.doubleValue) >= 10 ? .air.secondaryLabel : .label,
                symbolColor: .air.secondaryLabel
            )
            .heroSensitiveData()
        } else {
            Text(verbatim: "—")
                .font(Font(UIFont.compactRounded(ofSize: 34, weight: .bold)))
        }
    }
}

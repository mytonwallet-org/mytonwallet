import SwiftUI
import WalletContext

/// The token a trade pays with or receives, styled like the native payment method control.
public struct TradePaymentRow<Icon: View>: View {
    let title: String
    let amount: String?
    let symbol: String
    let icon: Icon

    public init(title: String, amount: String?, symbol: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.amount = amount
        self.symbol = symbol
        self.icon = icon()
    }

    public var body: some View {
        HStack(spacing: 10) {
            icon
            Text(title)
                .textStyle(.bodyEmphasized)
                .foregroundStyle(Color.air.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if let amount {
                    Text(amount).foregroundStyle(Color.air.primaryLabel)
                }
                Text(symbol).foregroundStyle(Color.air.secondaryLabel)
            }
            .textStyle(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(Color.air.pickerBackground, in: .capsule)
    }
}

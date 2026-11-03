import SwiftUI
import WalletContext

public struct TradeConversionButton: View {
    let text: String
    let isStale: Bool
    let action: () -> Void

    public init(text: String, isStale: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.isStale = isStale
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(isStale ? 0.55 : 1)
                    .mask { LoadingShineMask(isActive: isStale) }
                Image("TokenTradeConverter", bundle: AirBundle)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 12, height: 16)
            }
            .textStyle(.supportingEmphasized)
            .foregroundStyle(Color.air.secondaryLabel)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.air.secondaryLabel.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang("Switch Amount Currency"))
        .accessibilityValue(text)
    }
}

public struct TradePaymentRow<Icon: View>: View {
    let title: String
    let amount: String?
    let symbol: String
    let badge: String?
    let isStale: Bool
    let titleColor: Color
    let action: (() -> Void)?
    let icon: Icon

    public init(title: String, amount: String?, symbol: String, badge: String? = nil, isStale: Bool = false,
                titleColor: Color = Color.air.primaryLabel,
                action: (() -> Void)? = nil, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.amount = amount
        self.symbol = symbol
        self.badge = badge
        self.isStale = isStale
        self.titleColor = titleColor
        self.action = action
        self.icon = icon()
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            icon
            Text(title)
                .textStyle(.bodyEmphasized)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if let amount {
                    Text(amount)
                        .foregroundStyle(Color.air.primaryLabel)
                        .opacity(isStale ? 0.55 : 1)
                        .mask { LoadingShineMask(isActive: isStale) }
                }
                Text(symbol).foregroundStyle(Color.air.secondaryLabel)
                if let badge {
                    Text(badge)
                        .textStyle(.badge)
                        .tracking(0.066)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .padding(.horizontal, 3)
                        .padding(.bottom, 1)
                        .frame(height: 14)
                        .background(Color.air.thumbBackground, in: .rect(cornerRadius: 4))
                        .fixedSize()
                }
                if action != nil {
                    Image("TokenTradeDropdown", bundle: AirBundle)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 10, height: 22)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
            }
            .textStyle(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(Color.air.pickerBackground, in: .capsule)
        .contentShape(.capsule)
    }
}

public struct TradeFractionButtons: View {
    let percentages: [Int]
    let showsPositiveSign: Bool
    let action: (Int) -> Void

    public init(percentages: [Int] = [25, 50, 100], showsPositiveSign: Bool = false, action: @escaping (Int) -> Void) {
        self.percentages = percentages
        self.showsPositiveSign = showsPositiveSign
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(percentages, id: \.self) { percentage in
                Button { action(percentage) } label: {
                    Text((showsPositiveSign && percentage > 0 ? "+" : "") + percentage.formatted(.percent.scale(1).locale(.forNumberFormatters)))
                        .textStyle(.bodyEmphasized)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.air.headerBackground, in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.air.primaryLabel)
                .accessibilityIdentifier("trade.fraction.\(percentage)")
            }
        }
    }
}

import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct SwapDetailsContainer<Content: View>: View {
    @Binding var isExpanded: Bool
    var content: Content

    init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        InsetSection(
            dividersInset: IOS_26_MODE_ENABLED ? 4 : 0,
            dividersTrailingInset: IOS_26_MODE_ENABLED ? 20 : 0,
            horizontalPadding: 0
        ) {
            header

            if isExpanded {
                content
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: isExpanded ? nil : S.sectionItemHeight, alignment: .top)
        .clipShape(.rect(cornerRadius: S.insetSectionCornerRadius))
        .tint(.accentColor)
        .animation(.spring(duration: isExpanded ? 0.45 : 0.3), value: isExpanded)
    }

    private var header: some View {
        Button(action: { isExpanded.toggle() }) {
            InsetCell(horizontalPadding: 16) {
                HStack {
                    Text(lang("Swap Details"))
                        .textCase(IOS_26_MODE_ENABLED ? nil : .uppercase)
                    Spacer()
                    Image.airBundle("RightArrowIcon")
                        .renderingMode(.template)
                        .rotationEffect(isExpanded ? .radians(-0.5 * .pi) : .radians(0.5 * .pi))
                }
                .textStyle(.sectionHeader)
                .tint(.air.secondaryLabel)
                .foregroundStyle(Color.air.secondaryLabel)
            }
            .frame(height: S.sectionItemHeight)
            .contentShape(.rect)
        }
        .buttonStyle(InsetButtonStyle())
    }
}

struct SwapExchangeRateRow: View {
    let exchangeRate: SwapRate?

    @ViewBuilder
    var body: some View {
        if let exchangeRate {
            SwapDetailCell {
                Text(lang("Exchange Rate"))
                    .foregroundStyle(Color.air.secondaryLabel)
            } value: {
                let priceAmount = DecimalAmount.fromDouble(exchangeRate.price, exchangeRate.fromToken)
                Text("\(exchangeRate.toToken.symbol) ≈ \(priceAmount.formatted(.compact))")
                    .textStyle(.body, content: .technical, scaling: .dynamic)
            }
        }
    }
}

struct SwapBlockchainFeeRow<Value: View>: View {
    let nativeToken: ApiToken?
    let feeDetails: ExplainedTransferFee?
    let value: Value

    init(
        nativeToken: ApiToken?,
        feeDetails: ExplainedTransferFee?,
        @ViewBuilder value: () -> Value
    ) {
        self.nativeToken = nativeToken
        self.feeDetails = feeDetails
        self.value = value()
    }

    var body: some View {
        SwapDetailCell {
            SwapBlockchainFeeLabel(nativeToken: nativeToken, feeDetails: feeDetails)
        } value: {
            value
        }
    }
}

struct SwapDetailCell<Label: View, Value: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder var label: Label
    @ViewBuilder var value: Value

    var body: some View {
        InsetCell {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: alignment, spacing: 0) {
                    label.fixedSize()
                    Spacer(minLength: 8)
                    value.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    label
                    value
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

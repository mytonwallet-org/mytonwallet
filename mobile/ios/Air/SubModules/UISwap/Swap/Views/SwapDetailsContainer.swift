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
        InsetSection(horizontalPadding: 0) {
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
            InsetCell {
                HStack(spacing: 0) {
                    Text(lang("Exchange Rate"))
                        .foregroundStyle(Color.air.secondaryLabel)
                    Spacer(minLength: 4)
                    let priceAmount = DecimalAmount.fromDouble(exchangeRate.price, exchangeRate.fromToken)
                    Text("\(exchangeRate.toToken.symbol) ≈ \(priceAmount.formatted(.compact))")
                        .textStyle(.body, content: .technical, scaling: .dynamic)
                }
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
        InsetDetailCell {
            SwapBlockchainFeeLabel(nativeToken: nativeToken, feeDetails: feeDetails)
        } value: {
            value
        }
    }
}

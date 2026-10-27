
import SwiftUI
import UIKit
import WalletCore
import WalletContext

public struct SwapOverviewView: View {
    
    var fromAmount: TokenAmount
    var toAmount: TokenAmount
    var toAmountIsEstimated: Bool
    var onTokenTapped: ((ApiToken) -> Void)?
    
    public init(fromAmount: TokenAmount, toAmount: TokenAmount, toAmountIsEstimated: Bool = false, onTokenTapped: ((ApiToken) -> Void)? = nil) {
        self.fromAmount = fromAmount
        self.toAmount = toAmount
        self.toAmountIsEstimated = toAmountIsEstimated
        self.onTokenTapped = onTokenTapped
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            iconsView
                .zIndex(1)
                .padding(.bottom, 24)
            minusView
                .padding(.bottom, 4)
                .padding(.top, 1)
            plusView
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
        .padding(.leading, 2)
    }
    
    @ViewBuilder
    var iconsView: some View {
        let fromToken = fromAmount.type
        let toToken = toAmount.type
        HStack(spacing: 0) {
            hero(for: fromToken)
                .frame(width: 64, height: 60, alignment: .leading)
            Image(systemName: "chevron.forward")
                .textStyle(.body, content: .technical)
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(width: 32, height: 32)
            hero(for: toToken)
                .frame(width: 64, height: 60, alignment: .leading)
                .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func hero(for token: ApiToken) -> some View {
        if TokenHeroView.showsDiamond(for: token) {
            TokenHeroView(token: token, size: 60)
        } else {
            Button { onTokenTapped?(token) } label: {
                TokenHeroView(token: token, size: 60)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var minusView: some View {
        let fromToken = fromAmount.type
        Button {
            onTokenTapped?(fromToken)
        } label: {
            let amount = DecimalAmount(-fromAmount.amount, fromToken)
            AmountText(
                amount: amount,
                format: .init(preset: .defaultAdaptive, showMinus: true, roundHalfUp: false),
                integerFont: .compactRounded(ofSize: 17, weight: .bold),
                fractionFont: .compactRounded(ofSize: 17, weight: .bold),
                symbolFont: .compactRounded(ofSize: 17, weight: .bold),
                integerColor: UIColor.label,
                fractionColor: .air.secondaryLabel,
                symbolColor: .air.secondaryLabel
            )
            .heroSensitiveData(maskSize: CGSize(width: 90, height: 18))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    var plusView: some View {
        let toToken = toAmount.type
        Button {
            onTokenTapped?(toToken)
        } label: {
            let amount = DecimalAmount(toAmount.amount, toToken)
            AmountText(
                amount: amount,
                format: .init(preset: .defaultAdaptive, showPlus: !toAmountIsEstimated, roundHalfUp: false, precision: toAmountIsEstimated ? .approximate : nil),
                integerFont: .compactRounded(ofSize: 34, weight: .bold),
                fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                symbolFont: .compactRounded(ofSize: 28, weight: .bold),
                integerColor: UIColor.label,
                fractionColor: .air.secondaryLabel,
                symbolColor: .air.secondaryLabel
            )
            .heroSensitiveData()
        }
        .buttonStyle(.plain)
    }
}

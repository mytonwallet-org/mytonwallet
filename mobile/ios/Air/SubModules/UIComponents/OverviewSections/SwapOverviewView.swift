
import SwiftUI
import UIKit
import WalletCore
import WalletContext

public struct SwapOverviewView: View {
    
    var fromAmount: TokenAmount
    var toAmount: TokenAmount
    var onTokenTapped: ((ApiToken) -> Void)?
    
    public init(fromAmount: TokenAmount, toAmount: TokenAmount, onTokenTapped: ((ApiToken) -> Void)? = nil) {
        self.fromAmount = fromAmount
        self.toAmount = toAmount
        self.onTokenTapped = onTokenTapped
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            iconsView
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
            Button {
                onTokenTapped?(fromToken)
            } label: {
                WUIIconViewToken(token: fromToken, isWalletView: false, showldShowChain: true, size: 60, chainSize: 22, chainBorderWidth: 1.5, chainBorderColor: WTheme.sheetBackground, chainHorizontalOffset: 6, chainVerticalOffset: 2)
                    .frame(width: 64, height: 60, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.forward")
                .font(.body)
                .foregroundStyle(Color(WTheme.secondaryLabel))
                .frame(width: 32, height: 32)
            Button {
                onTokenTapped?(toToken)
            } label: {
                WUIIconViewToken(token: toToken, isWalletView: false, showldShowChain: true, size: 60, chainSize: 22, chainBorderWidth: 1.5, chainBorderColor: WTheme.sheetBackground, chainHorizontalOffset: 6, chainVerticalOffset: 2)
                    .frame(width: 64, height: 60, alignment: .leading)
                    .padding(.leading, 4)
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
                format: .init(maxDecimals: 2),
                integerFont: .compactRounded(ofSize: 17, weight: .bold),
                fractionFont: .compactRounded(ofSize: 17, weight: .bold),
                symbolFont: .compactRounded(ofSize: 17, weight: .bold),
                integerColor: WTheme.primaryLabel,
                fractionColor: WTheme.secondaryLabel,
                symbolColor: WTheme.secondaryLabel
            )
            .sensitiveData(alignment: .center, cols: 10, rows: 2, cellSize: 9, theme: .adaptive, cornerRadius: 5)
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
                format: .init(maxDecimals: 2, showPlus: true),
                integerFont: .compactRounded(ofSize: 34, weight: .bold),
                fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                symbolFont: .compactRounded(ofSize: 28, weight: .bold),
                integerColor: WTheme.primaryLabel,
                fractionColor: WTheme.secondaryLabel,
                symbolColor: WTheme.secondaryLabel
            )
            .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 11, theme: .adaptive, cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}

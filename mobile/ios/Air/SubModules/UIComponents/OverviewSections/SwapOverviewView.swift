
import SwiftUI
import UIKit
import WalletCore
import WalletContext

public struct SwapOverviewView: View {
    
    var fromAmount: BigInt
    var fromToken: ApiToken
    var toAmount: BigInt
    var toToken: ApiToken
    var onTokenTapped: ((ApiToken) -> Void)?
    
    public init(fromAmount: BigInt, fromToken: ApiToken, toAmount: BigInt, toToken: ApiToken, onTokenTapped: ((ApiToken) -> Void)? = nil) {
        self.fromAmount = fromAmount
        self.fromToken = fromToken
        self.toAmount = toAmount
        self.toToken = toToken
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
        Button {
            onTokenTapped?(fromToken)
        } label: {
            let amount = DecimalAmount(-fromAmount, fromToken)
            AmountText(
                amount: amount,
                format: .init(maxDecimals: 2, showMinus: true),
                integerFont: .rounded(ofSize: 17, weight: .bold),
                fractionFont: .rounded(ofSize: 17, weight: .bold),
                symbolFont: .rounded(ofSize: 17, weight: .bold),
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
        Button {
            onTokenTapped?(toToken)
        } label: {
            let amount = DecimalAmount(toAmount, toToken)
            AmountText(
                amount: amount,
                format: .init(maxDecimals: 2, showPlus: true),
                integerFont: .rounded(ofSize: 34, weight: .bold),
                fractionFont: .rounded(ofSize: 28, weight: .bold),
                symbolFont: .rounded(ofSize: 28, weight: .bold),
                integerColor: WTheme.primaryLabel,
                fractionColor: WTheme.secondaryLabel,
                symbolColor: WTheme.secondaryLabel
            )
            .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 11, theme: .adaptive, cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}

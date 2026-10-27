
import Foundation
import SwiftUI
import WalletCore
import WalletContext

public struct AmountCell: View {
    
    var amount: BigInt
    var token: ApiToken
    var format: DecimalAmountFormatStyle<ApiToken>
    var isError: Bool
    
    public init(amount: BigInt, token: ApiToken, format: DecimalAmountFormatStyle<ApiToken> = .init(), isError: Bool = false) {
        self.amount = amount
        self.token = token
        self.format = format
        self.isError = isError
    }
    
    public var body: some View {
        InsetCell {
            HStack(spacing: 8) {
                icon
                text
            }
            .padding(.vertical, 3)
        }
    }
    
    
    @ViewBuilder
    var icon: some View {
        WUIIconViewToken(
            token: token,
            isWalletView: false,
            showldShowChain: true,
            size: 28,
            chainSize: 12,
            chainBorderWidth: 0.667,
            chainHorizontalOffset: 3,
            chainVerticalOffset: 1
        )
            .frame(width: 30, height: 28, alignment: .leading)

    }
    
    @ViewBuilder
    var text: some View {
        let amount = DecimalAmount(amount, token)
        AmountText(
            amount: amount,
            format: format,
            integerFont: WTypography.uiFont(.amount, content: .technical),
            fractionFont: WTypography.uiFont(.amountSecondary, content: .technical),
            symbolFont: WTypography.uiFont(.amountSecondary, content: .technical),
            integerColor: isError ? .air.error : UIColor.label,
            fractionColor: isError ? .air.error : UIColor.label,
            symbolColor: isError ? .air.error : .air.secondaryLabel
        )
    }
}

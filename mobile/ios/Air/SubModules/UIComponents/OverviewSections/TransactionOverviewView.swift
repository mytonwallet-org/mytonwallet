
import SwiftUI
import WalletContext
import WalletCore
import Perception

public struct TransactionOverviewView: View {
    
    var amount: BigInt
    var token: ApiToken
    var isOutgoing: Bool
    var text: String?
    var addressViewModel: AddressViewModel
    
    public init(amount: BigInt, token: ApiToken, isOutgoing: Bool, text: String?, addressViewModel: AddressViewModel) {
        self.amount = amount
        self.token = token
        self.isOutgoing = isOutgoing
        self.text = text
        self.addressViewModel = addressViewModel
    }
    
    public var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                iconView
                    .padding(.bottom, 16)
                amountView
                    .padding(.top, 1)
                    .padding(.bottom, 12)
                toView
            }
        }
    }
    
    @ViewBuilder
    var iconView: some View {
        WUIIconViewToken(
            token: token,
            isWalletView: false,
            showldShowChain: true,
            size: 60,
            chainSize: 22,
            chainBorderWidth: 1.5,
            chainBorderColor: WTheme.sheetBackground,
            chainHorizontalOffset: 6,
            chainVerticalOffset: 2
        )
            .frame(width: 60, height: 60)
    }
    
    @ViewBuilder
    var amountView: some View {
        let amount = DecimalAmount(isOutgoing ? -amount : amount, token)
        
        AmountText(
            amount: amount.roundedForDisplay,
            format: .init(showPlus: !isOutgoing, showMinus: isOutgoing),
            integerFont: .compactRounded(ofSize: 34, weight: .bold),
            fractionFont: .compactRounded(ofSize: 28, weight: .bold),
            symbolFont: .compactRounded(ofSize: 28, weight: .bold),
            integerColor: WTheme.primaryLabel,
            fractionColor: abs(amount.doubleValue) >= 10 ? WTheme.secondaryLabel : WTheme.primaryLabel,
            symbolColor: WTheme.secondaryLabel
        )
        .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 11, theme: .adaptive, cornerRadius: 10)
    }
    
    @ViewBuilder
    var toView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let text {
                Text(text)
                    .font17h22()
            }
            TappableAddress(account: AccountContext(source: .current), model: addressViewModel)
        }
    }
}

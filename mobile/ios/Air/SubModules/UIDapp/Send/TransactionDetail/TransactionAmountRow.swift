
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

struct TransactionAmountRow: View {
    
    var transfer: ApiDappTransfer
    
    var body: some View {
        InsetCell(verticalPadding: 0) {
            HStack(spacing: 16) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    text
                    subtitle
                }
                Spacer()
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .frame(minHeight: 60)
        }
    }
    
    @ViewBuilder
    var icon: some View {
        WUIIconViewToken(
            token: .TONCOIN,
            isWalletView: false,
            showldShowChain: true,
            size: 40,
            chainSize: 16,
            chainBorderWidth: 1.333,
            chainBorderColor: WTheme.groupedItem,
            chainHorizontalOffset: 2,
            chainVerticalOffset: 1
        )
        .frame(width: 40, height: 40, alignment: .leading)
    }
    
    @ViewBuilder
    var text: some View {
        let amount = TokenAmount(transfer.amount, .TONCOIN)
        AmountText(
            amount: amount,
            format: .init(maxDecimals: 4, showMinus: true),
            integerFont: .systemFont(ofSize: 16, weight: .medium),
            fractionFont: .systemFont(ofSize: 16, weight: .medium),
            symbolFont: .systemFont(ofSize: 16, weight: .medium),
            integerColor: WTheme.primaryLabel,
            fractionColor: WTheme.primaryLabel,
            symbolColor: WTheme.secondaryLabel,
            forceSymbolColor: true,
        )
    }
    
    @ViewBuilder
    var subtitle: some View {
        let toncoin = ApiToken.toncoin
        let baseCurrency = TokenStore.baseCurrency ?? .USD
        let amount = TokenAmount(transfer.amount, .toncoin).convertTo(baseCurrency, exchangeRate: toncoin.price ?? 0)
        AmountText(
            amount: amount,
            format: .init(maxDecimals: 4, showMinus: true),
            integerFont: .systemFont(ofSize: 14, weight: .regular),
            fractionFont: .systemFont(ofSize: 14, weight: .regular),
            symbolFont: .systemFont(ofSize: 14, weight: .regular),
            integerColor: WTheme.secondaryLabel,
            fractionColor: WTheme.secondaryLabel,
            symbolColor: WTheme.secondaryLabel,
            forceSymbolColor: true,
        )
    }
}


import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct TransactionAmountRow: View {
    
    var transfer: ApiDappTransfer
    var chain: ApiChain
    
    private var transferToken: ApiToken { transfer.getToken(chain: chain) }
    
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
            token: transferToken,
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
        let amount = TokenAmount(transfer.effectiveAmount, transferToken)
        AmountText(
            amount: amount,
            format: .init(maxDecimals: 4),
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
        let token = TokenStore.getNativeToken(chain: chain)
        let baseCurrency = TokenStore.baseCurrency
        let amount = TokenAmount(transfer.amount, token).convertTo(baseCurrency, exchangeRate: token.price ?? 0)
        AmountText(
            amount: amount,
            format: .init(maxDecimals: 4),
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


import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct TransactionFeeRow: View {
    
    var transfer: ApiDappTransfer
    var chain: ApiChain
    
    var body: some View {
        InsetCell(verticalPadding: 0) {
            HStack(spacing: 16) {
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
    var text: some View {
        let token = TokenStore.getNativeToken(chain: chain)
        let amount = TokenAmount(transfer.networkFee, token)
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
        let amount = TokenAmount(transfer.networkFee, token).convertTo(baseCurrency, exchangeRate: token.price ?? 0)
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

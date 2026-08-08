
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
            .foregroundStyle(Color.air.primaryLabel)
            .frame(minHeight: 60)
        }
    }
    
    @ViewBuilder
    var text: some View {
        let token = TokenStore.getNativeToken(chain: chain)
        let amount = TokenAmount(transfer.networkFee, token)
        AmountText(
            amount: amount,
            format: .init(preset: .fee),
            integerFont: WTypography.uiFont(.calloutEmphasized, content: .technical),
            fractionFont: WTypography.uiFont(.calloutEmphasized, content: .technical),
            symbolFont: WTypography.uiFont(.calloutEmphasized, content: .technical),
            integerColor: UIColor.label,
            fractionColor: UIColor.label,
            symbolColor: .air.secondaryLabel,
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
            format: .init(preset: .fee),
            integerFont: WTypography.uiFont(.supporting, content: .technical),
            fractionFont: WTypography.uiFont(.supporting, content: .technical),
            symbolFont: WTypography.uiFont(.supporting, content: .technical),
            integerColor: .air.secondaryLabel,
            fractionColor: .air.secondaryLabel,
            symbolColor: .air.secondaryLabel,
            forceSymbolColor: true,
        )
    }
}

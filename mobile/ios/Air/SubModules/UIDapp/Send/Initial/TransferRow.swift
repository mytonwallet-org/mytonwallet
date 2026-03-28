
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct TransferRow: View {
    
    var transfer: ApiDappTransfer
    var chain: ApiChain
    var action: (ApiDappTransfer) -> ()
    
    private var transferToken: ApiToken { transfer.getToken(chain: chain) }
    
    var body: some View {
        InsetButtonCell(alignment: .leading, verticalPadding: 0, action: { action(transfer) }) {
            HStack(spacing: 16) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    text
                    subtitle
                }
                Spacer()
                Image.airBundle("RightArrowIcon")
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            .foregroundStyle(Color.air.primaryLabel)
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
            chainBorderColor: .air.groupedItem,
            chainHorizontalOffset: 2,
            chainVerticalOffset: 1
        )
        .frame(width: 40, height: 40, alignment: .leading)
    }
        
    @ViewBuilder
    var text: some View {
        HStack(spacing: 8) {
            if transfer.isScam == true {
                Image.airBundle("ScamBadge")
            }
            let amount = TokenAmount(transfer.effectiveAmount, transferToken)
            AmountText(
                amount: amount,
                format: .init(maxDecimals: 4),
                integerFont: .systemFont(ofSize: 16, weight: .medium),
                fractionFont: .systemFont(ofSize: 16, weight: .medium),
                symbolFont: .systemFont(ofSize: 16, weight: .medium),
                integerColor: UIColor.label,
                fractionColor: UIColor.label,
                symbolColor: .air.secondaryLabel,
                forceSymbolColor: true,
            )
            .opacity(transfer.isScam == true ? 0.7 : 1)
        }
    }
    
    @ViewBuilder
    var subtitle: some View {
        let to = Text(lang("to"))
        let addr = Text(formatStartEndAddress(transfer.toAddress))
            .fontWeight(.semibold)
        Text("\(to) \(addr)")
            .font14h18()
            .foregroundStyle(Color.air.secondaryLabel)
    }
}

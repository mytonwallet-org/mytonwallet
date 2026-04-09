
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
    private var amountsText: String {
        var items: [String] = []

        if transfer.isNftTransferPayload {
            items.append("1 NFT")
        }

        items.append(contentsOf: transfer.displayedAmounts(chain: chain, includeNativeFee: true).map {
            $0.formatted(.defaultAdaptive, maxDecimals: 4)
        })

        return items.joined(separator: " + ")
    }
    
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
        if let nft = transfer.nftTransferPayload?.nft {
            NftImage(nft: nft, animateIfPossible: false)
                .frame(width: 40, height: 40, alignment: .leading)
                .clipShape(.rect(cornerRadius: 8))
        } else if transfer.isNftTransferPayload {
            Image(uiImage: UIImage.airBundle("NoNftImage"))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .padding(8)
                .frame(width: 40, height: 40, alignment: .leading)
                .foregroundStyle(Color.air.secondaryLabel)
                .background(Color.air.secondaryFill)
                .clipShape(.rect(cornerRadius: 8))
        } else {
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
    }
        
    @ViewBuilder
    var text: some View {
        HStack(spacing: 8) {
            if transfer.isScam == true {
                Image.airBundle("ScamBadge")
            }
            Text(amountsText)
                .font(.system(size: 16, weight: .medium))
                .opacity(transfer.isScam == true ? 0.7 : 1)
        }
    }
    
    @ViewBuilder
    var subtitle: some View {
        let to = Text(lang("to"))
        let addr = Text(formatStartEndAddress(transfer.displayedToAddress))
            .fontWeight(.semibold)
        Text("\(to) \(addr)")
            .font14h18()
            .foregroundStyle(Color.air.secondaryLabel)
    }
}


import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Dependencies

struct TransferRow: View {

    var transfer: ApiDappTransfer
    var chain: ApiChain
    var accountContext: AccountContext
    var action: (ApiDappTransfer) -> ()

    @Dependency(\.nftStore) private var nftStore

    private var transferToken: ApiToken { transfer.getToken(chain: chain) }
    private var nft: ApiNft? {
        guard let payload = transfer.nftTransferPayload else { return nil }
        if let nft = payload.nft {
            return nft
        }
        return nftStore.getNft(
            accountId: accountContext.accountId,
            nftId: ApiNft.id(chain: chain, address: payload.nftAddress)
        )?.nft
    }
    private var amountsText: String {
        var items: [String] = []

        if transfer.isNftTransferPayload {
            items.append(L10n.amountNfts(amount: 1))
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
                    addressLines
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
        if let nft {
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
                .textStyle(.calloutEmphasized, content: .technical)
                .opacity(transfer.isScam == true ? 0.7 : 1)
        }
    }
    
    @ViewBuilder
    var addressLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            makeAddressLine(label: lang("to"), address: transfer.toAddress)
            if let payloadRecipientAddress = transfer.payloadRecipientAddress {
                makeAddressLine(label: lang("Recipient"), address: payloadRecipientAddress)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 1)
        .foregroundStyle(Color.air.secondaryLabel)
    }

    private func makeAddressLine(label: String, address: String) -> some View {
        let labelText = Text(label).textStyle(.supporting)
        let addressText = Text(formatStartEndAddress(address))
            .textStyle(.supportingStrong, content: .technical)
        return Text("\(labelText) \(addressText)")
            .lineSpacing(2)
    }
}

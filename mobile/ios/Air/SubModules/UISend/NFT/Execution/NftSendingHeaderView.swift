import ProtectedAction
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct NftSendingHeaderView: ConfirmationContent {
    let confirmed: ConfirmedNftSend

    @ViewBuilder
    var body: some View {
        if confirmed.mode == .send, confirmed.nfts.count == 1 {
            NftOverviewView(
                nfts: confirmed.nfts,
                isOutgoing: true,
                text: lang("Send to") + " ",
                addressViewModel: confirmed.addressViewModel
            )
        } else {
            VStack(spacing: 16) {
                NftPreviewSection(
                    nfts: confirmed.nfts,
                    maxItems: 3,
                    maxRows: 3
                )
                if confirmed.mode == .send {
                    TappableAddressLine(
                        title: lang("Send to"),
                        account: AccountContext(
                            source: .accountId(confirmed.account.id)
                        ),
                        model: confirmed.addressViewModel
                    )
                }
            }
        }
    }

    @ViewBuilder
    var compactRepresentation: some View {
        if confirmed.nfts.count > 1 {
            CompactActionSummary {
                compactLabel
            }
        } else {
            CompactActionSummary {
                if let nft = confirmed.nfts.first {
                    NftImage(nft: nft, animateIfPossible: false)
                        .clipShape(.rect(cornerRadius: 5))
                }
            } label: {
                compactLabel
            }
        }
    }

    private var compactLabel: Text {
        let subject: String
        if confirmed.nfts.count == 1 {
            subject = confirmed.nfts[0].name?.nilIfEmpty
                ?? lang("%amount% NFTs", arg1: 1)
        } else {
            subject = lang(
                "%amount% NFTs",
                arg1: confirmed.nfts.count
            )
        }

        if confirmed.mode == .burn {
            return Text(lang("Burn") + " ")
                .textStyle(.body)
                + Text(subject)
                    .textStyle(.bodyEmphasized, content: .technical)
        }
        let destination = confirmed.addressViewModel.name
            ?? confirmed.addressViewModel.address.map {
                formatStartEndAddress($0)
            }
            ?? ""
        return Text(subject)
            .textStyle(.bodyEmphasized, content: .technical)
            + Text(" \(lang("to")) ")
                .textStyle(.body)
            + Text(destination)
                .textStyle(.bodyEmphasized, content: .technical)
    }
}

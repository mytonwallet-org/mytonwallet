import ProtectedAction
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct TokenSendingHeaderView: ConfirmationContent {
    let confirmed: ConfirmedTokenSend

    var body: some View {
        TransactionOverviewView(
            amount: confirmed.amount,
            token: confirmed.token,
            isOutgoing: true,
            text: lang("Send to") + " ",
            addressViewModel: confirmed.addressViewModel
        )
    }

    var compactRepresentation: some View {
        CompactActionSummary {
            WUIIconViewToken(
                token: confirmed.token,
                isWalletView: false,
                showldShowChain: false,
                size: 20,
                chainSize: 0,
                chainBorderWidth: 0,
                chainHorizontalOffset: 0,
                chainVerticalOffset: 0
            )
        } label: {
            destinationLabel
        }
    }

    private var destinationLabel: Text {
        let subject = TokenAmount(
            confirmed.amount,
            confirmed.token
        ).formatted(.defaultAdaptive)
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

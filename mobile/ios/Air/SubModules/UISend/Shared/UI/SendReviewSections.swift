import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct SendRecipientReviewSection: View {
    let accountContext: AccountContext
    let addressViewModel: AddressViewModel
    let isScam: Bool

    var body: some View {
        InsetSection {
            InsetCell {
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: 8
                ) {
                    if isScam {
                        Image.airBundle("ScamBadge")
                            .offset(y: 1)
                            .accessibilityLabel(lang("Scam"))
                    }
                    TappableAddressFull(
                        accountContext: accountContext,
                        model: addressViewModel,
                        compactAddressWithName: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            Text(lang("Recipient Address"))
        } footer: {}
    }
}

struct SendPayloadReviewSection: View {
    let comment: String
    let binaryPayload: String?
    let stateInit: String?
    let isMessageEncrypted: Bool
    let isAvailable: Bool

    var body: some View {
        let signingData = SendSigningData(
            binaryPayload: binaryPayload,
            stateInit: stateInit
        )
        if signingData.isPresent {
            SendSigningDataSection(signingData: signingData)
        } else if !comment.isEmpty && isAvailable {
            SendCommentReviewSection(
                comment: comment,
                isMessageEncrypted: isMessageEncrypted
            )
        }
    }
}

private struct SendCommentReviewSection: View {
    let comment: String
    let isMessageEncrypted: Bool

    var body: some View {
        InsetSection {
            InsetCell {
                Text(verbatim: comment)
                    .font17h22()
            }
        } header: {
            Text(
                isMessageEncrypted
                    ? lang("Encrypted Message")
                    : lang("Comment or Memo")
            )
        } footer: {}
            .padding(.top, -8)
    }
}

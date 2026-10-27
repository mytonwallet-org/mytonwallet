import Dependencies
import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct NftSendReviewView: View {
    let model: NftSendModel
    let confirmed: ConfirmedNftSend?
    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            let state = NftSendReviewState(
                model: model,
                confirmed: confirmed
            )
            InsetList {
                NftPreviewSection(nfts: state.nfts)
                if state.mode == .send {
                    SendRecipientReviewSection(
                        accountContext: accountContext,
                        addressViewModel: state.addressViewModel,
                        isScam: state.isScamRecipient
                    )
                }
                NftSendFeeReviewSection(
                    chain: state.chain,
                    fee: state.fee,
                    isFeeError: state.isFeeError
                )
                if state.mode == .send {
                    SendPayloadReviewSection(
                        comment: state.comment,
                        binaryPayload: nil,
                        stateInit: nil,
                        isMessageEncrypted: false,
                        isAvailable: state.isPayloadAvailable
                    )
                }
            }
        }
    }
}

private struct NftSendReviewState {
    let mode: NftSendMode
    let chain: ApiChain
    let nfts: [ApiNft]
    let fee: MFee?
    let isFeeError: Bool
    let addressViewModel: AddressViewModel
    let isScamRecipient: Bool
    let comment: String
    let isPayloadAvailable: Bool

    @MainActor
    init(
        model: NftSendModel,
        confirmed: ConfirmedNftSend?
    ) {
        if let confirmed {
            mode = confirmed.mode
            chain = confirmed.chain
            nfts = confirmed.nfts
            fee = confirmed.explainedFee?.realFee
            isFeeError = false
            addressViewModel = confirmed.addressViewModel
            isScamRecipient = confirmed.isScamRecipient
            comment = confirmed.submission.comment ?? ""
            isPayloadAvailable =
                confirmed.isTransferPayloadAvailable
        } else {
            mode = model.configuration.mode
            chain = model.configuration.chain
            nfts = model.configuration.nfts
            fee = model.showingFee
            isFeeError = model.hasInsufficientBalanceError
            addressViewModel = model.addressViewModel
            isScamRecipient = model.isScamRecipient
            comment = model.comment
            isPayloadAvailable =
                model.isTransferPayloadAvailable
        }
    }
}

private struct NftSendFeeReviewSection: View {
    let chain: ApiChain
    let fee: MFee?
    let isFeeError: Bool

    @Dependency(\.tokenStore) private var tokenStore

    private var feeText: String? {
        let nativeToken = tokenStore.getNativeToken(chain: chain)
        return fee?.toString(
            token: nativeToken,
            nativeToken: nativeToken
        )
    }

    var body: some View {
        if let feeText {
            InsetSection {
                InsetCell(verticalPadding: 16) {
                    Text(feeText)
                        .textStyle(.calloutEmphasized, content: .technical)
                        .foregroundStyle(isFeeError ? AnyShapeStyle(Color.air.error) : AnyShapeStyle(.secondary))
                }
            } header: {
                Text(lang("Fee"))
            }
        }
    }
}

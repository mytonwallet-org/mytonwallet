import Dependencies
import Foundation
import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct TokenSendReviewView: View {
    let model: TokenSendModel
    let confirmed: ConfirmedTokenSend?
    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            InsetList {
                SendRecipientReviewSection(
                    accountContext: accountContext,
                    addressViewModel:
                        confirmed?.addressViewModel
                        ?? model.addressViewModel,
                    isScam:
                        confirmed?.isScamRecipient
                        ?? model.isScamRecipient
                )
                if let confirmed {
                    TokenSendAmountReviewSection(confirmed: confirmed)
                    TokenSendPayloadReviewSection(
                        payload: confirmed.submission.payload,
                        stateInit: confirmed.submission.stateInit
                    )
                } else {
                    TokenSendAmountReviewSection(model: model)
                    SendPayloadReviewSection(
                        comment: model.comment,
                        binaryPayload: model.binaryPayload,
                        stateInit: model.configuration.stateInit,
                        isMessageEncrypted:
                            model.isMessageEncrypted,
                        isAvailable: model.isTransferPayloadAvailable
                    )
                }
            }
        }
    }
}

private struct TokenSendAmountReviewSection: View {
    let amount: BigInt?
    let token: ApiToken
    let amountInBaseCurrency: BaseCurrencyAmount?
    let fee: MFee?
    let explainedFee: ExplainedTransferFee?
    let isFeeError: Bool

    @Dependency(\.tokenStore) private var tokenStore

    init(model: TokenSendModel) {
        self.amount = model.amount
        self.token = model.token
        self.amountInBaseCurrency = model.amountInBaseCurrency.map {
            BaseCurrencyAmount($0, model.baseCurrency)
        }
        self.fee = model.showingFee
        self.explainedFee = model.explainedFee
        self.isFeeError = model.hasInsufficientFee
    }

    init(confirmed: ConfirmedTokenSend) {
        self.amount = confirmed.amount
        self.token = confirmed.token
        self.amountInBaseCurrency = confirmed.amountInBaseCurrency
        self.fee = confirmed.explainedFee?.realFee
        self.explainedFee = confirmed.explainedFee
        self.isFeeError = false
    }

    var body: some View {
        if let amount {
            InsetSection {
                AmountCell(amount: amount, token: token)
            } header: {
                Text(lang("Amount"))
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    if let amountInBaseCurrency {
                        Text(
                            amount: amountInBaseCurrency,
                            format: .init()
                        )
                        .textStyle(.footnote, content: .technical)
                    }
                    Spacer()
                    FeeView(
                        token: token,
                        nativeToken: tokenStore.getNativeToken(
                            chain: token.chain
                        ),
                        fee: fee,
                        explainedTransferFee: explainedFee,
                        includeLabel: true,
                        isError: isFeeError,
                        textStyle: .footnote
                    )
                }
            }
        }
    }
}

private struct TokenSendPayloadReviewSection: View {
    let payload: AnyTransferPayload?
    let stateInit: String?

    var body: some View {
        switch payload {
        case .comment(let text, let shouldEncrypt):
            SendPayloadReviewSection(
                comment: text,
                binaryPayload: nil,
                stateInit: stateInit,
                isMessageEncrypted: shouldEncrypt == true,
                isAvailable: true
            )
        case .base64(let data):
            SendPayloadReviewSection(
                comment: "",
                binaryPayload: data,
                stateInit: stateInit,
                isMessageEncrypted: false,
                isAvailable: true
            )
        case .binary(let data):
            SendPayloadReviewSection(
                comment: "",
                binaryPayload: Data(data).base64EncodedString(),
                stateInit: stateInit,
                isMessageEncrypted: false,
                isAvailable: true
            )
        case nil:
            SendPayloadReviewSection(
                comment: "",
                binaryPayload: nil,
                stateInit: stateInit,
                isMessageEncrypted: false,
                isAvailable: false
            )
        }
    }
}

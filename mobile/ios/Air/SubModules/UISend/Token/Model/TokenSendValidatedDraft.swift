import WalletContext
import WalletCore

struct TokenSendDieselQuote: Equatable, Sendable {
    let status: DieselStatus?
    let tokenAmount: BigInt?
    let transaction: String?
}

struct TokenSendValidatedDraft: Equatable, Sendable {
    let recipient: SendValidatedRecipient
    let explainedFee: ExplainedTransferFee?
    let requiresMemo: Bool
    let diesel: TokenSendDieselQuote?

    init(
        recipient: SendValidatedRecipient,
        explainedFee: ExplainedTransferFee?,
        requiresMemo: Bool,
        diesel: TokenSendDieselQuote?
    ) {
        self.recipient = recipient
        self.explainedFee = explainedFee
        self.requiresMemo = requiresMemo
        self.diesel = diesel
    }

    init(apiDraft: ApiCheckTransactionDraftResult) {
        self.init(
            recipient: SendValidatedRecipient(
                resolvedAddress: apiDraft.resolvedAddress,
                addressName: apiDraft.addressName,
                isScam: apiDraft.isScam == true,
                error: apiDraft.error
            ),
            explainedFee: apiDraft.explainedFee,
            requiresMemo: !isSendAddressDraftError(apiDraft.error)
                && (apiDraft.isMemoRequired ?? false),
            diesel: apiDraft.diesel.map {
                TokenSendDieselQuote(
                    status: $0.status,
                    tokenAmount: $0.tokenAmount,
                    transaction: $0.transaction
                )
            }
        )
    }

    fileprivate func makeSubmission(
        for request: TokenSendDraftRequest
    ) throws -> TokenSendSubmission {
        guard let resolvedAddress = recipient.resolvedAddress else {
            throw DisplayError(text: lang("Address not resolved"))
        }
        return TokenSendSubmission(
            accountId: request.accountId,
            asset: request.asset,
            amount: request.amount,
            payload: request.payload,
            stateInit: request.stateInit,
            resolvedAddress: resolvedAddress,
            diesel: diesel
        )
    }
}

extension TokenSendDraftSnapshot {
    func makeSubmission() throws -> TokenSendSubmission {
        try draft.makeSubmission(for: request)
    }
}

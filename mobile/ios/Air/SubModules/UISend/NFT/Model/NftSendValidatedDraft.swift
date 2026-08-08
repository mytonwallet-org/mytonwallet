import WalletContext
import WalletCore

struct NftSendValidatedDraft: Equatable, Sendable {
    let recipient: SendValidatedRecipient
    let explainedFee: ExplainedTransferFee?
    let requiresMemo: Bool
    let realNativeFee: BigInt?

    init(
        recipient: SendValidatedRecipient,
        explainedFee: ExplainedTransferFee?,
        requiresMemo: Bool,
        realNativeFee: BigInt?
    ) {
        self.recipient = recipient
        self.explainedFee = explainedFee
        self.requiresMemo = requiresMemo
        self.realNativeFee = realNativeFee
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
            realNativeFee: apiDraft.realNativeFee
        )
    }

    func makeSubmission(
        for request: NftSendDraftRequest
    ) throws -> NftSendSubmission {
        guard let resolvedAddress = recipient.resolvedAddress else {
            throw DisplayError(text: lang("Address not resolved"))
        }
        return NftSendSubmission(
            accountId: request.accountId,
            chain: request.chain,
            nfts: request.nfts,
            comment: request.comment,
            mode: request.mode,
            resolvedAddress: resolvedAddress,
            totalRealFee: realNativeFee
        )
    }
}

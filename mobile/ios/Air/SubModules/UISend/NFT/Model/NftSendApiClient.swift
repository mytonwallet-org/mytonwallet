import WalletContext
import WalletCore

struct NftSendSubmissionRequest: Sendable {
    let chain: ApiChain
    let accountId: String
    let enclaveToken: EnclaveToken?
    let nfts: [ApiNft]
    let toAddress: String
    let comment: String?
    let totalRealFee: BigInt?
    let isNftBurn: Bool
}

struct NftSendApiClient: Sendable {
    let checkDraft: @Sendable (
        _ chain: ApiChain,
        _ options: ApiCheckNftTransferDraftOptions
    ) async throws -> ApiCheckTransactionDraftResult

    let submit: @Sendable (
        _ request: NftSendSubmissionRequest
    ) async throws -> ApiSubmitNftTransfersResult

    static let live = Self(
        checkDraft: { chain, options in
            try await Api.checkNftTransferDraft(
                chain: chain,
                options: options
            )
        },
        submit: { request in
            try await Api.submitNftTransfers(
                chain: request.chain,
                accountId: request.accountId,
                enclaveToken: request.enclaveToken,
                nfts: request.nfts,
                toAddress: request.toAddress,
                comment: request.comment,
                totalRealFee: request.totalRealFee,
                isNftBurn: request.isNftBurn
            )
        }
    )
}

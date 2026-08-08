import WalletContext
import WalletCore

struct TokenSendApiClient: Sendable {
    let checkDraft: @Sendable (
        _ chain: ApiChain,
        _ options: ApiCheckTransactionDraftOptions
    ) async throws -> ApiCheckTransactionDraftResult

    let submit: @Sendable (
        _ chain: ApiChain,
        _ options: ApiSubmitTransferOptions
    ) async throws -> ApiSubmitTransferResult

    static let live = Self(
        checkDraft: { chain, options in
            try await Api.checkTransactionDraft(
                chain: chain,
                options: options
            )
        },
        submit: { chain, options in
            try await Api.submitTransfer(
                chain: chain,
                options: options
            )
        }
    )
}

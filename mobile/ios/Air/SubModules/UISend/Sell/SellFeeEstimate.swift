import WalletContext
import WalletCore

enum SellFeeEstimate {
    static func maximumAmount(
        accountId: String,
        tokenSlug: String,
        chain: ApiChain,
        balance: BigInt,
        checkDraft: @Sendable (ApiChain, ApiCheckTransactionDraftOptions) async throws -> ApiCheckTransactionDraftResult = { chain, options in
            try await Api.checkTransactionDraft(chain: chain, options: options)
        }
    ) async throws -> BigInt? {
        let config = getChainConfig(chain: chain)
        if config.canTransferFullNativeBalance {
            return balance
        }
        let draft = try await checkDraft(chain, .init(
            accountId: accountId,
            toAddress: config.feeCheckAddress,
            amount: balance,
            payload: nil,
            stateInit: nil,
            tokenAddress: nil,
            allowGasless: nil
        ))
        if let error = draft.error {
            // A full-balance probe can still provide the fee needed to reduce the amount.
            if error != .insufficientBalance || draft.explainedFee?.fullFee == nil {
                throw error
            }
        }
        guard let fee = draft.explainedFee, let fullFee = fee.fullFee else {
            throw ApiAnyDisplayError.serverError
        }
        return getMaxTransferAmount(.init(
            tokenBalance: balance,
            tokenSlug: tokenSlug,
            fullFee: fullFee.terms,
            canTransferFullBalance: fee.canTransferFullBalance
        ))
    }
}

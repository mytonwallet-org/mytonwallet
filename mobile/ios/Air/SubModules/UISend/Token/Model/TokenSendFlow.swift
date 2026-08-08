import ProtectedAction
import WalletContext
import WalletCore

struct TokenSendAsset: Equatable, Hashable, Sendable {
    let slug: String
    let chain: ApiChain
    let tokenAddress: String?

    init(_ token: ApiToken) {
        self.slug = token.slug
        self.chain = token.chain
        self.tokenAddress = token.tokenAddress
    }
}

struct TokenSendDraftRequest: Equatable, Hashable, Sendable {
    let accountId: String
    let address: String
    let asset: TokenSendAsset
    let amount: BigInt
    let payload: AnyTransferPayload?
    let stateInit: String?
}

struct TokenSendFeeQuoteRequest: Equatable, Hashable, Sendable {
    let accountId: String
    let asset: TokenSendAsset
}

struct TokenSendSubmission: Sendable {
    let accountId: String
    let asset: TokenSendAsset
    let amount: BigInt
    let payload: AnyTransferPayload?
    let stateInit: String?
    let resolvedAddress: String
    let diesel: TokenSendDieselQuote?
}

struct TokenSendFlow: Sendable {
    private let api: TokenSendApiClient

    init(api: TokenSendApiClient = .live) {
        self.api = api
    }

    func validateDraft(
        _ request: TokenSendDraftRequest
    ) async throws -> TokenSendValidatedDraft {
        let options = ApiCheckTransactionDraftOptions(
            accountId: request.accountId,
            toAddress: request.address,
            amount: request.amount,
            payload: request.payload,
            stateInit: request.stateInit,
            tokenAddress: request.asset.tokenAddress,
            allowGasless: true
        )
        let draft = try await api.checkDraft(
            request.asset.chain,
            options
        )
        let validatedDraft = TokenSendValidatedDraft(apiDraft: draft)
        try validateSendDraftError(draft.error)
        return validatedDraft
    }

    func estimateFee(
        _ request: TokenSendFeeQuoteRequest
    ) async throws -> ExplainedTransferFee? {
        let feeCheckAddress = getChainConfig(
            chain: request.asset.chain
        ).feeCheckAddress
        guard !feeCheckAddress.isEmpty else { return nil }
        let draft = try await api.checkDraft(
            request.asset.chain,
            ApiCheckTransactionDraftOptions(
                accountId: request.accountId,
                toAddress: feeCheckAddress,
                amount: nil,
                payload: nil,
                stateInit: nil,
                tokenAddress: request.asset.tokenAddress,
                allowGasless: false
            )
        )
        return draft.explainedFee
    }

    func submit(
        _ submission: TokenSendSubmission,
        enclaveToken: EnclaveToken?,
        explainedFee: ExplainedTransferFee?
    ) async throws -> SendSubmissionResult {
        let options = try makeTransferOptions(
            submission: submission,
            enclaveToken: enclaveToken,
            explainedFee: explainedFee
        )
        let result = try await api.submit(
            submission.asset.chain,
            options
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(
                error: error,
                context: result
            )
        }
        return SendSubmissionResult(
            activityIds: [result.activityId].compactMap { $0 },
            mfaRequestHash: result.mfaRequestHash
        )
    }

    @MainActor
    func ledgerOperation(
        _ submission: TokenSendSubmission,
        explainedFee: ExplainedTransferFee?
    ) async throws -> HardwareOperation<SendSubmissionResult> {
        let options = try makeTransferOptions(
            submission: submission,
            enclaveToken: nil,
            explainedFee: explainedFee
        )
        return .single {
            let result = try await api.submit(
                submission.asset.chain,
                options
            )
            if let error = result.error {
                throw SdkError.apiReturnedError(
                    error: error,
                    context: result
                )
            }
            if result.mfaRequestHash != nil {
                throw DisplayError(text: lang("Unexpected error"))
            }
            return ActionSubmissionReceipt(
                activityIds: [result.activityId].compactMap { $0 }
            )
        }
    }

    private func makeTransferOptions(
        submission: TokenSendSubmission,
        enclaveToken: EnclaveToken?,
        explainedFee: ExplainedTransferFee?
    ) throws -> ApiSubmitTransferOptions {
        let diesel = submission.diesel
        return ApiSubmitTransferOptions(
            accountId: submission.accountId,
            toAddress: submission.resolvedAddress,
            amount: submission.amount,
            payload: submission.payload,
            stateInit: submission.stateInit,
            tokenAddress: submission.asset.tokenAddress,
            realFee: explainedFee?.realFee?.nativeSum,
            isGasless: explainedFee?.isGasless,
            dieselAmount: diesel?.tokenAmount,
            isGaslessWithStars: diesel?.status == .starsFee,
            gaslessTransaction: diesel?.transaction,
            enclaveToken: enclaveToken,
            fee: explainedFee?.fullFee?.nativeSum,
            noFeeCheck: nil
        )
    }
}

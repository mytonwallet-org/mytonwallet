import Foundation
import WalletCore
import WalletContext

@MainActor
struct SwapCexSupport {
    var createTransaction: (String, EnclaveToken, ApiSwapBuildRequest) async throws -> ApiSwapCexCreateTransactionResult = {
        try await Api.swapCexCreateTransaction(accountId: $0, enclaveToken: $1, request: $2)
    }
    var submit: (ApiChain, ApiSubmitTransferOptions, String) async throws -> ApiSwapSubmitResult = {
        try await Api.swapCexSubmit(chain: $0, options: $1, swapId: $2)
    }

    func swapCexCreateTransaction(
        accountId: String,
        sellingToken: ApiToken,
        request: ApiSwapBuildRequest,
        shouldTransfer: Bool,
        enclaveToken: EnclaveToken
    ) async throws -> SwapExecutionResult {
        // Creating an exchange order allocates a deposit address but does not send funds.
        let (createResult, options) = try await withNotSubmitted {
            let result = try await createTransaction(accountId, enclaveToken, request)
            let options = shouldTransfer ? try Self.makeTransferOptions(
                accountId: accountId,
                sellingToken: sellingToken,
                request: request,
                createResult: result,
                enclaveToken: enclaveToken
            ) : nil
            return (result, options)
        }
        guard let options else {
            return SwapExecutionResult(activity: createResult.activity, swapId: nil, mfaRequestHash: nil)
        }

        let result = try await submit(sellingToken.chain, options, createResult.swap.id)
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return SwapExecutionResult(activity: nil, swapId: createResult.swap.id, mfaRequestHash: result.mfaRequestHash)
    }

    private static func makeTransferOptions(
        accountId: String,
        sellingToken: ApiToken,
        request: ApiSwapBuildRequest,
        createResult: ApiSwapCexCreateTransactionResult,
        enclaveToken: EnclaveToken
    ) throws -> ApiSubmitTransferOptions {
        guard let toAddress = createResult.swap.cex?.payinAddress else {
            throw SdkError.unexpected(message: "Missing payin address")
        }
        guard let networkFee = createResult.swap.networkFee else {
            throw SdkError.unexpected(message: "Missing network fee", context: createResult)
        }
        let payload = try makeDepositMemoPayload(
            cexLabel: createResult.swap.cexLabel ?? request.cexLabel,
            memo: createResult.swap.cex?.payinExtraId?.nilIfEmpty,
            sourceChain: sellingToken.chain,
            createResult: createResult
        )
        return ApiSubmitTransferOptions(
            accountId: accountId,
            toAddress: toAddress,
            amount: createResult.swap.fromAmount.bigintAmount(decimals: sellingToken.decimals),
            payload: payload,
            stateInit: nil,
            tokenAddress: sellingToken.tokenAddress,
            realFee: nil,
            isGasless: false,
            dieselAmount: nil,
            isGaslessWithStars: nil,
            gaslessTransaction: nil,
            enclaveToken: enclaveToken,
            fee: networkFee.bigintAmount(decimals: sellingToken.chain.nativeToken.decimals),
            noFeeCheck: nil
        )
    }

    private static func makeDepositMemoPayload(
        cexLabel: ApiSwapCexLabel?,
        memo: String?,
        sourceChain: ApiChain,
        createResult: ApiSwapCexCreateTransactionResult
    ) throws -> AnyTransferPayload? {
        guard cexLabel == .nearIntents, let memo else {
            return nil
        }

        guard canAutoSubmitDepositMemo(sourceChain) else {
            throw SdkError.unexpected(message: "Unsupported auto-submitted deposit memo chain", context: createResult)
        }

        return .comment(text: memo, shouldEncrypt: false)
    }

    private static func canAutoSubmitDepositMemo(_ chain: ApiChain) -> Bool {
        chain == .ton || chain == .solana
    }
}

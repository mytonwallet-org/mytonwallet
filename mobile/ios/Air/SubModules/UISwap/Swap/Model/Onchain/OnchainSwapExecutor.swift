import WalletCore
import WalletContext

@MainActor struct OnchainSwapExecutor {
    var buildTransfer: (String, EnclaveToken, ApiSwapBuildRequest) async throws -> ApiSwapBuildResponse = {
        try await Api.swapBuildTransfer(accountId: $0, enclaveToken: $1, request: $2)
    }
    var submit: (ApiChain, String, EnclaveToken, [ApiSwapTransfer]?, ApiSwapHistoryItem, Bool?, String?, [ApiEvmSwapCall]?, ApiEvmSwapTransactionRequest?, Bool?) async throws -> ApiSwapSubmitResult = {
        try await Api.swapSubmit(chain: $0, accountId: $1, enclaveToken: $2, transfers: $3, historyItem: $4, isGasless: $5, transaction: $6, calls: $7, transactionRequest: $8, needsBatch: $9)
    }

    func performSwap(
        swapEstimate: ApiSwapDexEstimateResponse?,
        swapMode: ApiSwapMode,
        confirmation: SwapConfirmationAmounts,
        maxAmount: BigInt?,
        slippage: Double,
        account: SwapAccountSnapshot,
        enclaveToken: EnclaveToken
    ) async throws -> SwapExecutionResult {
        let prepared = try await withNotSubmitted { try await prepare(
            swapEstimate: swapEstimate,
            swapMode: swapMode,
            confirmation: confirmation,
            maxAmount: maxAmount,
            slippage: slippage,
            account: account,
            enclaveToken: enclaveToken
        ) }

        let historyItem = ApiSwapHistoryItem.makeFrom(
            swapBuildRequest: prepared.request,
            swapId: prepared.swapId
        )
        let result = try await submit(
            prepared.chain,
            account.id,
            enclaveToken,
            prepared.transferData.transfers,
            historyItem,
            prepared.shouldTryDiesel,
            prepared.transferData.transaction,
            prepared.transferData.calls,
            prepared.transferData.transactionRequest,
            prepared.transferData.needsBatch ?? prepared.request.needsBatch
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return SwapExecutionResult(activity: nil, swapId: result.swapId, mfaRequestHash: result.mfaRequestHash)
    }

    /// Everything that happens before the swap is submitted, so that a failure here is known to leave
    /// the chain untouched.
    private func prepare(
        swapEstimate: ApiSwapDexEstimateResponse?,
        swapMode: ApiSwapMode,
        confirmation: SwapConfirmationAmounts,
        maxAmount: BigInt?,
        slippage: Double,
        account: SwapAccountSnapshot,
        enclaveToken: EnclaveToken
    ) async throws -> PreparedOnchainSwap {
        guard let swapEstimate else {
            throw SdkError.unexpected(message: "Missing swap estimate")
        }
        guard let fromAddress = account.getAddress(chain: confirmation.selling.token.chain) else {
            throw SdkError.unexpected(message: "Missing account address")
        }
        guard let historyAddress = account.crosschainIdentifyingFromAddress else {
            throw SdkError.unexpected(message: "Missing TON history address")
        }
        let validationInput = SwapValidationInput(
            sellingToken: confirmation.selling.token,
            buyingToken: confirmation.buying.token,
            sellingAmount: confirmation.selling.amount,
            maxAmount: maxAmount,
            swapType: .onChain
        )
        let shouldTryDiesel = OnchainSwapValidator().shouldTryDiesel(
            input: validationInput,
            swapEstimate: swapEstimate,
            account: account
        )
        let swapBuildRequest = ApiSwapBuildRequest(
            from: swapEstimate.from,
            to: swapEstimate.to,
            fromAddress: fromAddress,
            historyAddress: historyAddress,
            dexLabel: swapEstimate.dexLabel,
            dexRouterLabel: swapEstimate.dexRouterLabel,
            fromAmount: swapEstimate.fromAmount,
            toAmount: swapEstimate.toAmount,
            toMinAmount: swapEstimate.toMinAmount,
            slippage: slippage,
            shouldTryDiesel: shouldTryDiesel,
            swapVersion: nil,
            swapMode: swapMode,
            walletVersion: account.version,
            routes: swapEstimate.routes,
            toAddress: account.getAddress(chain: confirmation.buying.token.chain),
            networkFee: swapEstimate.realNetworkFee,
            swapFee: swapEstimate.swapFee,
            ourFee: swapEstimate.ourFee,
            dieselFee: swapEstimate.dieselFee,
            needsBatch: swapEstimate.needsBatch
        )
        let transferData = try await buildTransfer(account.id, enclaveToken, swapBuildRequest)
        if let error = transferData.error {
            throw SdkError.apiReturnedError(error: error.rawValue, context: transferData)
        }
        guard let swapId = transferData.id, let chain = transferData.chain else {
            throw SdkError.unexpected(message: "Invalid swap build response", context: transferData)
        }
        return PreparedOnchainSwap(
            request: swapBuildRequest,
            transferData: transferData,
            shouldTryDiesel: shouldTryDiesel,
            chain: chain,
            swapId: swapId
        )
    }
}

struct PreparedOnchainSwap {
    let request: ApiSwapBuildRequest
    let transferData: ApiSwapBuildResponse
    let shouldTryDiesel: Bool
    let chain: ApiChain
    let swapId: String
}

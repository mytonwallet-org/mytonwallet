import WalletCore
import WalletContext

@MainActor struct OnchainSwapExecutor {
    var buildTransfer: (String, EnclaveToken, ApiSwapBuildRequest) async throws -> ApiSwapBuildResponse = {
        try await Api.swapBuildTransfer(accountId: $0, enclaveToken: $1, request: $2)
    }
    var submit: (ApiChain, String, EnclaveToken, [ApiSwapTransfer]?, ApiSwapHistoryItem, Bool?, String?, [ApiEvmSwapCall]?, Bool?) async throws -> ApiSwapSubmitResult = {
        try await Api.swapSubmit(chain: $0, accountId: $1, enclaveToken: $2, transfers: $3, historyItem: $4, isGasless: $5, transaction: $6, calls: $7, needsApprove: $8)
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
            networkFee: swapEstimate.realNetworkFee,
            swapFee: swapEstimate.swapFee,
            ourFee: swapEstimate.ourFee,
            dieselFee: swapEstimate.dieselFee,
            needsApprove: swapEstimate.needsApprove
        )
        let transferData = try await buildTransfer(account.id, enclaveToken, swapBuildRequest)
        if let error = transferData.error {
            throw SdkError.apiReturnedError(error: error.rawValue, context: transferData)
        }
        guard let swapId = transferData.id, let chain = transferData.chain else {
            throw SdkError.unexpected(message: "Invalid swap build response", context: transferData)
        }
        let historyItem = ApiSwapHistoryItem.makeFrom(swapBuildRequest: swapBuildRequest, swapId: swapId)
        let result = try await submit(
            chain,
            account.id,
            enclaveToken,
            transferData.transfers,
            historyItem,
            shouldTryDiesel,
            transferData.transaction,
            transferData.calls,
            swapBuildRequest.needsApprove
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return SwapExecutionResult(activity: nil, swapId: result.swapId, mfaRequestHash: result.mfaRequestHash)
    }
}

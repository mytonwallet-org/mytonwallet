import WalletCore
import WalletContext

@MainActor struct OnchainSwapExecutor {
    func performSwap(
        swapEstimate: ApiSwapEstimateResponse?,
        confirmation: SwapConfirmationAmounts,
        maxAmount: BigInt?,
        slippage: Double,
        account: SwapAccountSnapshot,
        passcode: String
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
        guard let fromAmount = swapEstimate.fromAmount, let toAmount = swapEstimate.toAmount else {
            throw SdkError.unexpected(message: "Missing swap estimate amount", context: swapEstimate)
        }

        let swapBuildRequest = ApiSwapBuildRequest(
            from: swapEstimate.from,
            to: swapEstimate.to,
            fromAddress: fromAddress,
            historyAddress: historyAddress,
            dexLabel: swapEstimate.dexLabel,
            fromAmount: fromAmount,
            toAmount: toAmount,
            toMinAmount: swapEstimate.toMinAmount,
            slippage: slippage,
            shouldTryDiesel: shouldTryDiesel,
            swapVersion: nil,
            walletVersion: account.version,
            routes: swapEstimate.routes,
            networkFee: swapEstimate.realNetworkFee,
            swapFee: swapEstimate.swapFee,
            ourFee: swapEstimate.ourFee,
            dieselFee: swapEstimate.dieselFee
        )
        let transferData = try await Api.swapBuildTransfer(accountId: account.id, password: passcode, request: swapBuildRequest)
        if let error = transferData.error {
            throw SdkError.apiReturnedError(error: error.rawValue, context: transferData)
        }
        guard let swapId = transferData.id, let chain = transferData.chain else {
            throw SdkError.unexpected(message: "Invalid swap build response", context: transferData)
        }
        let historyItem = ApiSwapHistoryItem.makeFrom(swapBuildRequest: swapBuildRequest, swapId: swapId)
        let result = try await Api.swapSubmit(
            chain: chain,
            accountId: account.id,
            password: passcode,
            transfers: transferData.transfers,
            historyItem: historyItem,
            isGasless: shouldTryDiesel,
            transaction: transferData.transaction
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return SwapExecutionResult(activity: nil, swapId: result.swapId, mfaRequestHash: result.mfaRequestHash)
    }
}

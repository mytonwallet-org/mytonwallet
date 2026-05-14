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
    ) async throws {
        guard let swapEstimate else {
            throw BridgeCallError.customMessage("Missing swap estimate", nil)
        }
        guard let fromAddress = account.getAddress(chain: confirmation.selling.token.chain) else {
            throw BridgeCallError.customMessage("Missing account address", nil)
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
            dexLabel: swapEstimate.dexLabel,
            fromAmount: swapEstimate.fromAmount ?? .zero,
            toAmount: swapEstimate.toAmount ?? .zero,
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
        let historyItem = ApiSwapHistoryItem.makeFrom(swapBuildRequest: swapBuildRequest, swapTransferData: transferData)
        let result = try await Api.swapSubmit(accountId: account.id, password: passcode, transfers: transferData.transfers, historyItem: historyItem, isGasless: shouldTryDiesel)
        if let error = result.error {
            throw BridgeCallError(message: error, payload: result)
        }
    }
}

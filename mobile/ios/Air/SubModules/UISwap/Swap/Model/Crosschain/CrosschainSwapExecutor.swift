import WalletCore

@MainActor struct CrosschainSwapExecutor {
    func performSwap(
        swapType: SwapType,
        swapEstimate: ApiSwapCexEstimateResponse?,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        payoutAddress: String? = nil,
        passcode: String
    ) async throws -> ApiActivity? {
        guard let swapEstimate else {
            throw BridgeCallError.customMessage("Missing swap estimate", nil)
        }
        switch swapType {
        case .crosschainFromWallet:
            return try await performFromWalletSwap(
                swapEstimate: swapEstimate,
                sellingToken: sellingToken,
                buyingToken: buyingToken,
                account: account,
                payoutAddress: payoutAddress,
                passcode: passcode
            )
        case .crosschainInsideWallet, .crosschainToWallet:
            return try await performToWalletSwap(
                swapEstimate: swapEstimate,
                sellingToken: sellingToken,
                buyingToken: buyingToken,
                account: account,
                passcode: passcode
            )
        case .onChain:
            throw BridgeCallError.customMessage("Invalid cross-chain swap type", nil)
        }
    }

    private func performToWalletSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        passcode: String
    ) async throws -> ApiActivity? {
        guard let toAddress = account.getAddress(chain: buyingToken.chain) else {
            throw BridgeCallError.customMessage("Missing payout address", nil)
        }
        return try await performCexSwap(
            swapEstimate: swapEstimate,
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            toAddress: toAddress,
            account: account,
            shouldTransfer: account.supports(chain: sellingToken.chain),
            passcode: passcode
        )
    }

    private func performFromWalletSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        payoutAddress: String?,
        passcode: String
    ) async throws -> ApiActivity? {
        guard let payoutAddress, !payoutAddress.isEmpty else {
            throw BridgeCallError.customMessage("Missing payout address", nil)
        }
        return try await performCexSwap(
            swapEstimate: swapEstimate,
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            toAddress: payoutAddress,
            account: account,
            shouldTransfer: true,
            passcode: passcode
        )
    }

    private func performCexSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        toAddress: String,
        account: SwapAccountSnapshot,
        shouldTransfer: Bool,
        passcode: String
    ) async throws -> ApiActivity? {
        guard let fromAddress = account.crosschainIdentifyingFromAddress else {
            throw BridgeCallError.customMessage("Missing account address", nil)
        }
        let networkFee = swapEstimate.realNetworkFee ?? swapEstimate.networkFee
        let params = ApiSwapCexCreateTransactionParams(
            from: sellingToken.swapIdentifier,
            fromAmount: swapEstimate.fromAmount,
            fromAddress: fromAddress,
            to: buyingToken.swapIdentifier,
            toAddress: toAddress,
            swapFee: swapEstimate.swapFee,
            networkFee: networkFee
        )
        return try await SwapCexSupport.swapCexCreateTransaction(
            accountId: account.id,
            sellingToken: sellingToken,
            params: params,
            shouldTransfer: shouldTransfer,
            passcode: passcode
        )
    }
}

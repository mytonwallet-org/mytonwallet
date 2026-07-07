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
    ) async throws -> SwapExecutionResult {
        guard let swapEstimate else {
            throw SdkError.unexpected(message: "Missing swap estimate")
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
            throw SdkError.unexpected(message: "Invalid cross-chain swap type")
        }
    }

    private func performToWalletSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        passcode: String
    ) async throws -> SwapExecutionResult {
        guard let toAddress = account.getAddress(chain: buyingToken.chain) else {
            throw SdkError.unexpected(message: "Missing payout address")
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
    ) async throws -> SwapExecutionResult {
        guard let payoutAddress, !payoutAddress.isEmpty else {
            throw SdkError.unexpected(message: "Missing payout address")
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
    ) async throws -> SwapExecutionResult {
        guard let historyAddress = account.crosschainIdentifyingFromAddress else {
            throw SdkError.unexpected(message: "Missing account address")
        }
        let isNearIntents = swapEstimate.cexLabel == .nearIntents
        let fromAddress: String
        if isNearIntents {
            guard let sourceAddress = account.getAddress(chain: sellingToken.chain) else {
                throw SdkError.unexpected(message: "Missing source address")
            }
            fromAddress = sourceAddress
        } else {
            fromAddress = historyAddress
        }
        let networkFee = swapEstimate.realNetworkFee ?? swapEstimate.networkFee
        let params = ApiSwapCexCreateTransactionParams(
            from: sellingToken.swapIdentifier,
            fromAmount: swapEstimate.fromAmount,
            fromAddress: fromAddress,
            historyAddress: historyAddress,
            cexLabel: swapEstimate.cexLabel,
            to: buyingToken.swapIdentifier,
            toAmount: swapEstimate.toAmount,
            toAddress: toAddress,
            swapFee: swapEstimate.swapFee,
            networkFee: networkFee
        )
        let result = try await SwapCexSupport.swapCexCreateTransaction(
            accountId: account.id,
            sellingToken: sellingToken,
            params: params,
            shouldTransfer: shouldTransfer,
            passcode: passcode
        )
        if shouldTransfer,
           sellingToken.chain == .ton,
           account.account.getChainInfo(chain: .ton)?.mfa != nil,
           result.mfaRequestHash == nil {
            throw SdkError.unexpected(message: "Missing MFA request hash", context: result)
        }
        return result
    }
}

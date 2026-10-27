import WalletCore

@MainActor struct CrosschainSwapExecutor {
    func performSwap(
        swapType: SwapType,
        swapEstimate: ApiSwapCexEstimateResponse?,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        payoutAddress: String? = nil,
        enclaveToken: EnclaveToken
    ) async throws -> SwapExecutionResult {
        guard let swapEstimate else {
            throw NotSubmittedError(SdkError.unexpected(message: "Missing swap estimate"))
        }
        switch swapType.cexTopology {
        case .fromWallet:
            return try await performFromWalletSwap(
                swapEstimate: swapEstimate,
                sellingToken: sellingToken,
                buyingToken: buyingToken,
                account: account,
                payoutAddress: payoutAddress,
                enclaveToken: enclaveToken
            )
        case .insideWallet, .toWallet:
            return try await performToWalletSwap(
                swapEstimate: swapEstimate,
                sellingToken: sellingToken,
                buyingToken: buyingToken,
                account: account,
                enclaveToken: enclaveToken
            )
        case nil:
            throw NotSubmittedError(SdkError.unexpected(message: "Invalid cross-chain swap type"))
        }
    }

    private func performToWalletSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        enclaveToken: EnclaveToken
    ) async throws -> SwapExecutionResult {
        guard let toAddress = account.getAddress(chain: buyingToken.chain) else {
            throw NotSubmittedError(SdkError.unexpected(message: "Missing payout address"))
        }
        return try await performCexSwap(
            swapEstimate: swapEstimate,
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            toAddress: toAddress,
            account: account,
            shouldTransfer: account.supports(chain: sellingToken.chain),
            enclaveToken: enclaveToken
        )
    }

    private func performFromWalletSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        account: SwapAccountSnapshot,
        payoutAddress: String?,
        enclaveToken: EnclaveToken
    ) async throws -> SwapExecutionResult {
        guard let payoutAddress, !payoutAddress.isEmpty else {
            throw NotSubmittedError(SdkError.unexpected(message: "Missing payout address"))
        }
        return try await performCexSwap(
            swapEstimate: swapEstimate,
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            toAddress: payoutAddress,
            account: account,
            shouldTransfer: true,
            enclaveToken: enclaveToken
        )
    }

    private func performCexSwap(
        swapEstimate: ApiSwapCexEstimateResponse,
        sellingToken: ApiToken,
        buyingToken: ApiToken,
        toAddress: String,
        account: SwapAccountSnapshot,
        shouldTransfer: Bool,
        enclaveToken: EnclaveToken
    ) async throws -> SwapExecutionResult {
        guard let historyAddress = account.crosschainIdentifyingFromAddress else {
            throw NotSubmittedError(SdkError.unexpected(message: "Missing account address"))
        }
        let isNearIntents = swapEstimate.cexLabel == .nearIntents
        let fromAddress: String
        if isNearIntents {
            guard let sourceAddress = account.getAddress(chain: sellingToken.chain) else {
                throw NotSubmittedError(SdkError.unexpected(message: "Missing source address"))
            }
            fromAddress = sourceAddress
        } else {
            fromAddress = historyAddress
        }
        let networkFee = swapEstimate.realNetworkFee ?? swapEstimate.networkFee
        let request = ApiSwapBuildRequest(
            from: sellingToken.swapIdentifier,
            to: buyingToken.swapIdentifier,
            fromAddress: fromAddress,
            historyAddress: historyAddress,
            cexLabel: swapEstimate.cexLabel,
            fromAmount: swapEstimate.fromAmount,
            toAmount: swapEstimate.toAmount,
            toAddress: toAddress,
            networkFee: networkFee,
            swapFee: swapEstimate.swapFee
        )
        let result = try await SwapCexSupport().swapCexCreateTransaction(
            accountId: account.id,
            sellingToken: sellingToken,
            request: request,
            shouldTransfer: shouldTransfer,
            enclaveToken: enclaveToken
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

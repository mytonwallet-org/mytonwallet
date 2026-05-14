import Foundation
import WalletCore
import WalletContext

struct CrosschainSwapEstimateResult {
    let changedFrom: SwapSide
    let swapEstimate: ApiSwapCexEstimateResponse?
    let estimateIssue: SwapIssue?
    let isRateLimited: Bool

    init(
        changedFrom: SwapSide,
        swapEstimate: ApiSwapCexEstimateResponse?,
        estimateIssue: SwapIssue?,
        isRateLimited: Bool = false
    ) {
        self.changedFrom = changedFrom
        self.swapEstimate = swapEstimate
        self.estimateIssue = estimateIssue
        self.isRateLimited = isRateLimited
    }
}

@MainActor struct CrosschainSwapEstimateEngine {
    func estimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> CrosschainSwapEstimateResult {
        try await loadEstimate(
            changedFrom: changedFrom,
            selling: input.selling,
            buying: input.buying,
            swapType: swapType,
            isMaxAmount: input.isMaxAmount,
            account: account
        )
    }

    private func loadEstimate(
        changedFrom: SwapSide,
        selling: TokenAmount,
        buying: TokenAmount,
        swapType: SwapType,
        isMaxAmount: Bool,
        account: SwapAccountSnapshot
    ) async throws -> CrosschainSwapEstimateResult {
        guard changedFrom == .selling else {
            throw BridgeCallError.customMessage("Cross-chain reverse estimation is not supported", nil)
        }
        do {
            let options = ApiSwapCexEstimateOptions(
                from: selling.token.swapIdentifier,
                to: buying.token.swapIdentifier,
                fromAmount: String(selling.amount.doubleAbsRepresentation(decimals: selling.token.decimals))
            )
            let estimate = try await Api.swapCexEstimate(swapEstimateOptions: options)
            try Task.checkCancellation()

            guard var swapEstimate = estimate else {
                return CrosschainSwapEstimateResult(
                    changedFrom: changedFrom,
                    swapEstimate: nil,
                    estimateIssue: .invalidPair
                )
            }

            if swapType != .crosschainToWallet {
                if let feeData = try? await fetchNetworkFee(sellingToken: selling.token, account: account) {
                    swapEstimate.networkFee = feeData.networkFee
                    swapEstimate.realNetworkFee = feeData.realNetworkFee
                }
                try Task.checkCancellation()
                adjustNativeMaxAmountIfNeeded(
                    &swapEstimate,
                    selling: selling,
                    swapType: swapType,
                    isMaxAmount: isMaxAmount,
                    account: account
                )
            }

            let resolvedSelling = TokenAmount(
                DecimalAmount.fromDouble(swapEstimate.fromAmount.value, selling.token).roundedForSwap.amount,
                selling.token
            )
            swapEstimate.isEnoughNative = isEnoughNativeForCrosschain(
                selling: resolvedSelling,
                swapType: swapType,
                networkFee: swapEstimate.networkFee?.value,
                account: account
            )
            swapEstimate.dieselStatus = .notAvailable
            return CrosschainSwapEstimateResult(
                changedFrom: changedFrom,
                swapEstimate: swapEstimate,
                estimateIssue: nil
            )
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            let isRateLimited = isSwapEstimateRateLimited(error)
            return CrosschainSwapEstimateResult(
                changedFrom: changedFrom,
                swapEstimate: nil,
                estimateIssue: isRateLimited ? nil : mapEstimateError(error),
                isRateLimited: isRateLimited
            )
        }
    }

    private func isEnoughNativeForCrosschain(
        selling: TokenAmount,
        swapType: SwapType,
        networkFee: Double?,
        account: SwapAccountSnapshot
    ) -> Bool? {
        if swapType == .crosschainToWallet {
            return true
        }
        guard
            account.supports(chain: selling.token.chain),
            let tokenBalance = account.balances[selling.token.slug],
            let nativeToken = TokenStore.tokens[selling.token.nativeTokenSlug],
            let nativeTokenBalance = account.balances[nativeToken.slug],
            let networkFee,
            let networkFeeData = FeeEstimationHelpers.networkFeeBigInt(
                sellToken: selling.token,
                swapType: swapType,
                networkFee: networkFee
            ),
            let maxAmount = getMaxSwapAmount(.init(
                swapType: swapType,
                tokenBalance: tokenBalance,
                tokenIn: selling.token,
                fullNetworkFee: .init(token: nil, native: networkFeeData.fee, stars: nil),
                ourFeePercent: 0,
                maxAmountFromBackend: nil
            ))
        else {
            return nil
        }

        return selling.amount <= maxAmount && networkFeeData.fee <= nativeTokenBalance
    }

    private func fetchNetworkFee(
        sellingToken: ApiToken,
        account: SwapAccountSnapshot
    ) async throws -> (networkFee: MDouble?, realNetworkFee: MDouble?) {
        let chain = sellingToken.chain
        let options = ApiCheckTransactionDraftOptions(
            accountId: account.id,
            toAddress: getChainConfig(chain: chain).feeCheckAddress,
            amount: nil,
            payload: nil,
            stateInit: nil,
            tokenAddress: sellingToken.tokenAddress,
            allowGasless: false
        )
        let draft = try await Api.checkTransactionDraft(chain: chain, options: options)
        let decimals = chain.nativeToken.decimals
        let networkFee = draft.fullNativeFee.flatMap { MDouble.forBigInt($0, decimals: decimals) }
        let realNetworkFee = draft.realNativeFee.flatMap { MDouble.forBigInt($0, decimals: decimals) }
        return (networkFee, realNetworkFee)
    }

    private func adjustNativeMaxAmountIfNeeded(
        _ swapEstimate: inout ApiSwapCexEstimateResponse,
        selling: TokenAmount,
        swapType: SwapType,
        isMaxAmount: Bool,
        account: SwapAccountSnapshot
    ) {
        guard
            isMaxAmount,
            selling.token.isNative,
            let networkFee = swapEstimate.networkFee,
            let tokenBalance = account.balances[selling.token.slug],
            let maxAmount = getMaxSwapAmount(.init(
                swapType: swapType,
                tokenBalance: tokenBalance,
                tokenIn: selling.token,
                fullNetworkFee: .init(
                    token: nil,
                    native: doubleToBigInt(networkFee.value, decimals: selling.token.decimals),
                    stars: nil
                ),
                ourFeePercent: 0,
                maxAmountFromBackend: nil
            ))
        else {
            return
        }

        swapEstimate.fromAmount = MDouble.forBigInt(maxAmount, decimals: selling.token.decimals) ?? swapEstimate.fromAmount
    }

    private func mapEstimateError(_ error: Error) -> SwapIssue {
        if let message = swapEstimateBackendMessage(from: error) {
            return mapEstimateErrorMessage(message)
        }
        return .unexpectedEstimateError
    }

    private func mapEstimateErrorMessage(_ message: String) -> SwapIssue {
        switch message.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Insufficient liquidity":
            return .insufficientLiquidity
        case "Tokens must be different", "Asset not found", "Pair not found":
            return .invalidPair
        case "Too small amount":
            return .tooSmallAmount
        default:
            return .unexpectedEstimateError
        }
    }
}

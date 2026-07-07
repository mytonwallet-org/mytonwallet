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

func crosschainNetworkFeeDraftAmount(
    sellingToken: ApiToken,
    isMaxAmount: Bool,
    account: SwapAccountSnapshot
) -> BigInt? {
    guard isMaxAmount, sellingToken.isNative, sellingToken.chain.isEvm else {
        return nil
    }
    return account.balances[sellingToken.slug]
}

func crosschainAdjustedNativeMaxAmount(
    sellingToken: ApiToken,
    swapType: SwapType,
    isMaxAmount: Bool,
    account: SwapAccountSnapshot,
    networkFee: MDouble?
) -> BigInt? {
    guard
        swapType != .crosschainToWallet,
        isMaxAmount,
        sellingToken.isNative,
        let tokenBalance = account.balances[sellingToken.slug],
        let networkFee
    else {
        return nil
    }

    return getMaxSwapAmount(.init(
        swapType: swapType,
        tokenBalance: tokenBalance,
        tokenIn: sellingToken,
        fullNetworkFee: .init(
            token: nil,
            native: networkFee.bigintAmount(decimals: sellingToken.decimals),
            stars: nil
        ),
        ourFeePercent: 0,
        maxAmountFromBackend: nil
    ))
}

@MainActor struct CrosschainSwapEstimateEngine {
    func estimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> CrosschainSwapEstimateResult {
        try await loadEstimate(
            input,
            changedFrom: changedFrom,
            swapType: swapType,
            account: account
        )
    }

    private func loadEstimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> CrosschainSwapEstimateResult {
        guard changedFrom == .selling else {
            throw SdkError.unexpected(message: "Cross-chain reverse estimation is not supported")
        }
        do {
            let selling = input.selling
            let buying = input.buying
            var requestAmount = selling.amount
            var networkFee: MDouble?
            var realNetworkFee: MDouble?

            if swapType != .crosschainToWallet, input.isMaxAmount, selling.token.isNative {
                let feeDraftAmount = crosschainNetworkFeeDraftAmount(
                    sellingToken: selling.token,
                    isMaxAmount: input.isMaxAmount,
                    account: account
                )
                if let feeData = try? await fetchNetworkFee(
                    sellingToken: selling.token,
                    account: account,
                    amount: feeDraftAmount
                ) {
                    networkFee = feeData.networkFee
                    realNetworkFee = feeData.realNetworkFee
                    if let adjustedMaxAmount = crosschainAdjustedNativeMaxAmount(
                        sellingToken: selling.token,
                        swapType: swapType,
                        isMaxAmount: input.isMaxAmount,
                        account: account,
                        networkFee: feeData.networkFee
                    ) {
                        requestAmount = adjustedMaxAmount
                    }
                }
                try Task.checkCancellation()
            }

            guard let fromAmount = MDouble.forBigInt(abs(requestAmount), decimals: selling.token.decimals) else {
                throw SdkError.unexpected(message: "Invalid swap amount")
            }
            let fromAddress = account.getAddress(chain: selling.token.chain)
            let toAddress = account.getAddress(chain: buying.token.chain)
            let shouldForceChangelly = swapType == .crosschainToWallet && fromAddress == nil
            let options = ApiSwapCexEstimateOptions(
                from: selling.token.swapIdentifier,
                to: buying.token.swapIdentifier,
                fromAmount: fromAmount,
                fromAddress: fromAddress,
                toAddress: toAddress,
                cexLabel: shouldForceChangelly ? .changelly : input.cexLabel,
                isFromAmountMax: input.isMaxAmount ? true : nil
            )
            let estimate = try await Api.swapCexEstimate(accountId: account.id, swapEstimateOptions: options)
            try Task.checkCancellation()

            guard var swapEstimate = estimate else {
                return CrosschainSwapEstimateResult(
                    changedFrom: changedFrom,
                    swapEstimate: nil,
                    estimateIssue: .invalidPair
                )
            }

            if swapType != .crosschainToWallet {
                if networkFee == nil, realNetworkFee == nil {
                    if let feeData = try? await fetchNetworkFee(
                        sellingToken: selling.token,
                        account: account,
                        amount: nil
                    ) {
                        networkFee = feeData.networkFee
                        realNetworkFee = feeData.realNetworkFee
                    }
                    try Task.checkCancellation()
                }
                swapEstimate.networkFee = networkFee
                swapEstimate.realNetworkFee = realNetworkFee
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
        account: SwapAccountSnapshot,
        amount: BigInt?
    ) async throws -> (networkFee: MDouble?, realNetworkFee: MDouble?) {
        let chain = sellingToken.chain
        let options = ApiCheckTransactionDraftOptions(
            accountId: account.id,
            toAddress: getChainConfig(chain: chain).feeCheckAddress,
            amount: amount,
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

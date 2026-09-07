import Foundation
import WalletCore
import WalletContext

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
        swapType.cexTopology != .toWallet,
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
        maxAmountFromBackend: nil
    ))
}

/// `nil` means the estimate could not price the transfer, and the validator blocks the swap on it. A balance
/// the snapshot lacks counts as zero: a token the account does not hold is "not enough", not "unknown".
@MainActor func isEnoughNativeForCrosschain(
    selling: TokenAmount,
    swapType: SwapType,
    fee: BigInt?,
    account: SwapAccountSnapshot
) -> Bool? {
    if swapType.cexTopology == .toWallet || !account.supports(chain: selling.token.chain) {
        return true
    }
    guard let fee else {
        return nil
    }
    let tokenBalance = account.balances[selling.token.slug] ?? 0
    let nativeBalance = account.balances[selling.token.nativeTokenSlug] ?? 0
    let maxAmount = getMaxSwapAmount(.init(
        swapType: swapType,
        tokenBalance: tokenBalance,
        tokenIn: selling.token,
        fullNetworkFee: .init(token: nil, native: fee, stars: nil),
        maxAmountFromBackend: nil
    )) ?? 0
    return selling.amount <= maxAmount && fee <= nativeBalance
}

@MainActor struct CrosschainSwapEstimateEngine {
    var fetchEstimate: (String, ApiSwapEstimateRequest) async throws -> ApiSwapEstimateResponse = {
        try await Api.swapEstimate(accountId: $0, request: $1)
    }

    func estimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> SwapEstimateResult {
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
    ) async throws -> SwapEstimateResult {
        guard changedFrom == .selling else {
            throw SdkError.unexpected(message: "Cross-chain reverse estimation is not supported")
        }
        do {
            let selling = input.selling
            let buying = input.buying
            var requestAmount = selling.amount
            var networkFee: MDouble?
            var realNetworkFee: MDouble?

            if swapType.cexTopology != .toWallet, input.isMaxAmount, selling.token.isNative {
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
            let shouldForceChangelly = swapType.cexTopology == .toWallet && fromAddress == nil
            let request = ApiSwapEstimateRequest(
                from: selling.token.swapIdentifier,
                to: buying.token.swapIdentifier,
                slippage: nil,
                fromAmount: fromAmount,
                toAmount: nil,
                fromAddress: fromAddress,
                toAddress: toAddress,
                cexLabel: shouldForceChangelly ? .changelly : input.cexLabel,
                shouldTryDiesel: nil,
                swapVersion: nil,
                toncoinBalance: nil,
                walletVersion: nil,
                isFromAmountMax: input.isMaxAmount ? true : nil
            )
            let response = try await fetchEstimate(account.id, request)
            try Task.checkCancellation()
            if case .error = response {
                return SwapEstimateResult(changedFrom: input.inputSource, response: response)
            }
            guard case .cex(var swapEstimate) = response else {
                throw SdkError.unexpected(message: "Expected CEX swap estimate", context: response)
            }

            if swapType.cexTopology != .toWallet {
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
            let nativeFee = swapEstimate.networkFee.flatMap {
                FeeEstimationHelpers.networkFeeBigInt(
                    sellToken: selling.token,
                    swapType: swapType,
                    networkFee: $0.value
                )?.fee
            }
            swapEstimate.isEnoughNative = isEnoughNativeForCrosschain(
                selling: resolvedSelling,
                swapType: swapType,
                fee: nativeFee,
                account: account
            )
            swapEstimate.dieselStatus = .notAvailable
            return SwapEstimateResult(
                changedFrom: changedFrom,
                response: .cex(swapEstimate),
                estimateIssue: nil
            )
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            let isRateLimited = isSwapEstimateRateLimited(error)
            return SwapEstimateResult(
                changedFrom: changedFrom,
                response: nil,
                estimateIssue: isRateLimited ? nil : swapEstimateIssue(from: error),
                isRateLimited: isRateLimited
            )
        }
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

}

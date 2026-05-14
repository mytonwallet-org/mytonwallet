import Foundation
import WalletCore
import WalletContext

private let log = Log("OnchainSwapEstimateEngine")

@MainActor struct OnchainSwapEstimateEngine {
    func estimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> OnchainSwapEstimateResult {
        try await loadEstimate(
            input: input,
            changedFrom: changedFrom,
            account: account
        )
    }

    private func loadEstimate(
        input: SwapEstimateInput,
        changedFrom: SwapSide,
        account: SwapAccountSnapshot
    ) async throws -> OnchainSwapEstimateResult {
        do {
            let selling = input.selling
            let buying = input.buying
            guard let fromAddress = account.getAddress(chain: selling.token.chain) else {
                throw BridgeCallError.customMessage("Missing account address", nil)
            }
            let toncoinBalance = account.balances[TONCOIN_SLUG].flatMap { MDouble.forBigInt($0, decimals: 9) }
            let isFromAmountMax = changedFrom == .selling && input.isMaxAmount
            let shouldTryDiesel: Bool = if let currentNetworkFee = input.previousNetworkFee,
                                           let nativeBalance = account.balances[selling.token.nativeTokenSlug],
                                           let nativeToken = TokenStore.tokens[selling.token.nativeTokenSlug] {
                nativeBalance < currentNetworkFee.bigintAmount(decimals: nativeToken.decimals)
            } else {
                false
            }
            let requestFromAmount: MDouble? = if isFromAmountMax {
                account.balances[selling.token.slug].flatMap { MDouble.forBigInt($0, decimals: selling.token.decimals) }
            } else if changedFrom == .selling {
                MDouble.forBigInt(selling.amount, decimals: selling.token.decimals)
            } else {
                nil
            }
            let request = ApiSwapEstimateRequest(
                from: selling.token.swapIdentifier,
                to: buying.token.swapIdentifier,
                slippage: input.slippage,
                fromAmount: requestFromAmount,
                toAmount: changedFrom == .buying ? MDouble.forBigInt(buying.amount, decimals: buying.token.decimals) : nil,
                fromAddress: fromAddress,
                shouldTryDiesel: shouldTryDiesel,
                swapVersion: nil,
                toncoinBalance: toncoinBalance,
                walletVersion: account.version,
                isFromAmountMax: isFromAmountMax
            )

            let swapEstimate = try await Api.swapEstimate(accountId: account.id, request: request)
            try Task.checkCancellation()
            return OnchainSwapEstimateResult(
                changedFrom: changedFrom,
                swapEstimate: swapEstimate,
                estimateIssue: nil
            )
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            log.error("swapEstimate error \(error, .public)")
            let isRateLimited = isSwapEstimateRateLimited(error)
            return OnchainSwapEstimateResult(
                changedFrom: changedFrom,
                swapEstimate: nil,
                estimateIssue: isRateLimited ? nil : mapEstimateError(error),
                isRateLimited: isRateLimited
            )
        }
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

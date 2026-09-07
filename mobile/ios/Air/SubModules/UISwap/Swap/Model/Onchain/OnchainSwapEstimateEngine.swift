import Foundation
import WalletCore
import WalletContext

private let log = Log("OnchainSwapEstimateEngine")

@MainActor struct OnchainSwapEstimateEngine {
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
            input: input,
            changedFrom: changedFrom,
            account: account
        )
    }

    private func loadEstimate(
        input: SwapEstimateInput,
        changedFrom: SwapSide,
        account: SwapAccountSnapshot
    ) async throws -> SwapEstimateResult {
        do {
            let selling = input.selling
            let buying = input.buying
            guard let fromAddress = account.getAddress(chain: selling.token.chain) else {
                throw SdkError.unexpected(message: "Missing account address")
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

            let response = try await fetchEstimate(account.id, request)
            try Task.checkCancellation()
            if case .error = response {
                return SwapEstimateResult(changedFrom: input.inputSource, response: response)
            }
            guard case .dex(let swapEstimate) = response else {
                throw SdkError.unexpected(message: "Expected DEX swap estimate", context: response)
            }
            return SwapEstimateResult(
                changedFrom: changedFrom,
                response: .dex(swapEstimate),
                estimateIssue: nil
            )
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            log.error("swapEstimate error \(error, .public)")
            let isRateLimited = isSwapEstimateRateLimited(error)
            return SwapEstimateResult(
                changedFrom: changedFrom,
                response: nil,
                estimateIssue: isRateLimited ? nil : swapEstimateIssue(from: error),
                isRateLimited: isRateLimited
            )
        }
    }
}

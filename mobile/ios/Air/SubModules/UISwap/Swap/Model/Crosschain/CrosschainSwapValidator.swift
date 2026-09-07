import WalletCore
import WalletContext

@MainActor struct CrosschainSwapValidator {
    func validationIssue(
        input: SwapValidationInput,
        swapEstimate: ApiSwapCexEstimateResponse?,
        account: SwapAccountSnapshot
    ) -> SwapIssue? {
        guard let swapEstimate else {
            return nil
        }
        var issue: SwapIssue?
        let sellingToken = input.sellingToken
        let balanceIn = account.balances[sellingToken.slug] ?? 0
        if account.supports(chain: sellingToken.chain) {
            if let sellingAmount = input.sellingAmount, balanceIn < sellingAmount {
                issue = .insufficientBalance
            }
        }
        if swapEstimate.isEnoughNative == false {
            issue = sellingToken.isNative ? .insufficientBalance : .notEnoughToken(nativeToken(for: sellingToken))
        }
        // An unknown fee blocks the swap; a short balance or a min/max violation is the more useful message.
        if swapEstimate.isEnoughNative == nil, issue == nil {
            issue = .unexpectedEstimateError
        }
        if swapEstimate.fromAmount < swapEstimate.fromMin {
            issue = .minimumAmount(swapEstimate.fromMin, sellingToken)
        }
        if swapEstimate.fromMax > 0, swapEstimate.fromAmount > swapEstimate.fromMax {
            issue = .maximumAmount(swapEstimate.fromMax, sellingToken)
        }
        return issue
    }

    private func nativeToken(for token: ApiToken) -> ApiToken {
        TokenStore.tokens[token.nativeTokenSlug] ?? token.chain.nativeToken
    }
}

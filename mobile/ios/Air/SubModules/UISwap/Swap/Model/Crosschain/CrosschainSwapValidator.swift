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
        if let fromMin = swapEstimate.fromMin {
            if swapEstimate.fromAmount < fromMin {
                issue = .minimumAmount(fromMin, sellingToken)
            }
        }
        if let fromMax = swapEstimate.fromMax, fromMax > 0 {
            if swapEstimate.fromAmount > fromMax {
                issue = .maximumAmount(fromMax, sellingToken)
            }
        }
        return issue
    }

    private func nativeToken(for token: ApiToken) -> ApiToken {
        TokenStore.tokens[token.nativeTokenSlug] ?? token.chain.nativeToken
    }
}

import WalletCore
import WalletContext

struct OnchainSwapFeeStatus {
    let explainedFee: ExplainedSwapFee
    let nativeToken: ApiToken
    let isNativeFeeCovered: Bool
}

@MainActor struct OnchainSwapValidator {
    func validationIssue(
        input: SwapValidationInput,
        swapEstimate: ApiSwapEstimateResponse?,
        account: SwapAccountSnapshot
    ) -> SwapIssue? {
        guard let swapEstimate else {
            return nil
        }
        let sellingToken = input.sellingToken
        let sellingAmount = input.sellingAmount ?? 0
        let balanceIn = account.balances[sellingToken.slug] ?? 0
        if account.supports(chain: sellingToken.chain) {
            if balanceIn < sellingAmount {
                return .insufficientBalance
            }
        }

        let feeStatus = feeStatus(input: input, swapEstimate: swapEstimate, account: account)
        let notEnoughForFee = swapEstimate.toAmount?.value == 0 && !feeStatus.isNativeFeeCovered
        if notEnoughForFee {
            return .notEnoughToken(sellingToken)
        }

        if let maxAmount = input.maxAmount, sellingAmount > maxAmount {
            if !feeStatus.isNativeFeeCovered, !feeStatus.explainedFee.isGasless {
                return sellingToken.isNative ? .insufficientBalance : .notEnoughToken(feeStatus.nativeToken)
            }
            return .insufficientBalance
        }

        if !feeStatus.isNativeFeeCovered {
            if feeStatus.explainedFee.isGasless {
                switch swapEstimate.dieselStatus {
                case .pendingPrevious:
                    return .awaitingPreviousFee
                case .notAuthorized, .available, .starsFee:
                    return nil
                case .notAvailable:
                    break
                }
            }
            return sellingToken.isNative ? .insufficientBalance : .notEnoughToken(feeStatus.nativeToken)
        }
        return nil
    }

    func requiresDieselAuthorization(
        input: SwapValidationInput,
        swapEstimate: ApiSwapEstimateResponse?,
        account: SwapAccountSnapshot
    ) -> Bool {
        guard let swapEstimate else {
            return false
        }
        return feeStatus(input: input, swapEstimate: swapEstimate, account: account).explainedFee.isGasless
            && swapEstimate.dieselStatus == .notAuthorized
    }

    func shouldTryDiesel(
        input: SwapValidationInput,
        swapEstimate: ApiSwapEstimateResponse?,
        account: SwapAccountSnapshot
    ) -> Bool {
        guard let swapEstimate else {
            return false
        }
        return feeStatus(input: input, swapEstimate: swapEstimate, account: account).explainedFee.isGasless
    }

    func feeStatus(
        input: SwapValidationInput,
        swapEstimate: ApiSwapEstimateResponse,
        account: SwapAccountSnapshot
    ) -> OnchainSwapFeeStatus {
        let sellingToken = input.sellingToken
        let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] ?? sellingToken.chain.nativeToken
        let nativeTokenInBalance = account.balances[nativeToken.slug] ?? 0
        let explainedFee = explainSwapFee(.init(
            swapType: .onChain,
            tokenIn: sellingToken,
            networkFee: swapEstimate.networkFee,
            realNetworkFee: swapEstimate.realNetworkFee,
            ourFee: swapEstimate.ourFee,
            dieselStatus: swapEstimate.dieselStatus,
            dieselFee: swapEstimate.dieselFee,
            nativeTokenInBalance: nativeTokenInBalance
        ))
        let networkFee = swapEstimate.networkFee.bigintAmount(decimals: nativeToken.decimals)
        return OnchainSwapFeeStatus(
            explainedFee: explainedFee,
            nativeToken: nativeToken,
            isNativeFeeCovered: nativeTokenInBalance >= networkFee
        )
    }
}

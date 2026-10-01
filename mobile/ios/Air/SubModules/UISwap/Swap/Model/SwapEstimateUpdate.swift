import WalletContext

struct SwapEstimateUpdate: Sendable {
    let changedFrom: SwapSide
    let estimatedAmounts: SwapInputModel.Estimate?
    let backendMaxAmount: BigInt?
    let stateUpdate: SwapEstimateResult?

    init(
        changedFrom: SwapSide,
        estimatedAmounts: SwapInputModel.Estimate?,
        backendMaxAmount: BigInt?,
        stateUpdate: SwapEstimateResult?
    ) {
        self.changedFrom = changedFrom
        self.estimatedAmounts = estimatedAmounts
        self.backendMaxAmount = backendMaxAmount
        self.stateUpdate = stateUpdate
    }

    var hasQuote: Bool {
        stateUpdate?.response?.isQuote == true
    }

    @MainActor func apply(to input: SwapInputModel) {
        if let estimatedAmounts {
            input.updateWithEstimate(estimatedAmounts)
        } else {
            input.clearEstimatedAmount(changedFrom: changedFrom)
        }
        input.setBackendMaxAmount(backendMaxAmount)
    }
}

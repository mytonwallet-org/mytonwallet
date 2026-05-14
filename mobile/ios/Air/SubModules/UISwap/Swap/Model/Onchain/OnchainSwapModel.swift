import WalletCore

struct OnchainSwapEstimateResult {
    let changedFrom: SwapSide
    let swapEstimate: ApiSwapEstimateResponse?
    let estimateIssue: SwapIssue?
    let isRateLimited: Bool

    init(
        changedFrom: SwapSide,
        swapEstimate: ApiSwapEstimateResponse?,
        estimateIssue: SwapIssue?,
        isRateLimited: Bool = false
    ) {
        self.changedFrom = changedFrom
        self.swapEstimate = swapEstimate
        self.estimateIssue = estimateIssue
        self.isRateLimited = isRateLimited
    }
}

struct OnchainSwapModel {
    private(set) var swapEstimate: ApiSwapEstimateResponse?
    private(set) var estimateIssue: SwapIssue?

    mutating func applyEstimate(_ result: OnchainSwapEstimateResult) {
        updateEstimate(
            result.swapEstimate,
            estimateIssue: result.estimateIssue
        )
    }

    mutating func clearEstimate() {
        updateEstimate(nil)
    }

    private mutating func updateEstimate(_ swapEstimate: ApiSwapEstimateResponse?, estimateIssue: SwapIssue? = nil) {
        self.swapEstimate = swapEstimate
        self.estimateIssue = estimateIssue
    }
}

import WalletCore

struct CrosschainSwapModel {
    private(set) var cexEstimate: ApiSwapCexEstimateResponse?
    private(set) var estimateIssue: SwapIssue?

    mutating func applyEstimate(_ result: CrosschainSwapEstimateResult) {
        updateEstimate(result.swapEstimate, estimateIssue: result.estimateIssue)
    }

    mutating func clearEstimate() {
        updateEstimate(nil)
    }

    private mutating func updateEstimate(_ swapEstimate: ApiSwapCexEstimateResponse?, estimateIssue: SwapIssue? = nil) {
        cexEstimate = swapEstimate
        self.estimateIssue = estimateIssue
    }
}

import WalletCore

struct SwapEstimateResult: Sendable {
    let changedFrom: SwapSide
    let response: ApiSwapEstimateResponse?
    let estimateIssue: SwapIssue?

    init(
        changedFrom: SwapSide,
        response: ApiSwapEstimateResponse?,
        estimateIssue: SwapIssue?
    ) {
        self.changedFrom = changedFrom
        self.response = response
        self.estimateIssue = estimateIssue
    }

    init(changedFrom: SwapSide, response: ApiSwapEstimateResponse) {
        self.changedFrom = changedFrom
        self.response = response
        if case .error(let error) = response {
            estimateIssue = isSwapEstimateRateLimited(error) ? nil : swapEstimateIssue(from: error)
        } else {
            estimateIssue = nil
        }
    }

    var isRateLimited: Bool {
        guard case .error(let error) = response else { return false }
        return isSwapEstimateRateLimited(error)
    }

    var dexEstimate: ApiSwapDexEstimateResponse? {
        guard case .dex(let estimate) = response else { return nil }
        return estimate
    }

    var cexEstimate: ApiSwapCexEstimateResponse? {
        guard case .cex(let estimate) = response else { return nil }
        return estimate
    }
}

struct SwapEstimateModel {
    private(set) var response: ApiSwapEstimateResponse?
    private(set) var estimateIssue: SwapIssue?
    private(set) var swapMode: ApiSwapMode?
    private var estimatedInput: SwapEstimateInput?

    init(_ result: SwapEstimateResult? = nil) {
        if let result {
            apply(result)
        }
    }

    func response(for input: SwapEstimateInput?) -> ApiSwapEstimateResponse? {
        guard estimatedInput?.matchesCurrent(input) == true else { return nil }
        return response
    }

    mutating func invalidateHint() {
        estimatedInput = nil
    }

    var dexEstimate: ApiSwapDexEstimateResponse? {
        guard case .dex(let estimate) = response else { return nil }
        return estimate
    }

    var cexEstimate: ApiSwapCexEstimateResponse? {
        guard case .cex(let estimate) = response else { return nil }
        return estimate
    }

    mutating func apply(_ result: SwapEstimateResult, input: SwapEstimateInput? = nil) {
        response = result.response
        estimateIssue = result.estimateIssue
        swapMode = result.response?.isQuote == true ? result.changedFrom.swapMode : nil
        estimatedInput = input
    }

    mutating func clear() {
        response = nil
        estimateIssue = nil
        swapMode = nil
        estimatedInput = nil
    }
}

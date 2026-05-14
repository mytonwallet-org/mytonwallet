import WalletCore
import WalletContext

enum SwapEstimateStateUpdate {
    case onchain(OnchainSwapEstimateResult)
    case crosschain(CrosschainSwapEstimateResult)
}

@MainActor struct SwapEstimateUpdate {
    let changedFrom: SwapSide
    let estimatedAmounts: SwapInputModel.Estimate?
    let backendMaxAmount: BigInt?
    let keepsCurrentState: Bool
    let stateUpdate: SwapEstimateStateUpdate?

    init(
        changedFrom: SwapSide,
        estimatedAmounts: SwapInputModel.Estimate?,
        backendMaxAmount: BigInt?,
        keepsCurrentState: Bool = false,
        stateUpdate: SwapEstimateStateUpdate?
    ) {
        self.changedFrom = changedFrom
        self.estimatedAmounts = estimatedAmounts
        self.backendMaxAmount = backendMaxAmount
        self.keepsCurrentState = keepsCurrentState
        self.stateUpdate = stateUpdate
    }

    static func rateLimited(changedFrom: SwapSide) -> SwapEstimateUpdate {
        SwapEstimateUpdate(
            changedFrom: changedFrom,
            estimatedAmounts: nil,
            backendMaxAmount: nil,
            keepsCurrentState: true,
            stateUpdate: nil
        )
    }

    func apply(to input: SwapInputModel) {
        guard !keepsCurrentState else { return }
        if let estimatedAmounts {
            input.updateWithEstimate(estimatedAmounts)
        } else {
            input.clearEstimatedAmount(changedFrom: changedFrom)
        }
        input.setBackendMaxAmount(backendMaxAmount)
    }
}

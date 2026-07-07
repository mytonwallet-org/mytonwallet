import WalletCore
import WalletContext

struct SwapExecutionContext {
    let swapType: SwapType
    let confirmation: SwapConfirmationAmounts
    let maxAmount: BigInt?
    let slippage: Double
    let payoutAddress: String?
    let account: SwapAccountSnapshot
    let passcode: String
}

struct SwapExecutionResult: Sendable, MfaProtectedActionResult {
    let activity: ApiActivity?
    let swapId: String?
    let mfaRequestHash: String?

    static let submitted = SwapExecutionResult(activity: nil, swapId: nil, mfaRequestHash: nil)

    func handleMfaConfirmation(accountId: String, request: ApiMfaRequest) async throws {
        guard let swapId else {
            return
        }
        guard !request.txHash.isEmpty else {
            throw SdkError.unexpected(message: "Missing MFA transaction hash", context: request)
        }
        try await Api.confirmSwapMfaRequest(accountId: accountId, swapId: swapId, txHash: request.txHash)
    }
}

struct SwapMaxAmountContext {
    let swapType: SwapType
    let fullNetworkFee: MFee.FeeTerms?
    let ourFeePercent: Double?
}

struct SwapFlowState {
    let onchain: OnchainSwapModel
    let crosschain: CrosschainSwapModel
}

enum SwapDetailsSection: Equatable {
    case onchain
    case crosschain(SwapType)
}

@MainActor protocol SwapFlow {
    var refreshesOnSlippageChange: Bool { get }

    func supports(swapType: SwapType) -> Bool
    func detailsSection(swapType: SwapType) -> SwapDetailsSection
    func previousNetworkFee(state: SwapFlowState) -> MDouble?
    func priceImpactWarning(state: SwapFlowState) -> Double?
    func estimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> SwapEstimateUpdate
    func maxAmountContext(
        swapType: SwapType,
        sellingToken: ApiToken,
        nativeTokenInBalance: BigInt?,
        state: SwapFlowState
    ) -> SwapMaxAmountContext
    func buttonState(context: SwapPresentationContext, state: SwapFlowState) -> SwapButtonState
    func route(context: SwapPresentationContext, state: SwapFlowState) -> SwapRoute?
    func performSwap(context: SwapExecutionContext, state: SwapFlowState) async throws -> SwapExecutionResult
}

@MainActor struct SwapFlowRouter {
    private let flows: [any SwapFlow]

    init(flows: [any SwapFlow]) {
        self.flows = flows
    }

    func flow(for swapType: SwapType) -> any SwapFlow {
        guard let flow = flows.first(where: { $0.supports(swapType: swapType) }) else {
            fatalError("Missing swap flow for \(swapType)")
        }
        return flow
    }
}

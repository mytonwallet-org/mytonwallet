import WalletCore
import WalletContext

@MainActor struct CrosschainSwapFlow: SwapFlow {
    private let estimateEngine: CrosschainSwapEstimateEngine
    private let presenter: CrosschainSwapPresenter
    private let executor: CrosschainSwapExecutor

    init(
        validator: CrosschainSwapValidator,
        estimateEngine: CrosschainSwapEstimateEngine = CrosschainSwapEstimateEngine(),
        executor: CrosschainSwapExecutor = CrosschainSwapExecutor()
    ) {
        self.estimateEngine = estimateEngine
        self.presenter = CrosschainSwapPresenter(validator: validator)
        self.executor = executor
    }

    var refreshesOnSlippageChange: Bool {
        false
    }

    func previousNetworkFee(state: SwapFlowState) -> MDouble? {
        nil
    }

    func priceImpactWarning(state: SwapFlowState) -> Double? {
        nil
    }

    func supports(swapType: SwapType) -> Bool {
        swapType != .onChain
    }

    func detailsSection(swapType: SwapType) -> SwapDetailsSection {
        .crosschain(swapType)
    }

    func estimate(
        _ input: SwapEstimateInput,
        changedFrom: SwapSide,
        swapType: SwapType,
        account: SwapAccountSnapshot
    ) async throws -> SwapEstimateUpdate {
        let result = try await estimateEngine.estimate(
            input,
            changedFrom: changedFrom,
            swapType: swapType,
            account: account
        )
        if result.isRateLimited {
            return .rateLimited(changedFrom: result.changedFrom)
        }
        let estimatedAmounts = result.swapEstimate.map {
            SwapInputModel.Estimate(
                changedFrom: result.changedFrom,
                fromAmount: $0.fromAmount.value,
                toAmount: $0.toAmount.value
            )
        }
        return SwapEstimateUpdate(
            changedFrom: result.changedFrom,
            estimatedAmounts: estimatedAmounts,
            backendMaxAmount: nil,
            stateUpdate: .crosschain(result)
        )
    }

    func maxAmountContext(
        swapType: SwapType,
        sellingToken: ApiToken,
        nativeTokenInBalance: BigInt?,
        state: SwapFlowState
    ) -> SwapMaxAmountContext {
        let explainedFee = explainSwapFee(.init(
            swapType: swapType,
            tokenIn: sellingToken,
            networkFee: state.crosschain.cexEstimate?.networkFee,
            realNetworkFee: state.crosschain.cexEstimate?.realNetworkFee,
            ourFee: nil,
            dieselStatus: nil,
            dieselFee: nil,
            nativeTokenInBalance: nativeTokenInBalance
        ))
        return SwapMaxAmountContext(
            swapType: swapType,
            fullNetworkFee: explainedFee.fullFee?.networkTerms,
            ourFeePercent: nil
        )
    }

    func buttonState(context: SwapPresentationContext, state: SwapFlowState) -> SwapButtonState {
        presenter.buttonState(context: context, state: state.crosschain)
    }

    func route(context: SwapPresentationContext, state: SwapFlowState) -> SwapRoute? {
        presenter.route(context: context, state: state.crosschain)
    }

    func performSwap(context: SwapExecutionContext, state: SwapFlowState) async throws -> ApiActivity? {
        try await executor.performSwap(
            swapType: context.swapType,
            swapEstimate: state.crosschain.cexEstimate,
            sellingToken: context.confirmation.selling.token,
            buyingToken: context.confirmation.buying.token,
            account: context.account,
            payoutAddress: context.payoutAddress,
            passcode: context.passcode
        )
    }
}

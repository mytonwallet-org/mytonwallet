import WalletCore
import WalletContext

@MainActor struct OnchainSwapFlow: SwapFlow {
    private let estimateEngine: OnchainSwapEstimateEngine
    private let presenter: OnchainSwapPresenter
    private let executor: OnchainSwapExecutor

    init(
        validator: OnchainSwapValidator,
        estimateEngine: OnchainSwapEstimateEngine = OnchainSwapEstimateEngine(),
        executor: OnchainSwapExecutor = OnchainSwapExecutor()
    ) {
        self.estimateEngine = estimateEngine
        self.presenter = OnchainSwapPresenter(validator: validator)
        self.executor = executor
    }

    var refreshesOnSlippageChange: Bool {
        true
    }

    func previousNetworkFee(state: SwapFlowState) -> MDouble? {
        state.onchain.swapEstimate?.networkFee
    }

    func priceImpactWarning(state: SwapFlowState) -> Double? {
        guard let impact = state.onchain.swapEstimate?.impact, impact > MAX_PRICE_IMPACT_VALUE else {
            return nil
        }
        return impact
    }

    func supports(swapType: SwapType) -> Bool {
        swapType == .onChain
    }

    func detailsSection(swapType: SwapType) -> SwapDetailsSection {
        .onchain
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
                fromAmount: $0.fromAmount?.value ?? 0,
                toAmount: $0.toAmount?.value ?? 0
            )
        }
        let backendMaxAmount = input.isMaxAmount ? result.swapEstimate?.fromAmount.flatMap {
            DecimalAmount.fromDouble($0.value, input.selling.token).roundedForSwap.amount
        } : nil
        return SwapEstimateUpdate(
            changedFrom: result.changedFrom,
            estimatedAmounts: estimatedAmounts,
            backendMaxAmount: backendMaxAmount,
            stateUpdate: .onchain(result)
        )
    }

    func maxAmountContext(
        swapType: SwapType,
        sellingToken: ApiToken,
        nativeTokenInBalance: BigInt?,
        state: SwapFlowState
    ) -> SwapMaxAmountContext {
        let explainedFee = explainSwapFee(.init(
            swapType: .onChain,
            tokenIn: sellingToken,
            networkFee: state.onchain.swapEstimate?.networkFee,
            realNetworkFee: state.onchain.swapEstimate?.realNetworkFee,
            ourFee: state.onchain.swapEstimate?.ourFee,
            dieselStatus: state.onchain.swapEstimate?.dieselStatus,
            dieselFee: state.onchain.swapEstimate?.dieselFee,
            nativeTokenInBalance: nativeTokenInBalance
        ))
        return SwapMaxAmountContext(
            swapType: .onChain,
            fullNetworkFee: explainedFee.fullFee?.networkTerms,
            ourFeePercent: state.onchain.swapEstimate?.ourFeePercent
        )
    }

    func buttonState(context: SwapPresentationContext, state: SwapFlowState) -> SwapButtonState {
        presenter.buttonState(context: context, state: state.onchain)
    }

    func route(context: SwapPresentationContext, state: SwapFlowState) -> SwapRoute? {
        presenter.route(context: context, state: state.onchain)
    }

    func performSwap(context: SwapExecutionContext, state: SwapFlowState) async throws -> ApiActivity? {
        try await executor.performSwap(
            swapEstimate: state.onchain.swapEstimate,
            confirmation: context.confirmation,
            maxAmount: context.maxAmount,
            slippage: context.slippage,
            account: context.account,
            passcode: context.passcode
        )
        return nil
    }
}

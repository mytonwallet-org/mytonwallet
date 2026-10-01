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

    func previousNetworkFee(state: SwapEstimateModel) -> MDouble? {
        state.dexEstimate?.networkFee
    }

    func priceImpactWarning(state: SwapEstimateModel) -> Double? {
        guard let impact = state.dexEstimate?.impact, impact > MAX_PRICE_IMPACT_VALUE else {
            return nil
        }
        return impact
    }

    func supports(swapType: SwapType) -> Bool {
        swapType.route == .dex
    }

    func detailsSection(swapType: SwapType) -> SwapDetailsSection {
        .dex
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
        let estimatedAmounts = result.dexEstimate.map {
            SwapInputModel.Estimate(
                changedFrom: result.changedFrom,
                fromAmount: $0.fromAmount.value,
                toAmount: $0.toAmount.value
            )
        }
        let backendMaxAmount = input.isMaxAmount ? result.dexEstimate.map {
            DecimalAmount.fromDouble($0.fromAmount.value, input.selling.token).roundedForSwap.amount
        } : nil
        return SwapEstimateUpdate(
            changedFrom: result.changedFrom,
            estimatedAmounts: estimatedAmounts,
            backendMaxAmount: backendMaxAmount,
            stateUpdate: result
        )
    }

    func maxAmountContext(
        swapType: SwapType,
        sellingToken: ApiToken,
        nativeTokenInBalance: BigInt?,
        state: SwapEstimateModel
    ) -> SwapMaxAmountContext {
        let explainedFee = explainSwapFee(.init(
            swapType: .onChain,
            tokenIn: sellingToken,
            networkFee: state.dexEstimate?.networkFee,
            realNetworkFee: state.dexEstimate?.realNetworkFee,
            dieselStatus: state.dexEstimate?.dieselStatus,
            dieselFee: state.dexEstimate?.dieselFee,
            nativeTokenInBalance: nativeTokenInBalance
        ))
        return SwapMaxAmountContext(
            swapType: .onChain,
            fullNetworkFee: explainedFee.fullFee?.networkTerms
        )
    }

    func buttonState(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapButtonState {
        presenter.buttonState(context: context, state: state)
    }

    func route(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapRoute? {
        presenter.route(context: context, state: state)
    }

    func performSwap(context: SwapExecutionContext, state: SwapEstimateModel) async throws -> SwapExecutionResult {
        guard let swapMode = state.swapMode else {
            throw SdkError.unexpected(message: "Missing swap estimate mode")
        }
        return try await executor.performSwap(
            swapEstimate: state.dexEstimate,
            swapMode: swapMode,
            confirmation: context.confirmation,
            maxAmount: context.maxAmount,
            slippage: context.slippage,
            account: context.account,
            enclaveToken: context.enclaveToken
        )
    }
}

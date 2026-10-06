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

    func previousNetworkFee(state: SwapEstimateModel) -> MDouble? {
        nil
    }

    func priceImpactWarning(state: SwapEstimateModel) -> Double? {
        nil
    }

    func supports(swapType: SwapType) -> Bool {
        swapType.route == .cex
    }

    func detailsSection(swapType: SwapType) -> SwapDetailsSection {
        .cex(swapType)
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
        let estimatedAmounts = result.cexEstimate.map {
            SwapInputModel.Estimate(
                changedFrom: result.changedFrom,
                fromAmount: $0.fromAmount,
                toAmount: $0.toAmount
            )
        }
        return SwapEstimateUpdate(
            changedFrom: result.changedFrom,
            estimatedAmounts: estimatedAmounts,
            backendMaxAmount: nil,
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
            swapType: swapType,
            tokenIn: sellingToken,
            networkFee: state.cexEstimate?.networkFee,
            realNetworkFee: state.cexEstimate?.realNetworkFee,
            dieselStatus: nil,
            dieselFee: nil,
            nativeTokenInBalance: nativeTokenInBalance
        ))
        return SwapMaxAmountContext(
            swapType: swapType,
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
        try await executor.performSwap(
            swapType: context.swapType,
            swapEstimate: state.cexEstimate,
            sellingToken: context.confirmation.selling.token,
            buyingToken: context.confirmation.buying.token,
            account: context.account,
            payoutAddress: context.payoutAddress,
            enclaveToken: context.enclaveToken
        )
    }
}

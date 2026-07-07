import Foundation
import WalletCore
import WalletContext
import Dependencies
import Perception
import AsyncAlgorithms

@MainActor protocol SwapModelDelegate: AnyObject {
    func applyButtonConfiguration(_ config: SwapButtonConfiguration)
    func executeSwapCommand(_ command: SwapCommand)
}

private let estimateRefreshInterval: Duration = .seconds(1.5)
private let estimateInputDebounce: Duration = .milliseconds(250)

private enum SwapModelIntent: Sendable {
    case inputChanged(side: SwapSide, source: SwapInputChangeSource)
    case slippageChanged
    case refreshTick
}

@Perceptible
@MainActor final class SwapModel {

    private(set) var isValidPair = true
    private(set) var swapType = SwapType.onChain

    private(set) var onchain = OnchainSwapModel()
    private(set) var crosschain = CrosschainSwapModel()
    let input: SwapInputModel
    let buttonModel = SwapButtonModel()
    private let contextModel = SwapContextModel()
    private let flows: SwapFlowRouter

    @PerceptionIgnored
    private weak var delegate: SwapModelDelegate?

    @PerceptionIgnored
    private let intents = AsyncChannel<SwapModelIntent>()
    @PerceptionIgnored
    private var intentTask: Task<Void, Never>?
    @PerceptionIgnored
    private var refreshTimerTask: Task<Void, Never>?
    @PerceptionIgnored
    private var debounceTask: Task<Void, Never>?
    @PerceptionIgnored
    private var estimateTask: Task<Void, Never>?
    @PerceptionIgnored
    private var estimateGate = SwapEstimateGate()
    @PerceptionIgnored
    private var isInputDebouncePending = false
    @PerceptionIgnored
    private var stage = SwapStage.editing
    private(set) var slippage = DEFAULT_SLIPPAGE
    @PerceptionIgnored
    private var currentTokenPair: (selling: String, buying: String)
    @PerceptionIgnored
    @AccountContext var account: MAccount

    deinit {
        intentTask?.cancel()
        refreshTimerTask?.cancel()
        debounceTask?.cancel()
        estimateTask?.cancel()
    }

    init(
        delegate: SwapModelDelegate,
        defaultSellingToken: String?,
        defaultBuyingToken: String?,
        defaultSellingAmount: Double?,
        accountContext: AccountContext
    ) {
        self.delegate = delegate
        self._account = accountContext

        @Dependency(\.tokenStore) var tokenStore
        let sellingToken = tokenStore.getToken(slugOrAddress: defaultSellingToken ?? TONCOIN_SLUG) ?? tokenStore.tokens[TONCOIN_SLUG]!
        let buyingToken = tokenStore.getToken(slugOrAddress: defaultBuyingToken ?? TON_USDT_SLUG) ?? tokenStore.tokens[TON_USDT_SLUG]!
        let tokenBalance = accountContext.balances[sellingToken.slug] ?? 0

        let inputModel = SwapInputModel(
            sellingTokenSlug: sellingToken.slug,
            buyingTokenSlug: buyingToken.slug,
            tokenBalance: tokenBalance,
            accountContext: accountContext
        )
        inputModel.sellingAmount = defaultSellingAmount.flatMap { doubleToBigInt($0, decimals: sellingToken.decimals) }
        self.input = inputModel
        let onchainValidator = OnchainSwapValidator()
        let crosschainValidator = CrosschainSwapValidator()
        self.flows = SwapFlowRouter(flows: [
            OnchainSwapFlow(validator: onchainValidator),
            CrosschainSwapFlow(validator: crosschainValidator)
        ])
        self.currentTokenPair = (sellingToken.slug, buyingToken.slug)
        self.swapType = contextModel.updateSwapType(
            selling: inputModel.sellingToken,
            buying: inputModel.buyingToken,
            accountChains: accountContext.account.supportedChains
        )
        self.input.updateBuyingAmountInputDisabled(
            contextModel.currentBuyAmountInputDisabled(
                selling: inputModel.sellingToken,
                buying: inputModel.buyingToken,
                accountChains: accountContext.account.supportedChains
            )
        )
        self.refreshInputMaxAmountContext()

        self.input.delegate = self
        self.startIntentStream()
        if inputModel.sellingAmount ?? 0 > 0 {
            self.sendIntent(.inputChanged(side: .selling, source: .user))
        }
    }

    func updateSwapType(selling: TokenAmount, buying: TokenAmount) {
        resetEstimateIfPairChanged(selling: selling.token, buying: buying.token)
        swapType = contextModel.updateSwapType(selling: selling.token, buying: buying.token, accountChains: account.supportedChains)
        input.updateBuyingAmountInputDisabled(
            contextModel.currentBuyAmountInputDisabled(
                selling: selling.token,
                buying: buying.token,
                accountChains: account.supportedChains
            )
        )
        refreshInputMaxAmountContext()
    }

    func setStage(_ stage: SwapStage) {
        self.stage = stage
        guard !stage.allowsEstimation else {
            applyCurrentButtonConfiguration()
            return
        }
        debounceTask?.cancel()
        estimateTask?.cancel()
        isInputDebouncePending = false
        estimateGate.reset()
        finishEstimating(applyButtonConfiguration: false)
    }

    func refreshBalances() {
        input.refreshTokenBalanceFromAccount()
        refreshInputMaxAmountContext()
        applyCurrentButtonConfiguration()
    }

    func onAccountSelected(accountId: String) async throws {
        guard accountId != account.id else { return }

        try await AccountStore.activateAccount(accountId: accountId)

        debounceTask?.cancel()
        estimateTask?.cancel()
        isInputDebouncePending = false
        estimateGate.reset()
        clearEstimates()
        $account.accountId = accountId
        input.refreshTokenBalanceFromAccount()
        updateSwapType(selling: input.sellingTokenAmount, buying: input.buyingTokenAmount)
        refreshInputMaxAmountContext()

        if currentEstimateInput() != nil {
            beginEstimating(changedFrom: input.inputSource)
            submitCurrentEstimate(visible: true)
        } else {
            finishEstimating()
        }
    }

    var displayImpactWarning: Double? {
        flow(for: swapType).priceImpactWarning(state: flowState)
    }

    var detailsSection: SwapDetailsSection {
        flow(for: swapType).detailsSection(swapType: swapType)
    }

    var detailsVM: SwapDetailsVM {
        SwapDetailsVM(onchainModel: onchain, inputModel: input)
    }

    func confirmationAmounts() -> SwapConfirmationAmounts? {
        guard
            let sellingAmount = input.sellingAmount,
            let buyingAmount = input.buyingAmount
        else {
            return nil
        }
        return SwapConfirmationAmounts(
            selling: TokenAmount(sellingAmount, input.sellingToken),
            buying: TokenAmount(buyingAmount, input.buyingToken)
        )
    }

    func continueRoute() -> SwapRoute? {
        guard let route = flow(for: swapType).route(context: currentPresentationContext(), state: flowState) else {
            return nil
        }
        guard route.allowsPriceImpactWarning, let impact = displayImpactWarning else {
            return route
        }
        return .priceImpactWarning(impact: impact, next: route)
    }

    func swapNow(
        confirmation: SwapConfirmationAmounts,
        passcode: String,
        payoutAddress: String? = nil
    ) async throws -> SwapExecutionResult {
        guard confirmation == confirmationAmounts() else {
            throw DisplayError(text: "Swap input changed")
        }
        return try await flow(for: swapType).performSwap(context: .init(
            swapType: swapType,
            confirmation: confirmation,
            maxAmount: input.maxAmount,
            slippage: slippage.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS),
            payoutAddress: payoutAddress,
            account: currentAccountSnapshot(),
            passcode: passcode
        ), state: flowState)
    }

    func commitSlippage(_ slippage: BigInt) {
        guard self.slippage != slippage else { return }
        self.slippage = slippage
        sendIntent(.slippageChanged)
    }
}

extension SwapModel: SwapInputModelDelegate {
    func swapDataChanged(
        swapSide: SwapSide,
        selling: TokenAmount,
        buying: TokenAmount,
        source: SwapInputChangeSource
    ) {
        sendIntent(.inputChanged(side: swapSide, source: source))
    }

    func swapCommandRequested(_ command: SwapCommand) {
        delegate?.executeSwapCommand(command)
    }
}

private extension SwapModel {
    func resetEstimateIfPairChanged(selling: ApiToken, buying: ApiToken) {
        let pair = (selling.slug, buying.slug)
        guard pair != currentTokenPair else { return }
        currentTokenPair = pair
        clearEstimates()
        estimateTask?.cancel()
        estimateGate.reset()
        applyCurrentButtonConfiguration()
    }

    func startIntentStream() {
        let intents = intents
        intentTask = Task { [weak self, intents] in
            for await intent in intents {
                guard !Task.isCancelled else { return }
                await self?.handleIntent(intent)
            }
        }
        refreshTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: estimateRefreshInterval)
                guard !Task.isCancelled else { return }
                self?.sendIntent(.refreshTick)
            }
        }
    }

    func sendIntent(_ intent: SwapModelIntent) {
        Task { [intents] in
            await intents.send(intent)
        }
    }

    func handleIntent(_ intent: SwapModelIntent) async {
        switch intent {
        case .inputChanged(let side, let source):
            handleInputChanged(side: side, source: source)
        case .slippageChanged:
            handleSlippageChanged()
        case .refreshTick:
            submitCurrentEstimate(visible: false)
        }
    }

    func handleInputChanged(side: SwapSide, source: SwapInputChangeSource) {
        updateSwapType(selling: input.sellingTokenAmount, buying: input.buyingTokenAmount)
        let amount = side == .selling ? input.sellingAmount : input.buyingAmount
        guard let amount, amount > 0 else {
            debounceTask?.cancel()
            isInputDebouncePending = false
            estimateGate.cancelFollowUp()
            input.clearEstimatedAmount(changedFrom: side)
            finishEstimating()
            applyButtonState(isValidPair ? .emptyAmount : .invalidPair)
            return
        }

        switch source {
        case .user:
            beginEstimating(changedFrom: side)
            scheduleDebouncedEstimate()
        case .maxAmountRecalculation:
            if estimateGate.isInFlight {
                applyCurrentButtonConfiguration()
            } else {
                beginEstimating(changedFrom: side)
                submitCurrentEstimate(visible: true)
            }
        }
    }

    func handleSlippageChanged() {
        guard flow(for: swapType).refreshesOnSlippageChange, currentEstimateInput() != nil else { return }
        beginEstimating(changedFrom: input.inputSource)
        submitCurrentEstimate(visible: true)
    }

    func scheduleDebouncedEstimate() {
        debounceTask?.cancel()
        isInputDebouncePending = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: estimateInputDebounce)
            guard !Task.isCancelled else { return }
            self?.isInputDebouncePending = false
            self?.submitCurrentEstimate(visible: true)
        }
    }

    func submitCurrentEstimate(visible: Bool) {
        guard stage.allowsEstimation else { return }
        guard visible || !isInputDebouncePending else { return }
        guard let estimateInput = currentEstimateInput() else { return }
        if visible {
            beginEstimating(changedFrom: estimateInput.inputSource)
        }
        guard estimateGate.start(estimateInput) else { return }
        estimateTask = Task { [weak self] in
            await self?.performEstimate(estimateInput)
        }
    }

    func performEstimate(_ estimateInput: SwapEstimateInput) async {
        var changedFromForReset = estimateInput.inputSource
        defer {
            if estimateGate.finish() {
                submitCurrentEstimate(visible: input.isEstimating)
            }
        }

        do {
            let account = currentAccountSnapshot()
            let context = try await contextModel.updateContext(
                selling: estimateInput.selling.token,
                buying: estimateInput.buying.token,
                accountChains: account.supportedChains
            )
            guard !Task.isCancelled, stage.allowsEstimation else { return }
            guard estimateInput.matchesCurrent(currentEstimateInput()) else { return }

            swapType = context.swapType
            isValidPair = context.isValidPair
            input.updateBuyingAmountInputDisabled(context.isBuyAmountInputDisabled)
            let effectiveChangedFrom: SwapSide = context.isBuyAmountInputDisabled && estimateInput.inputSource == .buying ? .selling : estimateInput.inputSource
            changedFromForReset = effectiveChangedFrom

            guard isValidPair else {
                input.clearEstimatedAmount(changedFrom: effectiveChangedFrom)
                finishEstimating()
                return
            }
            guard estimateInput.selling.amount > 0 || estimateInput.buying.amount > 0 else {
                input.clearEstimatedAmount(changedFrom: effectiveChangedFrom)
                finishEstimating()
                return
            }

            let flow = flow(for: context.swapType)
            let update = try await flow.estimate(
                estimateInput,
                changedFrom: effectiveChangedFrom,
                swapType: context.swapType,
                account: account
            )
            guard !Task.isCancelled, stage.allowsEstimation else { return }
            guard estimateInput.matchesCurrent(currentEstimateInput()) else { return }
            applyEstimate(update)
        } catch {
            if !(error is CancellationError) {
                input.clearEstimatedAmount(changedFrom: changedFromForReset)
                finishEstimating()
            }
        }
    }

    func currentEstimateInput() -> SwapEstimateInput? {
        let estimateInput = SwapEstimateInput(
            accountId: account.id,
            selling: input.sellingTokenAmount,
            buying: input.buyingTokenAmount,
            inputSource: input.inputSource,
            isMaxAmount: input.isUsingMax,
            maxAmount: input.maxAmount ?? input.tokenBalance,
            slippage: slippage.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS),
            previousNetworkFee: flow(for: swapType).previousNetworkFee(state: flowState),
            cexLabel: swapType == .onChain ? nil : crosschain.cexEstimate?.cexLabel
        )
        return estimateInput.inputAmount > 0 ? estimateInput : nil
    }

    var flowState: SwapFlowState {
        SwapFlowState(onchain: onchain, crosschain: crosschain)
    }

    func currentAccountSnapshot() -> SwapAccountSnapshot {
        SwapAccountSnapshot(account: account, balances: $account.balances)
    }

    func currentValidationInput() -> SwapValidationInput {
        SwapValidationInput(
            sellingToken: input.sellingToken,
            buyingToken: input.buyingToken,
            sellingAmount: input.sellingAmount,
            maxAmount: input.maxAmount,
            swapType: swapType
        )
    }

    func currentPresentationContext() -> SwapPresentationContext {
        SwapPresentationContext(
            swapType: swapType,
            isValidPair: isValidPair,
            hasEnteredAmount: input.sellingAmount != nil || input.buyingAmount != nil,
            isEstimating: input.isEstimating,
            validationInput: currentValidationInput(),
            confirmationAmounts: confirmationAmounts(),
            account: currentAccountSnapshot()
        )
    }

    func flow(for swapType: SwapType) -> any SwapFlow {
        flows.flow(for: swapType)
    }

    func applyEstimate(_ update: SwapEstimateUpdate) {
        guard !update.keepsCurrentState else {
            applyCurrentButtonConfiguration()
            return
        }
        applyStateUpdate(update.stateUpdate)
        update.apply(to: input)
        finishEstimating(applyButtonConfiguration: false)
        guard isValidPair else {
            applyCurrentButtonConfiguration()
            return
        }

        refreshInputMaxAmountContext(notifyAmountChange: false)
        applyCurrentButtonConfiguration()
    }

    func beginEstimating(changedFrom: SwapSide) {
        input.startEstimating(changedFrom: changedFrom)
        applyCurrentButtonConfiguration()
    }

    func finishEstimating(applyButtonConfiguration: Bool = true) {
        input.finishEstimating()
        if applyButtonConfiguration {
            applyCurrentButtonConfiguration()
        }
    }

    func refreshInputMaxAmountContext(notifyAmountChange: Bool = true) {
        let sellingToken = input.sellingToken
        guard let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] else {
            input.updateMaxAmountContext(
                swapType: swapType,
                fullNetworkFee: nil,
                ourFeePercent: nil,
                notifyAmountChange: notifyAmountChange
            )
            return
        }

        let nativeTokenInBalance = $account.balances[nativeToken.slug]
        let context = flow(for: swapType).maxAmountContext(
            swapType: swapType,
            sellingToken: sellingToken,
            nativeTokenInBalance: nativeTokenInBalance,
            state: flowState
        )
        input.updateMaxAmountContext(
            swapType: context.swapType,
            fullNetworkFee: context.fullNetworkFee,
            ourFeePercent: context.ourFeePercent,
            notifyAmountChange: notifyAmountChange
        )
    }

    func applyCurrentButtonConfiguration() {
        let state = flow(for: swapType).buttonState(context: currentPresentationContext(), state: flowState)
        applyButtonState(state)
    }

    func applyButtonState(_ state: SwapButtonState) {
        delegate?.applyButtonConfiguration(buttonModel.configuration(
            for: state,
            sellingToken: input.sellingToken,
            buyingToken: input.buyingToken
        ))
    }

    func clearEstimates() {
        onchain = OnchainSwapModel()
        crosschain = CrosschainSwapModel()
    }

    func applyStateUpdate(_ update: SwapEstimateStateUpdate?) {
        guard let update else { return }
        switch update {
        case .onchain(let result):
            var next = onchain
            next.applyEstimate(result)
            onchain = next
        case .crosschain(let result):
            var next = crosschain
            next.applyEstimate(result)
            crosschain = next
        }
    }
}

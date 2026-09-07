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

/// The longest gap a run of failing estimates can stretch the refresh to, counted in ticks.
let maxEstimateBackoffTicks = 32

/// How many ticks to let pass before the next attempt, given how many in a row have failed.
///
/// The refresh follows a moving market, which a failing estimate is not doing: a pair with no route,
/// or an amount the network fee already exceeds, answers the same way however often it is asked. The
/// first retry stays immediate, since one failure is most cheaply explained as a blip, and only a run
/// of them is evidence of something that asking again will not resolve.
func estimateTicksToWait(failedAttempts: Int) -> Int {
    // `maxEstimateBackoffTicks` is the only ceiling here; the shift is clamped purely to keep it in range.
    let doublings = min(max(failedAttempts - 1, 0), Int.bitWidth - 2)
    return min(1 << doublings, maxEstimateBackoffTicks)
}

private enum SwapModelIntent: Sendable {
    case inputChanged(side: SwapSide, source: SwapInputChangeSource)
    case slippageChanged
    case refreshTick
}

@Perceptible
@MainActor final class SwapModel {

    private(set) var isValidPair = true
    private(set) var swapType = SwapType.onChain

    private(set) var estimateState = SwapEstimateModel()
    var hint: SwapHint? {
        SwapHint.resolve(
            estimate: estimateState.response(for: currentEstimateInput()),
            accountContext: $account,
            sellingToken: input.sellingToken,
            buyingToken: input.buyingToken
        )
    }
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
    private var failedEstimateAttempts = 0
    @PerceptionIgnored
    private var ticksSinceEstimateAttempt = 0
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
    private var currentTokenPair: (selling: String?, buying: String?)
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
        defaults: ApiSwapDefaults,
        defaultSellingAmount: Double?,
        defaultBuyingAmount: Double? = nil,
        accountContext: AccountContext
    ) {
        self.delegate = delegate
        self._account = accountContext
        let sellingToken = defaults.tokenIn
        let buyingToken = defaults.tokenOut
        let tokenBalance = sellingToken.map { accountContext.balances[$0.slug] ?? 0 }

        let inputModel = SwapInputModel(
            sellingTokenSlug: sellingToken?.slug,
            buyingTokenSlug: buyingToken?.slug,
            tokenBalance: tokenBalance,
            accountContext: accountContext
        )
        inputModel.sellingAmount = sellingToken.flatMap { token in
            defaultSellingAmount.flatMap { doubleToBigInt($0, decimals: token.decimals) }
        }
        inputModel.buyingAmount = buyingToken.flatMap { token in
            defaultBuyingAmount.flatMap { doubleToBigInt($0, decimals: token.decimals) }
        }
        inputModel.inputSource = defaultBuyingAmount == nil ? .selling : .buying
        self.input = inputModel
        let onchainValidator = OnchainSwapValidator()
        let crosschainValidator = CrosschainSwapValidator()
        self.flows = SwapFlowRouter(flows: [
            OnchainSwapFlow(validator: onchainValidator),
            CrosschainSwapFlow(validator: crosschainValidator)
        ])
        self.currentTokenPair = (sellingToken?.slug, buyingToken?.slug)
        self.updateSwapType()

        self.input.delegate = self
        self.startIntentStream()
        if inputModel.buyingAmount ?? 0 > 0 {
            self.sendIntent(.inputChanged(side: .buying, source: .user))
        } else if inputModel.sellingAmount ?? 0 > 0 {
            self.sendIntent(.inputChanged(side: .selling, source: .user))
        }
    }

    func updateSwapType() {
        resetEstimateIfPairChanged(selling: input.sellingToken, buying: input.buyingToken)
        guard let selling = input.sellingToken, let buying = input.buyingToken else { return }
        swapType = contextModel.updateSwapType(selling: selling, buying: buying, accountChains: account.supportedChains)
        input.updateBuyingAmountInputDisabled(
            contextModel.currentBuyAmountInputDisabled(
                selling: selling,
                buying: buying,
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

    func performHintAction(_ hint: SwapHint) {
        guard hint == self.hint else { return }
        switch hint {
        case .receive(let chain, _), .belowMinimum(let chain):
            let buyingToken: ApiToken? = input.buyingToken
            AppActions.showReceive(accountContext: $account, chain: chain, buyingToken: buyingToken?.slug)
        case .intermediate(let token, _):
            input.userSelectedToken(token, side: .buying)
        case .external(_, let url):
            guard url.scheme == "https", url.host != nil else { return }
            AppActions.openInBrowser(url)
        }
    }

    func onAccountSelected(accountId: String) async throws {
        guard accountId != account.id else { return }

        try await AccountStore.activateAccount(accountId: accountId)

        debounceTask?.cancel()
        estimateTask?.cancel()
        isInputDebouncePending = false
        estimateGate.reset()
        resetEstimateBackoff()
        clearEstimates()
        $account.accountId = accountId
        input.refreshTokenBalanceFromAccount()
        updateSwapType()
        refreshInputMaxAmountContext()

        if currentEstimateInput() != nil {
            beginEstimating(changedFrom: input.inputSource)
            submitCurrentEstimate(visible: true)
        } else {
            finishEstimating()
        }
    }

    var displayImpactWarning: Double? {
        flow(for: swapType).priceImpactWarning(state: estimateState)
    }

    var detailsSection: SwapDetailsSection {
        flow(for: swapType).detailsSection(swapType: swapType)
    }

    var detailsVM: SwapDetailsVM {
        SwapDetailsVM(swapEstimate: estimateState.dexEstimate, inputModel: input)
    }

    func confirmationAmounts() -> SwapConfirmationAmounts? {
        guard
            let sellingToken = input.sellingToken,
            let buyingToken = input.buyingToken,
            let sellingAmount = input.sellingAmount,
            let buyingAmount = input.buyingAmount
        else {
            return nil
        }
        return SwapConfirmationAmounts(
            selling: TokenAmount(sellingAmount, sellingToken),
            buying: TokenAmount(buyingAmount, buyingToken)
        )
    }

    func continueRoute() -> SwapRoute? {
        guard let context = currentPresentationContext(),
              let route = flow(for: swapType).route(context: context, state: estimateState) else {
            return nil
        }
        guard route.allowsPriceImpactWarning, let impact = displayImpactWarning else {
            return route
        }
        return .priceImpactWarning(impact: impact, next: route)
    }

    func makeConfirmationSnapshot(payoutAddress: String? = nil) -> SwapConfirmationSnapshot? {
        guard let confirmation = confirmationAmounts() else { return nil }
        return SwapConfirmationSnapshot(
            swapType: swapType,
            confirmation: confirmation,
            maxAmount: input.maxAmount,
            slippage: slippage.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS),
            payoutAddress: payoutAddress,
            account: currentAccountSnapshot(),
            estimateState: estimateState
        )
    }

    func performSwap(snapshot: SwapConfirmationSnapshot, enclaveToken: EnclaveToken) async throws -> SwapExecutionResult {
        try await flow(for: snapshot.swapType).performSwap(context: .init(
            swapType: snapshot.swapType,
            confirmation: snapshot.confirmation,
            maxAmount: snapshot.maxAmount,
            slippage: snapshot.slippage,
            payoutAddress: snapshot.payoutAddress,
            account: snapshot.account,
            enclaveToken: enclaveToken
        ), state: snapshot.estimateState)
    }

    func commitSlippage(_ slippage: BigInt) {
        guard self.slippage != slippage else { return }
        self.slippage = slippage
        estimateState.invalidateHint()
        sendIntent(.slippageChanged)
    }
}

extension SwapModel: SwapInputModelDelegate {
    func swapDataChanged(
        swapSide: SwapSide,
        source: SwapInputChangeSource
    ) {
        sendIntent(.inputChanged(side: swapSide, source: source))
    }

    func swapCommandRequested(_ command: SwapCommand) {
        delegate?.executeSwapCommand(command)
    }
}

private extension SwapModel {
    func resetEstimateIfPairChanged(selling: ApiToken?, buying: ApiToken?) {
        let pair = (selling?.slug, buying?.slug)
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
            handleRefreshTick()
        }
    }

    func handleRefreshTick() {
        ticksSinceEstimateAttempt += 1
        guard ticksSinceEstimateAttempt >= estimateTicksToWait(failedAttempts: failedEstimateAttempts) else {
            return
        }

        // A tick that turns out to have nothing to send - a form past editing, or one still holding
        // an input debounce - keeps the wait it had earned and sends the moment it can again.
        submitCurrentEstimate(visible: false)
    }

    /// Clears the backoff, so an estimate the user asked for is never made to wait behind it.
    func resetEstimateBackoff() {
        failedEstimateAttempts = 0
        ticksSinceEstimateAttempt = 0
    }

    func handleInputChanged(side: SwapSide, source: SwapInputChangeSource) {
        resetEstimateBackoff()
        updateSwapType()
        let amount = side == .selling ? input.sellingAmount : input.buyingAmount
        guard input.sellingToken != nil, input.buyingToken != nil, let amount, amount > 0 else {
            debounceTask?.cancel()
            isInputDebouncePending = false
            estimateGate.cancelFollowUp()
            if input.sellingToken != nil, input.buyingToken != nil {
                input.clearEstimatedAmount(changedFrom: side)
            }
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
        resetEstimateBackoff()
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

    /// Starts an estimate, and reports whether one actually began.
    ///
    /// Every reason to decline is a reason not to charge the caller for an attempt, so the answer is
    /// the method's own rather than a set of conditions each caller has to restate and keep in step.
    @discardableResult
    func submitCurrentEstimate(visible: Bool) -> Bool {
        guard stage.allowsEstimation else { return false }
        guard visible || !isInputDebouncePending else { return false }
        guard let estimateInput = currentEstimateInput() else { return false }
        if visible {
            beginEstimating(changedFrom: estimateInput.inputSource)
        }
        guard let slot = estimateGate.start(estimateInput) else { return false }

        // The wait is measured from the last attempt that actually began, whichever path began it -
        // a refresh tick, an edit, or the follow-up that runs when an estimate in flight finishes.
        ticksSinceEstimateAttempt = 0
        estimateTask = Task { [weak self] in
            await self?.performEstimate(estimateInput, slot: slot)
        }
        return true
    }

    func performEstimate(_ estimateInput: SwapEstimateInput, slot: SwapEstimateGate.Slot) async {
        var changedFromForReset = estimateInput.inputSource
        defer {
            if estimateGate.finish(slot) {
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
            isValidPair = isSwapPairInAccountScope(
                selling: estimateInput.selling.token,
                buying: estimateInput.buying.token,
                accountChains: account.supportedChains
            )
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
                // The backoff belongs to the inputs on screen, the same way the applied estimate does.
                // A request the user has since edited away from says nothing about them.
                if estimateInput.matchesCurrent(currentEstimateInput()) {
                    failedEstimateAttempts += 1
                }
                input.clearEstimatedAmount(changedFrom: changedFromForReset)
                finishEstimating()
            }
        }
    }

    func currentEstimateInput() -> SwapEstimateInput? {
        guard let selling = input.sellingTokenAmount, let buying = input.buyingTokenAmount else { return nil }
        let estimateInput = SwapEstimateInput(
            accountId: account.id,
            selling: selling,
            buying: buying,
            inputSource: input.inputSource,
            isMaxAmount: input.isUsingMax,
            maxAmount: input.maxAmount ?? input.tokenBalance,
            slippage: slippage.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS),
            previousNetworkFee: flow(for: swapType).previousNetworkFee(state: estimateState),
            cexLabel: swapType.route == .dex ? nil : estimateState.cexEstimate?.cexLabel
        )
        return estimateInput.inputAmount > 0 ? estimateInput : nil
    }

    func currentAccountSnapshot() -> SwapAccountSnapshot {
        SwapAccountSnapshot(account: account, balances: $account.balances)
    }

    func currentPresentationContext() -> SwapPresentationContext? {
        guard let sellingToken = input.sellingToken, let buyingToken = input.buyingToken else { return nil }
        return SwapPresentationContext(
            swapType: swapType,
            isValidPair: isValidPair,
            hasEnteredAmount: input.sellingAmount != nil || input.buyingAmount != nil,
            isEstimating: input.isEstimating,
            validationInput: SwapValidationInput(
                sellingToken: sellingToken,
                buyingToken: buyingToken,
                sellingAmount: input.sellingAmount,
                maxAmount: input.maxAmount,
                swapType: swapType
            ),
            confirmationAmounts: confirmationAmounts(),
            account: currentAccountSnapshot()
        )
    }

    func flow(for swapType: SwapType) -> any SwapFlow {
        flows.flow(for: swapType)
    }

    func applyEstimate(_ update: SwapEstimateUpdate) {
        // A quote is the market answering, so the refresh returns to following it at full rate. An
        // attempt that came back without one is a failure the engines report in place of throwing.
        if update.hasQuote {
            failedEstimateAttempts = 0
            isValidPair = true
        } else {
            failedEstimateAttempts += 1
        }

        guard !update.keepsCurrentState else {
            applyCurrentButtonConfiguration()
            return
        }
        applyStateUpdate(update.stateUpdate)
        if update.stateUpdate?.estimateIssue == .invalidPair {
            isValidPair = false
        }
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
        guard let sellingToken = input.sellingToken else { return }
        guard let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] else {
            input.updateMaxAmountContext(
                swapType: swapType,
                fullNetworkFee: nil,
                notifyAmountChange: notifyAmountChange
            )
            return
        }

        let nativeTokenInBalance = $account.balances[nativeToken.slug]
        let context = flow(for: swapType).maxAmountContext(
            swapType: swapType,
            sellingToken: sellingToken,
            nativeTokenInBalance: nativeTokenInBalance,
            state: estimateState
        )
        input.updateMaxAmountContext(
            swapType: context.swapType,
            fullNetworkFee: context.fullNetworkFee,
            notifyAmountChange: notifyAmountChange
        )
    }

    func applyCurrentButtonConfiguration() {
        let state = currentPresentationContext().map {
            flow(for: swapType).buttonState(context: $0, state: estimateState)
        } ?? .emptyAmount
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
        estimateState.clear()
    }

    func applyStateUpdate(_ update: SwapEstimateResult?) {
        guard let update else { return }
        estimateState.apply(update, input: currentEstimateInput())
    }
}

import Foundation
import UIComponents
import WalletCore
import WalletContext
import Dependencies
import Perception

@MainActor protocol SwapModelDelegate: AnyObject {
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

@Perceptible
@MainActor final class SwapModel {

    private(set) var isValidPair = true
    private(set) var swapType = SwapType.onChain
    private(set) var slippage = DEFAULT_SLIPPAGE

    var hint: SwapHint? {
        SwapHint.resolve(
            estimate: estimate.current?.draft.stateUpdate?.response,
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
    private(set) var estimate: DraftEngine<SwapEstimateRequest, SwapEstimateUpdate>!

    @PerceptionIgnored
    private weak var delegate: SwapModelDelegate?
    @PerceptionIgnored
    private var failedEstimateAttempts = 0
    @PerceptionIgnored
    private var lastEstimateRequest: SwapEstimateRequest?
    private var stage = SwapStage.editing
    var isSubmitting: Bool { stage == .confirming }
    @PerceptionIgnored
    private var currentTokenPair: (selling: String?, buying: String?)
    @PerceptionIgnored
    @AccountContext var account: MAccount

    init(
        delegate: SwapModelDelegate,
        defaults: ApiSwapDefaults,
        defaultSellingAmount: Double?,
        defaultBuyingAmount: Double? = nil,
        accountContext: AccountContext,
        estimateLoader: DraftEngine<SwapEstimateRequest, SwapEstimateUpdate>.Loader? = nil
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
        self.estimate = DraftEngine(
            debounce: { from, to in
                // Only a typed amount on the same pair and side debounces;
                // picks — tokens, side, Max, slippage — estimate now.
                guard let from,
                      from.accountId == to.accountId,
                      from.sellingSlug == to.sellingSlug,
                      from.buyingSlug == to.buyingSlug,
                      from.side == to.side,
                      from.slippage == to.slippage,
                      case .exact = from.amount,
                      case .exact = to.amount else {
                    return .zero
                }
                return estimateInputDebounce
            },
            refreshInterval: estimateRefreshInterval,
            sameScope: {
                // Estimates stay displayable for the same pair; changing
                // either token clears them.
                $0.accountId == $1.accountId
                    && $0.sellingSlug == $1.sellingSlug
                    && $0.buyingSlug == $1.buyingSlug
            },
            load: estimateLoader ?? { [weak self] request, previous in
                guard let self else { throw CancellationError() }
                return try await loadEstimate(request, previous: previous)
            }
        )
        self.updateSwapType()

        self.input.delegate = self
        self.input.isEstimatingProvider = { [weak self] in
            self?.estimate.isLoading ?? false
        }
        estimate.onLoad = { [weak self] snapshot in
            self?.applyEstimate(snapshot.draft)
        }
        estimate.onFailure = { [weak self] request, _ in
            guard let self else { return }
            recordEstimateOutcome(hasQuote: false)
            // A refresh failure (a rate limit, a transient error) keeps
            // the current estimate displayable — its derived amount stays.
            // Only a blocking failure clears the opposite side.
            guard estimate.current == nil else { return }
            input.clearEstimatedAmount(changedFrom: request.side)
        }
        estimate.start { [weak self] in
            self?.currentEstimateRequest
        }
    }

    /// Keeps the previous quote visible while edited inputs are estimated.
    var estimateState: SwapEstimateModel {
        SwapEstimateModel(estimate.displayed?.stateUpdate)
    }

    /// A matching quote remains usable during periodic refreshes and rate
    /// limits. Changed inputs must receive their own quote before continuing.
    private var currentEstimateState: SwapEstimateModel {
        SwapEstimateModel(estimate.current?.draft.stateUpdate)
    }

    func updateSwapType() {
        let pair = (input.sellingToken?.slug, input.buyingToken?.slug)
        if pair != currentTokenPair {
            currentTokenPair = pair
            isValidPair = true
        }
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
        if stage.allowsEstimation {
            estimate.resume()
        } else {
            estimate.pause()
        }
    }

    func refreshBalances() {
        input.refreshTokenBalanceFromAccount()
        refreshInputMaxAmountContext()
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
        $account.accountId = accountId
        // The same pair can be valid in the newly selected account.
        isValidPair = true
        input.refreshTokenBalanceFromAccount()
        updateSwapType()
        refreshInputMaxAmountContext()
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

    var currentButtonConfiguration: DraftButtonConfiguration {
        let state = currentPresentationContext().map {
            flow(for: swapType).buttonState(context: $0, state: currentEstimateState)
        } ?? .emptyAmount
        return buttonModel.configuration(
            for: isSubmitting ? .submitting : state,
            sellingToken: input.sellingToken,
            buyingToken: input.buyingToken
        )
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
        guard stage == .editing else { return nil }
        let state = currentEstimateState
        guard let context = currentPresentationContext(),
              let route = flow(for: swapType).route(context: context, state: state) else {
            return nil
        }
        guard route.allowsPriceImpactWarning,
              let impact = flow(for: swapType).priceImpactWarning(state: state) else {
            return route
        }
        return .priceImpactWarning(impact: impact, next: route)
    }

    func makeConfirmationSnapshot(payoutAddress: String? = nil) -> SwapConfirmationSnapshot? {
        let state = currentEstimateState
        guard let context = currentPresentationContext(),
              let confirmation = context.confirmationAmounts else { return nil }
        switch flow(for: swapType).buttonState(context: context, state: state) {
        case .readyToSwap, .readyToContinue:
            break
        default:
            return nil
        }
        return SwapConfirmationSnapshot(
            swapType: swapType,
            confirmation: confirmation,
            maxAmount: input.maxAmount,
            slippage: slippage.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS),
            payoutAddress: payoutAddress,
            account: currentAccountSnapshot(),
            estimateState: state
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
    }
}

extension SwapModel: SwapInputModelDelegate {
    func swapDataChanged(
        swapSide: SwapSide,
        source: SwapInputChangeSource
    ) {
        // Pair context updates synchronously; the estimate engine observes
        // the request derivation and reloads on its own.
        updateSwapType()
        // Deleting the driving amount idles the engine, so the derived
        // opposite side clears here.
        let amount = swapSide == .selling ? input.sellingAmount : input.buyingAmount
        if input.sellingToken != nil, input.buyingToken != nil, (amount ?? 0) <= 0 {
            input.clearEstimatedAmount(changedFrom: swapSide)
        }
    }

    func swapCommandRequested(_ command: SwapCommand) {
        delegate?.executeSwapCommand(command)
    }
}

private extension SwapModel {
    var currentEstimateRequest: SwapEstimateRequest? {
        guard let selling = input.sellingToken, let buying = input.buyingToken else { return nil }
        return SwapEstimateRequest.derive(
            accountId: account.id,
            input: input,
            isValidPair: isSwapPairInAccountScope(
                selling: selling,
                buying: buying,
                accountChains: account.supportedChains
            ),
            slippage: slippage.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS)
        )
    }

    func loadEstimate(
        _ request: SwapEstimateRequest,
        previous: SwapEstimateUpdate?
    ) async throws -> SwapEstimateUpdate {
        guard request == currentEstimateRequest,
              let estimateInput = makeEstimateInput(request: request, previous: previous) else {
            throw CancellationError()
        }
        if lastEstimateRequest != request {
            lastEstimateRequest = request
            failedEstimateAttempts = 0
            estimate.refreshInterval = estimateRefreshInterval
        }
        let account = currentAccountSnapshot()
        let context = try await contextModel.updateContext(
            selling: estimateInput.selling.token,
            buying: estimateInput.buying.token,
            accountChains: account.supportedChains
        )
        guard request == currentEstimateRequest else { throw CancellationError() }
        swapType = context.swapType
        isValidPair = isSwapPairInAccountScope(
            selling: estimateInput.selling.token,
            buying: estimateInput.buying.token,
            accountChains: account.supportedChains
        )
        input.updateBuyingAmountInputDisabled(context.isBuyAmountInputDisabled)
        guard request == currentEstimateRequest else { throw CancellationError() }
        return try await flow(for: context.swapType).estimate(
            estimateInput,
            changedFrom: request.side,
            swapType: context.swapType,
            account: account
        )
    }

    func makeEstimateInput(
        request: SwapEstimateRequest,
        previous: SwapEstimateUpdate?
    ) -> SwapEstimateInput? {
        guard let selling = input.sellingTokenAmount, let buying = input.buyingTokenAmount else { return nil }
        let isMaxAmount: Bool
        if case .max = request.amount {
            isMaxAmount = true
        } else {
            isMaxAmount = false
        }
        let previousResult = previous?.stateUpdate
        return SwapEstimateInput(
            accountId: request.accountId,
            selling: selling,
            buying: buying,
            inputSource: request.side,
            isMaxAmount: isMaxAmount,
            maxAmount: input.maxAmount ?? input.tokenBalance,
            slippage: request.slippage,
            previousNetworkFee: previousResult?.dexEstimate?.networkFee,
            cexLabel: swapType.route == .dex ? nil : previousResult?.cexEstimate?.cexLabel
        )
    }

    func recordEstimateOutcome(hasQuote: Bool) {
        failedEstimateAttempts = hasQuote ? 0 : failedEstimateAttempts + 1
        estimate.refreshInterval = estimateRefreshInterval * estimateTicksToWait(failedAttempts: failedEstimateAttempts)
    }

    func applyEstimate(_ update: SwapEstimateUpdate) {
        recordEstimateOutcome(hasQuote: update.hasQuote)
        if update.hasQuote {
            isValidPair = true
        } else if update.stateUpdate?.estimateIssue == .invalidPair {
            isValidPair = false
        }
        // Writes the estimated opposite side and the backend maximum into
        // the form. Neither is part of the request, so this cannot start
        // another estimate; the periodic tick owns refreshes.
        update.apply(to: input)
        refreshInputMaxAmountContext(notifyAmountChange: false)
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
            isEstimating: estimate.isLoading,
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
}

import WalletCore

struct SwapPresentationContext {
    let swapType: SwapType
    let isValidPair: Bool
    let hasEnteredAmount: Bool
    let isEstimating: Bool
    let validationInput: SwapValidationInput
    let confirmationAmounts: SwapConfirmationAmounts?
    let account: SwapAccountSnapshot
}

@MainActor struct OnchainSwapPresenter {
    private let validator: OnchainSwapValidator

    init(validator: OnchainSwapValidator) {
        self.validator = validator
    }

    func buttonState(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapButtonState {
        guard context.isValidPair else {
            return .invalidPair
        }
        guard context.hasEnteredAmount else {
            return .emptyAmount
        }
        if let issue = blockingIssue(context: context, state: state) {
            return .blocked(issue)
        }
        if context.isEstimating {
            return .estimating(showContinue: false)
        }
        guard state.dexEstimate != nil else {
            return .waitingForEstimate
        }
        if validator.requiresDieselAuthorization(
            input: context.validationInput,
            swapEstimate: state.dexEstimate,
            account: context.account
        ) {
            return .authorizeDiesel
        }
        return .readyToSwap
    }

    func route(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapRoute? {
        switch buttonState(context: context, state: state) {
        case .authorizeDiesel:
            return .authorizeDiesel
        case .readyToSwap:
            return .confirmSwap(presentCrosschainResult: false)
        default:
            return nil
        }
    }

    private func blockingIssue(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapIssue? {
        if let estimateIssue = state.estimateIssue {
            return estimateIssue
        }
        return validator.validationIssue(
            input: context.validationInput,
            swapEstimate: state.dexEstimate,
            account: context.account
        )
    }
}

@MainActor struct CrosschainSwapPresenter {
    private let validator: CrosschainSwapValidator

    init(validator: CrosschainSwapValidator) {
        self.validator = validator
    }

    func buttonState(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapButtonState {
        guard context.isValidPair else {
            return .invalidPair
        }
        guard context.hasEnteredAmount else {
            return .emptyAmount
        }
        let shouldShowContinue = shouldShowContinue(context: context)
        if let issue = blockingIssue(context: context, state: state) {
            return .blocked(issue)
        }
        if context.isEstimating {
            return .estimating(showContinue: shouldShowContinue)
        }
        guard state.cexEstimate != nil else {
            return .waitingForEstimate
        }
        return shouldShowContinue ? .readyToContinue : .readyToSwap
    }

    func route(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapRoute? {
        switch buttonState(context: context, state: state) {
        case .readyToSwap, .readyToContinue:
            break
        default:
            return nil
        }
        switch context.swapType.cexTopology {
        case .fromWallet:
            guard let amounts = context.confirmationAmounts else {
                return nil
            }
            return .crosschainFromWallet(.init(
                selling: amounts.selling,
                buying: amounts.buying,
                cexLabel: state.cexEstimate?.cexLabel
            ))
        case .toWallet:
            return .confirmSwap(presentCrosschainResult: true)
        case .insideWallet:
            return .confirmSwap(presentCrosschainResult: false)
        case nil:
            return nil
        }
    }

    private func blockingIssue(context: SwapPresentationContext, state: SwapEstimateModel) -> SwapIssue? {
        if let estimateIssue = state.estimateIssue {
            return estimateIssue
        }
        return validator.validationIssue(
            input: context.validationInput,
            swapEstimate: state.cexEstimate,
            account: context.account
        )
    }

    private func shouldShowContinue(context: SwapPresentationContext) -> Bool {
        context.swapType.cexTopology == .fromWallet
            && context.account.supports(chain: context.validationInput.buyingToken.chain) == false
    }
}

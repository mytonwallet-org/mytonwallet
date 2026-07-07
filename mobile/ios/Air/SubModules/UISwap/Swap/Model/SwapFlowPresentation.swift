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

    func buttonState(context: SwapPresentationContext, state: OnchainSwapModel) -> SwapButtonState {
        guard context.isValidPair else {
            return .invalidPair
        }
        guard context.hasEnteredAmount else {
            return .emptyAmount
        }
        if context.isEstimating {
            return .estimating(showContinue: false)
        }
        if let issue = blockingIssue(context: context, state: state) {
            return .blocked(issue)
        }
        guard state.swapEstimate != nil else {
            return .waitingForEstimate
        }
        if validator.requiresDieselAuthorization(
            input: context.validationInput,
            swapEstimate: state.swapEstimate,
            account: context.account
        ) {
            return .authorizeDiesel
        }
        return .readyToSwap
    }

    func route(context: SwapPresentationContext, state: OnchainSwapModel) -> SwapRoute? {
        guard state.swapEstimate != nil else {
            return nil
        }
        if validator.requiresDieselAuthorization(
            input: context.validationInput,
            swapEstimate: state.swapEstimate,
            account: context.account
        ) {
            return .authorizeDiesel
        }
        return .confirmSwap(presentCrosschainResult: false)
    }

    private func blockingIssue(context: SwapPresentationContext, state: OnchainSwapModel) -> SwapIssue? {
        if let estimateIssue = state.estimateIssue {
            return estimateIssue
        }
        return validator.validationIssue(
            input: context.validationInput,
            swapEstimate: state.swapEstimate,
            account: context.account
        )
    }
}

@MainActor struct CrosschainSwapPresenter {
    private let validator: CrosschainSwapValidator

    init(validator: CrosschainSwapValidator) {
        self.validator = validator
    }

    func buttonState(context: SwapPresentationContext, state: CrosschainSwapModel) -> SwapButtonState {
        guard context.isValidPair else {
            return .invalidPair
        }
        guard context.hasEnteredAmount else {
            return .emptyAmount
        }
        let shouldShowContinue = shouldShowContinue(context: context)
        if context.isEstimating {
            return .estimating(showContinue: shouldShowContinue)
        }
        if let issue = blockingIssue(context: context, state: state) {
            return .blocked(issue)
        }
        guard state.cexEstimate != nil else {
            return .waitingForEstimate
        }
        return shouldShowContinue ? .readyToContinue : .readyToSwap
    }

    func route(context: SwapPresentationContext, state: CrosschainSwapModel) -> SwapRoute? {
        guard state.cexEstimate != nil else {
            return nil
        }
        switch context.swapType {
        case .crosschainFromWallet:
            guard let amounts = context.confirmationAmounts else {
                return nil
            }
            return .crosschainFromWallet(.init(
                selling: amounts.selling,
                buying: amounts.buying,
                cexLabel: state.cexEstimate?.cexLabel
            ))
        case .crosschainToWallet:
            return .confirmSwap(presentCrosschainResult: true)
        case .crosschainInsideWallet:
            return .confirmSwap(presentCrosschainResult: false)
        case .onChain:
            return nil
        }
    }

    private func blockingIssue(context: SwapPresentationContext, state: CrosschainSwapModel) -> SwapIssue? {
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
        context.swapType == .crosschainFromWallet
            && context.account.supports(chain: context.validationInput.buyingToken.chain) == false
    }
}

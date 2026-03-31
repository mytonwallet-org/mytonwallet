import WalletContext
import WalletCore

struct SwapContext {
    let selling: ApiToken
    let buying: ApiToken
    let swapType: SwapType
    let isValidPair: Bool
    let isBuyAmountInputDisabled: Bool
}

@MainActor final class SwapContextModel {
    private let pairModel = SwapPairModel()
    private(set) var swapType: SwapType = .onChain
    private(set) var isValidPair = true
    private(set) var context: SwapContext?

    func updateSwapType(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) -> SwapType {
        let swapType = getSwapType(from: selling.slug, to: buying.slug, accountChains: accountChains)
        self.swapType = swapType
        return swapType
    }

    func currentBuyAmountInputDisabled(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) -> Bool {
        let swapType = getSwapType(from: selling.slug, to: buying.slug, accountChains: accountChains)
        guard swapType == .onChain else { return true }
        return pairModel.cachedIsReverseProhibited(selling: selling, buying: buying) ?? true
    }

    func updateContext(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) async throws -> SwapContext {
        let swapType = updateSwapType(selling: selling, buying: buying, accountChains: accountChains)
        let pairState = try await pairModel.updatePair(selling: selling, buying: buying)
        let isValidPair = pairState.isValidPair
        self.isValidPair = isValidPair
        let context = SwapContext(
            selling: selling,
            buying: buying,
            swapType: swapType,
            isValidPair: isValidPair,
            isBuyAmountInputDisabled: swapType != .onChain || pairState.isReverseProhibited
        )
        self.context = context
        return context
    }
}

@MainActor private final class SwapPairModel {
    struct PairState {
        let isValidPair: Bool
        let isReverseProhibited: Bool
    }

    var prevPair: (String, String) = ("", "")
    var pairState = PairState(isValidPair: true, isReverseProhibited: false)

    func updatePair(selling: ApiToken, buying: ApiToken) async throws -> PairState {
        let pair = (selling.slug, buying.slug)
        guard pair != prevPair else { return pairState }
        let pairs = try await Api.swapGetPairs(symbolOrMinter: selling.swapIdentifier)
        try Task.checkCancellation()
        let currentPair = pairs.first(where: { $0.slug == buying.slug })
        let isWellKnownAllowedPair = selling.slug != buying.slug
            && selling.chain == buying.chain
            && selling.chain.isOnchainSwapSupported
        let nextState = PairState(
            isValidPair: currentPair != nil || isWellKnownAllowedPair,
            isReverseProhibited: currentPair?.isReverseProhibited == true
        )
        prevPair = pair
        pairState = nextState
        return nextState
    }

    func cachedIsReverseProhibited(selling: ApiToken, buying: ApiToken) -> Bool? {
        let pair = (selling.slug, buying.slug)
        if pair == prevPair {
            return pairState.isReverseProhibited
        }
        guard let pairs = TokenStore.swapPairs[selling.swapIdentifier] else {
            return nil
        }
        return pairs.first(where: { $0.slug == buying.slug })?.isReverseProhibited == true
    }
}

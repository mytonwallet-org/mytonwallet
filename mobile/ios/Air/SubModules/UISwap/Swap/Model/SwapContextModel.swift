import WalletContext
import WalletCore

struct SwapContext {
    let selling: ApiToken
    let buying: ApiToken
    let swapType: SwapType
    let isValidPair: Bool
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

    func updateContext(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) async throws -> SwapContext {
        let swapType = updateSwapType(selling: selling, buying: buying, accountChains: accountChains)
        let isValidPair = try await pairModel.updatePair(selling: selling, buying: buying)
        self.isValidPair = isValidPair
        let context = SwapContext(selling: selling, buying: buying, swapType: swapType, isValidPair: isValidPair)
        self.context = context
        return context
    }
}

@MainActor private final class SwapPairModel {
    var prevPair: (String, String) = ("", "")
    var isValidPair = true

    func updatePair(selling: ApiToken, buying: ApiToken) async throws -> Bool {
        let pair = (selling.slug, buying.slug)
        guard pair != prevPair else { return isValidPair }
        prevPair = pair
        if selling.chain == .ton && buying.chain == .ton && selling.slug != buying.slug {
            isValidPair = true
            return true
        }
        let pairs = try await Api.swapGetPairs(symbolOrMinter: selling.swapIdentifier)
        try Task.checkCancellation()
        isValidPair = pairs.contains(where: { $0.slug == buying.slug })
        return isValidPair
    }
}

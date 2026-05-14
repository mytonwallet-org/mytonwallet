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
    private let pairResolver = SwapPairResolver()
    private(set) var swapType: SwapType = .onChain
    private(set) var isValidPair = true
    private(set) var context: SwapContext?

    func updateSwapType(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) -> SwapType {
        let swapType = pairResolver.swapType(selling: selling, buying: buying, accountChains: accountChains)
        self.swapType = swapType
        return swapType
    }

    func currentBuyAmountInputDisabled(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) -> Bool {
        pairResolver.currentBuyAmountInputMode(
            selling: selling,
            buying: buying,
            accountChains: accountChains
        ).isDisabled
    }

    func updateContext(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) async throws -> SwapContext {
        let resolution = try await pairResolver.resolve(
            selling: selling,
            buying: buying,
            accountChains: accountChains
        )
        swapType = resolution.swapType
        isValidPair = resolution.isValidPair
        let context = SwapContext(
            selling: resolution.selling,
            buying: resolution.buying,
            swapType: resolution.swapType,
            isValidPair: resolution.isValidPair,
            isBuyAmountInputDisabled: resolution.buyAmountInputMode.isDisabled
        )
        self.context = context
        return context
    }
}

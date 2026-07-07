import WalletContext
import WalletCore

enum SwapBuyAmountInputMode: Equatable {
    case enabled
    case disabled

    var isDisabled: Bool {
        self == .disabled
    }
}

struct SwapPairResolution {
    let selling: ApiToken
    let buying: ApiToken
    let swapType: SwapType
    let isValidPair: Bool
    let buyAmountInputMode: SwapBuyAmountInputMode
}

func isSwapPairInAccountScope(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) -> Bool {
    accountChains.contains(selling.chain) || accountChains.contains(buying.chain)
}

func resolveBuyAmountInputMode(
    swapType: SwapType,
    sellingChain: ApiChain,
    isReverseProhibited: Bool
) -> SwapBuyAmountInputMode {
    swapType == .onChain
        && sellingChain.canSwapByBuyAmount
        && !isReverseProhibited
        ? .enabled
        : .disabled
}

@MainActor final class SwapPairResolver {
    private let pairModel = SwapPairModel()

    func swapType(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) -> SwapType {
        getSwapType(from: selling.slug, to: buying.slug, accountChains: accountChains)
    }

    func currentBuyAmountInputMode(
        selling: ApiToken,
        buying: ApiToken,
        accountChains: Set<ApiChain>
    ) -> SwapBuyAmountInputMode {
        let swapType = swapType(selling: selling, buying: buying, accountChains: accountChains)
        return resolveBuyAmountInputMode(
            swapType: swapType,
            sellingChain: selling.chain,
            isReverseProhibited: pairModel.cachedIsReverseProhibited(selling: selling, buying: buying) ?? true
        )
    }

    func resolve(selling: ApiToken, buying: ApiToken, accountChains: Set<ApiChain>) async throws -> SwapPairResolution {
        let swapType = swapType(selling: selling, buying: buying, accountChains: accountChains)
        let isAccountScoped = isSwapPairInAccountScope(selling: selling, buying: buying, accountChains: accountChains)
        let pairState: SwapPairModel.PairState
        if isAccountScoped {
            pairState = try await pairModel.updatePair(selling: selling, buying: buying)
        } else {
            pairState = SwapPairModel.PairState(isValidPair: false, isReverseProhibited: true)
        }
        return SwapPairResolution(
            selling: selling,
            buying: buying,
            swapType: swapType,
            isValidPair: isAccountScoped && pairState.isValidPair,
            buyAmountInputMode: resolveBuyAmountInputMode(
                swapType: swapType,
                sellingChain: selling.chain,
                isReverseProhibited: pairState.isReverseProhibited
            )
        )
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

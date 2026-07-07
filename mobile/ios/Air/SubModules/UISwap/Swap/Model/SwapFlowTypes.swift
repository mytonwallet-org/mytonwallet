import WalletCore
import WalletContext

struct SwapConfirmationAmounts: Equatable {
    let selling: TokenAmount
    let buying: TokenAmount
}

struct CrosschainFromWalletConfirmation {
    let selling: TokenAmount
    let buying: TokenAmount
    let cexLabel: ApiSwapCexLabel?
}

indirect enum SwapRoute {
    case authorizeDiesel
    case confirmSwap(presentCrosschainResult: Bool)
    case crosschainFromWallet(CrosschainFromWalletConfirmation)
    case priceImpactWarning(impact: Double, next: SwapRoute)

    var allowsPriceImpactWarning: Bool {
        switch self {
        case .confirmSwap:
            return true
        case .authorizeDiesel, .crosschainFromWallet, .priceImpactWarning:
            return false
        }
    }
}

enum SwapStage {
    case editing
    case externalAddress
    case confirming
    case complete

    var allowsEstimation: Bool {
        self == .editing
    }
}

struct SwapValidationInput {
    let sellingToken: ApiToken
    let buyingToken: ApiToken
    let sellingAmount: BigInt?
    let maxAmount: BigInt?
    let swapType: SwapType
}

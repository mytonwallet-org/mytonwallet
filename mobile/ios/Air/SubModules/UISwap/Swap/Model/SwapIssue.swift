import WalletContext
import WalletCore

enum SwapIssue: Equatable {
    case invalidPair
    case insufficientBalance
    case insufficientLiquidity
    case tooSmallAmount
    case notEnoughToken(ApiToken)
    case minimumAmount(MDouble, ApiToken)
    case maximumAmount(MDouble, ApiToken)
    case awaitingPreviousFee
    case unexpectedEstimateError
}

extension SwapIssue {
    var buttonTitle: String {
        switch self {
        case .invalidPair:
            lang("Unsupported Pair")
        case .insufficientBalance:
            lang("Insufficient Balance")
        case .insufficientLiquidity:
            lang("Insufficient liquidity")
        case .tooSmallAmount:
            lang("$swap_too_small_amount")
        case .notEnoughToken(let token):
            L10n.notEnoughSymbol(symbol: token.symbol)
        case .minimumAmount(let amount, let token):
            L10n.minimumAmount(value: formattedTokenAmount(amount, token: token))
        case .maximumAmount(let amount, let token):
            L10n.maximumAmount(value: formattedTokenAmount(amount, token: token))
        case .awaitingPreviousFee:
            lang("Awaiting Previous Fee")
        case .unexpectedEstimateError:
            lang("Unexpected Error")
        }
    }

    private func formattedTokenAmount(_ amount: MDouble, token: ApiToken) -> String {
        TokenAmount.fromDouble(amount.value, token).formatted(.defaultAdaptive)
    }
}

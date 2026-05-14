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
            lang("Invalid Pair")
        case .insufficientBalance:
            lang("Insufficient Balance")
        case .insufficientLiquidity:
            lang("Insufficient liquidity")
        case .tooSmallAmount:
            lang("$swap_too_small_amount")
        case .notEnoughToken(let token):
            lang("Not Enough %symbol%", arg1: token.symbol)
        case .minimumAmount(let amount, let token):
            lang("Minimum amount", arg1: formattedTokenAmount(amount, token: token))
        case .maximumAmount(let amount, let token):
            lang("Maximum amount", arg1: formattedTokenAmount(amount, token: token))
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

import WalletContext
import WalletCore

enum SwapIssue: Equatable {
    case invalidPair
    case insufficientBalance
    case insufficientFee
    case insufficientLiquidity
    case tooSmallAmount
    case minimumAmount(MDouble, ApiToken)
    case maximumAmount(MDouble, ApiToken)
    case awaitingPreviousFee
    case unexpectedEstimateError
    case quoteUnavailable
    case serviceUnavailable
}

extension SwapIssue {
    var buttonTitle: String {
        switch self {
        case .invalidPair:
            lang("Unsupported Pair")
        case .insufficientBalance:
            lang("Insufficient Balance")
        case .insufficientFee:
            lang("Insufficient Fee")
        case .insufficientLiquidity:
            lang("Insufficient liquidity")
        case .tooSmallAmount:
            lang("$swap_too_small_amount")
        case .minimumAmount(let amount, let token):
            L10n.minimumAmount(value: formattedTokenAmount(amount, token: token))
        case .maximumAmount(let amount, let token):
            L10n.maximumAmount(value: formattedTokenAmount(amount, token: token))
        case .awaitingPreviousFee:
            lang("Awaiting Previous Fee")
        case .unexpectedEstimateError:
            lang("Unexpected Error")
        case .quoteUnavailable:
            lang("$swap_quote_unavailable")
        case .serviceUnavailable:
            lang("$swap_service_unavailable")
        }
    }

    private func formattedTokenAmount(_ amount: MDouble, token: ApiToken) -> String {
        TokenAmount.fromDouble(amount.value, token).formatted(.defaultAdaptive)
    }
}

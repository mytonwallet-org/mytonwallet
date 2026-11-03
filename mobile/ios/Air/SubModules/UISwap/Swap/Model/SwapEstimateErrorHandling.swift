import Foundation
import WalletCore

func swapEstimateBackendMessage(from error: Error) -> String? {
    if let bridgeError = error as? SdkError {
        return bridgeError.backendMessage
    }

    let description = (error as NSError).localizedDescription
    return description.isEmpty ? nil : description
}

func isSwapEstimateRateLimited(_ error: Error) -> Bool {
    guard let message = swapEstimateBackendMessage(from: error)?.lowercased() else {
        return false
    }
    return message.contains("too many requests") || (message.contains("request") && message.contains("limit"))
}

/// The backend's `error` answer to the estimate. A thrown bridge or transport failure carries no answer.
func swapEstimateRefusal(from error: Error) -> String? {
    if let response = error as? ApiSwapEstimateErrorResponse {
        return response.error
    }
    if case .some(.apiReturnedError(let message, _, _)) = error as? SdkError {
        return message
    }
    return nil
}

func swapEstimateIssue(from error: Error) -> SwapIssue {
    guard let refusal = swapEstimateRefusal(from: error) else {
        return .unexpectedEstimateError
    }
    switch refusal.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "Insufficient liquidity":
        return .insufficientLiquidity
    case "Tokens must be different", "Asset not found", "Pair not found":
        return .invalidPair
    case "Too small amount":
        return .tooSmallAmount
    case "No swap quote available":
        return .quoteUnavailable
    case "Swap routers are unavailable":
        return .serviceUnavailable
    default:
        return .quoteUnavailable
    }
}

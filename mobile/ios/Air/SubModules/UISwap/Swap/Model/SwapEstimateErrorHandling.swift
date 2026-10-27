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

func swapEstimateIssue(from error: Error) -> SwapIssue {
    guard let message = swapEstimateBackendMessage(from: error) else {
        return .unexpectedEstimateError
    }
    switch message.trimmingCharacters(in: .whitespacesAndNewlines) {
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
        return .unexpectedEstimateError
    }
}

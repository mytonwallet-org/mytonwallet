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

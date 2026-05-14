import Foundation
import WalletCore

func swapEstimateBackendMessage(from error: Error) -> String? {
    if let bridgeError = error as? BridgeCallError {
        switch bridgeError {
        case .apiReturnedError(let error, _):
            return error
        case .customMessage(let message, _):
            return message
        case .message(let message, _):
            return message.rawValue
        case .unknown(let baseError):
            if let baseError = baseError as? Error {
                return swapEstimateBackendMessage(from: baseError)
            }
            if let baseError = baseError as? String {
                return baseError
            }
        }
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

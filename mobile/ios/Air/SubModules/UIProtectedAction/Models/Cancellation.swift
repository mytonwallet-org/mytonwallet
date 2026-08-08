import Foundation
import WalletContext

enum CancellationStage: String, Sendable {
    case authentication
    case mfa
    case ledger
}

enum CancellationReason: String, Sendable {
    case dismissed
    case cancelButton
    case closeButton
    case taskCancelled
}

struct AuthorizationCancellation: Error, Sendable {
    let stage: CancellationStage
    let reason: CancellationReason
}

enum InvariantError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case missingPresenter(String)
    case missingResult(String)
    case activityTimedOut(String)
    case completionPresentationFailed(String)

    var diagnosticDescription: String {
        switch self {
        case .invalidConfiguration(let context):
            "Invalid protected action configuration: \(context)"
        case .missingPresenter(let context):
            "Missing presenter: \(context)"
        case .missingResult(let context):
            "Protected action completed without a result: \(context)"
        case .activityTimedOut(let context):
            "Timed out waiting for protected action activity: \(context)"
        case .completionPresentationFailed(let context):
            "Failed to present protected action completion: \(context)"
        }
    }

    var errorDescription: String? {
        lang("Unexpected error")
    }
}

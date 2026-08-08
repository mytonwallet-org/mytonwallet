import Foundation

enum TokenSendBlockingReason: Equatable, Sendable {
    case incompleteInput
    case invalidRecipient
    case insufficientAmount
    case insufficientFee
    case unresolvedRecipient
    case requiredCommentMissing
    case multisigWarning
    case gasWarning
    case dieselAuthorizationUnavailable
    case draftRejected
}

enum TokenSendMaxFailure: Equatable, Sendable {
    case oscillating
    case attemptLimit
}

enum TokenSendPrimaryAction: Equatable, Sendable {
    case unavailable(TokenSendBlockingReason)
    case validating
    case authorizeDiesel(URL)
    case awaitingPreviousDiesel
    case retryDraft
    case retryMaximum(TokenSendMaxFailure)
    case continueToReview

    var isEnabled: Bool {
        switch self {
        case .authorizeDiesel, .retryDraft, .retryMaximum,
             .continueToReview:
            true
        case .unavailable, .validating, .awaitingPreviousDiesel:
            false
        }
    }

    var isLoading: Bool {
        if case .validating = self {
            return true
        }
        return false
    }
}

enum NftSendPrimaryAction: Equatable, Sendable {
    case incomplete
    case validating
    case retryDraft
    case invalidAddress
    case insufficientBalance
    case continueToReview

    var isEnabled: Bool {
        switch self {
        case .retryDraft, .continueToReview:
            true
        case .incomplete, .validating, .invalidAddress,
             .insufficientBalance:
            false
        }
    }

    var isLoading: Bool {
        self == .validating
    }
}

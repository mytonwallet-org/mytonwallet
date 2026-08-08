import ProtectedAction
import WalletCore

struct SendSubmissionResult: Sendable {
    let activityIds: [String]
    let mfaRequestHash: String?
}

extension SendSubmissionResult: MfaProtectedActionResult {
    var protectedActionActivityIds: [String] {
        activityIds
    }
}

func isSendAddressDraftError(
    _ error: ApiAnyDisplayError?
) -> Bool {
    guard let error else { return false }
    return [
        .domainNotResolved,
        .invalidAddress,
        .invalidAddressFormat,
        .invalidToAddress,
    ].contains(error)
}

func validateSendDraftError(
    _ error: ApiAnyDisplayError?
) throws {
    guard let error else { return }
    if isSendAddressDraftError(error) {
        return
    }
    if error == .insufficientBalance {
        return
    }
    throw error
}

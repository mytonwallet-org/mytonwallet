
import Foundation
import WalletContext

public struct ApiSubmitTransferResult: Decodable, Sendable {
    public var activityId: String?
    public var mfaRequestHash: String?
    public var error: String?
}

extension ApiSubmitTransferResult: MfaProtectedActionResult {
    public var protectedActionError: String? { error }
}

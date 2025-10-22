
import Foundation
import WalletContext

public struct ApiSubmitTransferResult: Decodable, @unchecked Sendable {
    public var activityId: String?
    public var error: String?
}

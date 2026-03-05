
import Foundation
import WalletContext

public struct ApiSubmitTransferResult: Decodable, Sendable {
    public var activityId: String?
    public var error: String?
}


import Foundation
import WalletContext

public struct ApiSignedTransfer: Equatable, Hashable, Codable, Sendable {
    public var base64: String
    public var seqno: Int
}

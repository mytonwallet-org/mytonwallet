import Foundation
import WalletContext

public struct ApiForeignUnstakeDraft: Equatable, Codable, Sendable {
    public struct Transfer: Equatable, Codable, Sendable {
        public var toAddress: String
        public var amount: BigInt
        public var payload: String?
    }

    public var amountNative: BigInt
    public var transfers: [Transfer]
    public var fee: BigInt
    public var realFee: BigInt
    public var isInstant: Bool
}

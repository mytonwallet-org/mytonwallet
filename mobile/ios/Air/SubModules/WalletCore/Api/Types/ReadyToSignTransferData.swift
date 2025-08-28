
import Foundation
import WalletContext

extension Api {

    public struct ReadyToSignTransferData {
        
        public var accountId: String
        public var fromAddress: String?
        public var normalizedAddress: String?
        public var path: [Int]
        public var transaction: [String: Any]
        public var pendingTransferId: String

        init(any: Any) throws {
            let dict = try (any as? [String: Any]).orThrow("not a dictionary")
            accountId = try (dict["accountId"] as? String).orThrow("accountId is nil")
            fromAddress = dict["fromAddress"] as? String
            normalizedAddress = dict["normalizedAddress"] as? String
            path = try (dict["path"] as? [Int]).orThrow("path is nil")
            transaction = try (dict["transaction"] as? [String: Any]).orThrow("transaction is nil")
            pendingTransferId = try (dict["pendingTransferId"] as? String).orThrow("pendingTransferId is nil")
        }
    }
}

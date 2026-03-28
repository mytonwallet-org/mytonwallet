import Foundation
import GRDB

public struct MAccountSavedAddresses: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var addresses: [SavedAddress]

    public init(accountId: String, addresses: [SavedAddress]) {
        self.accountId = accountId
        self.addresses = addresses
    }

    public static let databaseTableName: String = "account_saved_addresses"
}

public extension MAccountSavedAddresses {
    var hasData: Bool {
        !addresses.isEmpty
    }
}

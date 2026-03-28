import Foundation
import GRDB
import WalletContext

public struct MOrderedAccountIds: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let id: Int64
    public var orderedAccountIds: [String]

    public init(id: Int64 = SINGLETON_TABLE_ROW_ID, orderedAccountIds: [String]) {
        self.id = id
        self.orderedAccountIds = orderedAccountIds
    }

    public static let databaseTableName: String = "account_ordering"
}

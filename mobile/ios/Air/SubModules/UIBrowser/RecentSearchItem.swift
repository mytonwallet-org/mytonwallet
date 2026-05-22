import Foundation
import GRDB

public struct RecentSearchItem: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var accountId: String
    public var tag: String?
    public var text: String
    public var timestamp: Date

    public static let databaseTableName = "recent_searches"

    public init(accountId: String, tag: String?, text: String, timestamp: Date) {
        self.accountId = accountId
        self.tag = tag
        self.text = text
        self.timestamp = timestamp
    }
}

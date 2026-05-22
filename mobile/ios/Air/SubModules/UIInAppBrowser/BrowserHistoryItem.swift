import Foundation
import GRDB

public struct BrowserHistoryItem: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var accountId: String
    public var tag: String?
    public var url: String
    public var title: String
    public var favicon: String
    public var visitDate: Date

    public static let databaseTableName = "browser_history"

    public init(accountId: String, tag: String?, url: String, title: String, favicon: String, visitDate: Date) {
        self.accountId = accountId
        self.tag = tag
        self.url = url
        self.title = title
        self.favicon = favicon
        self.visitDate = visitDate
    }
}

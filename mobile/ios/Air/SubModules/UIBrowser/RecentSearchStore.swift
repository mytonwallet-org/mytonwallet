import Foundation
import GRDB
import WalletContext
import WalletCore

private let log = Log("RecentSearchStore")

@MainActor
public final class RecentSearchStore: WalletCoreData.EventsObserver {

    public static let shared = RecentSearchStore()

    private static let maxItemsPerTag = 10

    public var onLoaded: (() -> Void)?

    private var cachedAccountId: String?
    private var isLoaded: Bool = false
    public private(set) var items: [RecentSearchItem] = []

    private init() {
        WalletCoreData.add(eventObserver: self)
        loadCurrentAccount()
    }

    public func saveSearch(accountId: String, text: String, tag: String?) {
        let now = Date()

        if cachedAccountId == accountId, isLoaded {
            let normalized = text.lowercased()
            items.removeAll { $0.text.lowercased() == normalized && $0.tag == tag }
            let newItem = RecentSearchItem(accountId: accountId, tag: tag, text: text, timestamp: now)
            items.insert(newItem, at: 0)
        }

        let maxItems = Self.maxItemsPerTag
        Task.detached {
            guard let db else { return }
            do {
                try db.write { db in
                    try RecentSearchItem
                        .filter(Column("accountId") == accountId
                            && Column("text") == text
                            && Column("tag") === tag)
                        .deleteAll(db)
                    let item = RecentSearchItem(accountId: accountId, tag: tag, text: text, timestamp: now)
                    try item.insert(db)
                    try db.execute(sql: """
                        DELETE FROM recent_searches
                        WHERE accountId = ? AND tag IS ? AND rowid NOT IN (
                            SELECT rowid FROM recent_searches
                            WHERE accountId = ? AND tag IS ?
                            ORDER BY timestamp DESC
                            LIMIT ?
                        )
                        """, arguments: [accountId, tag, accountId, tag, maxItems])
                }
            } catch {
                log.error("saveSearch failed: \(error, .public)")
            }
        }
    }

    public func clear(accountId: String, tag: String?) {
        if cachedAccountId == accountId, isLoaded {
            items.removeAll { $0.tag == tag }
        }
        Task.detached {
            guard let db else { return }
            do {
                _ = try db.write { db in
                    try RecentSearchItem
                        .filter(Column("accountId") == accountId && Column("tag") === tag)
                        .deleteAll(db)
                }
            } catch {
                log.error("clear failed: \(error, .public)")
            }
        }
    }

    // MARK: - WalletCoreData.EventsObserver

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(let accountId, _):
            loadForAccount(accountId)
        case .accountDeleted(let accountId):
            if cachedAccountId == accountId {
                items = []
                isLoaded = false
                cachedAccountId = nil
            }
        case .accountsReset:
            items = []
            isLoaded = false
            cachedAccountId = nil
        default:
            break
        }
    }

    private func loadCurrentAccount() {
        guard let accountId = AccountStore.accountId else { return }
        loadForAccount(accountId)
    }

    private func loadForAccount(_ accountId: String) {
        guard accountId != cachedAccountId else { return }
        cachedAccountId = accountId
        isLoaded = false
        items = []

        Task {
            guard let db else { return }
            do {
                let loaded = try await db.read { db in
                    try RecentSearchItem
                        .filter(Column("accountId") == accountId)
                        .order(Column("timestamp").desc)
                        .fetchAll(db)
                }
                if self.cachedAccountId == accountId {
                    self.items = loaded
                    self.isLoaded = true
                    self.onLoaded?()
                }
            } catch {
                log.error("loadForAccount failed: \(error, .public)")
            }
        }
    }
}

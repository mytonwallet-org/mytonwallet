import Combine
import Foundation
import GRDB
import WalletContext
import WalletCore

private let log = Log("BrowserHistoryStore")

@MainActor
public final class BrowserHistoryStore: WalletCoreData.EventsObserver {

    public static let shared = BrowserHistoryStore()

    private static let maxItemsPerTag = 100

    private let onLoadedSubject = PassthroughSubject<Void, Never>()
    
    public var onLoaded: AnyPublisher<Void, Never> {
        onLoadedSubject.eraseToAnyPublisher()
    }

    private var cachedAccountId: String?
    private var isLoaded: Bool = false
    public private(set) var items: [BrowserHistoryItem] = []

    private init() {
        WalletCoreData.add(eventObserver: self)
        loadCurrentAccount()
    }

    public func saveVisit(accountId: String, url: String, title: String, favicon: String, tag: String?) {
        let now = Date()

        // Update in-memory cache immediately — only when the DB load has completed,
        // so we don't add an item that will be wiped by the in-flight read.
        if cachedAccountId == accountId, isLoaded {
            let normalized = url.lowercased()
            items.removeAll { $0.url.lowercased() == normalized && $0.tag == tag }
            let newItem = BrowserHistoryItem(accountId: accountId, tag: tag,
                                             url: url, title: title, favicon: favicon, visitDate: now)
            items.insert(newItem, at: 0)
        }

        // Persist asynchronously off the main thread.
        let maxItems = Self.maxItemsPerTag
        Task.detached {
            guard let db else { return }
            do {
                try db.write { db in
                    // Deduplicate on (accountId, url, tag) — matches the UNIQUE constraint.
                    // Use === (IS) for null-safe tag comparison.
                    try BrowserHistoryItem
                        .filter(Column("accountId") == accountId
                            && Column("url") == url
                            && Column("tag") === tag)
                        .deleteAll(db)
                    let item = BrowserHistoryItem(accountId: accountId, tag: tag, url: url, title: title, favicon: favicon, visitDate: now)
                    try item.insert(db)
                    try db.execute(sql: """
                        DELETE FROM browser_history
                        WHERE accountId = ? AND tag IS ? AND rowid NOT IN (
                            SELECT rowid FROM browser_history
                            WHERE accountId = ? AND tag IS ?
                            ORDER BY visitDate DESC
                            LIMIT ?
                        )
                        """, arguments: [accountId, tag, accountId, tag, maxItems])
                }
            } catch {
                log.error("saveVisit failed: \(error, .public)")
            }
        }
    }

    public func clear(accountId: String, tag: String) {
        if cachedAccountId == accountId, isLoaded {
            items.removeAll { $0.tag == tag }
        }
        Task.detached {
            guard let db else { return }
            do {
                _ = try db.write { db in
                    try BrowserHistoryItem
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
                    try BrowserHistoryItem
                        .filter(Column("accountId") == accountId)
                        .order(Column("visitDate").desc)
                        .fetchAll(db)
                }
                if self.cachedAccountId == accountId {
                    self.items = loaded
                    self.isLoaded = true
                    self.onLoadedSubject.send()
                }
            } catch {
                log.error("loadForAccount failed: \(error, .public)")
            }
        }
    }
}

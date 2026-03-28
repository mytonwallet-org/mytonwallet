import Dependencies
import Foundation
import GRDB
import Perception
import WalletContext

private let log = Log("SavedAddressesStore")

public actor SavedAddressesStore: WalletCoreData.EventsObserver {
    @MainActor private var byAccountId: MainActorByAccountIdStore<SavedAddresses> = .init(initialValue: SavedAddresses.init(accountId:))

    private var db: (any DatabaseWriter)?

    init() {
    }

    func use(db: any DatabaseWriter) async {
        self.db = db
        await loadFromDb()
        WalletCoreData.add(eventObserver: self)
    }

    @MainActor func clean() {
        byAccountId.removeAll()
    }

    @MainActor public func `for`(accountId: String) -> SavedAddresses {
        byAccountId.for(accountId: accountId)
    }

    func persist(accountId: String, values: [SavedAddress]) {
        guard let db else {
            assertionFailure("database not ready")
            return
        }

        let row = MAccountSavedAddresses(accountId: accountId, addresses: values)
        do {
            try db.write { db in
                if row.hasData {
                    try row.upsert(db)
                } else {
                    try MAccountSavedAddresses.deleteOne(db, key: accountId)
                }
            }
        } catch {
            log.error("persist failed accountId=\(accountId, .public) error=\(error, .public)")
        }
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountDeleted(let accountId):
            byAccountId.remove(accountId: accountId)
        case .accountsReset:
            byAccountId.removeAll()
        default:
            break
        }
    }

    private func loadFromDb() async {
        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let rows = try await db.read { db in
                try MAccountSavedAddresses.fetchAll(db)
            }
            await MainActor.run {
                for row in rows {
                    `for`(accountId: row.accountId).replace(values: row.addresses)
                }
            }
        } catch {
            log.error("initial load failed: \(error, .public)")
        }
    }
}

extension SavedAddressesStore: DependencyKey {
    public static let liveValue: SavedAddressesStore = SavedAddressesStore()
}

extension DependencyValues {
    public var savedAddresses: SavedAddressesStore {
        self[SavedAddressesStore.self]
    }
}

@MainActor
@Perceptible
public final class SavedAddresses: Sendable {
    public let accountId: String
    public private(set) var values: [SavedAddress] = []

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    public func save(_ newValue: SavedAddress, addOnly: Bool = false) {
        var nextValues = values.filter { !$0.matches(newValue) }
        guard !addOnly || nextValues.count == values.count else { return }
        nextValues.append(newValue)
        guard nextValues != values else { return }
        values = nextValues
        persist(values: nextValues)
    }

    public func delete(_ valueToDelete: SavedAddress) {
        let nextValues = values.filter { !$0.matches(valueToDelete) }
        guard nextValues != values else { return }
        values = nextValues
        persist(values: nextValues)
    }

    public func getMatching(_ searchString: String) -> [SavedAddress] {
        searchString.isEmpty
            ? values
            : values.filter { $0.name.lowercased().contains(searchString) || $0.address.lowercased().contains(searchString) }
    }

    public func get(chain: ApiChain, address: String) -> SavedAddress? {
        values.first(where: { $0.matches(chain: chain, address: address) })
    }

    fileprivate func replace(values: [SavedAddress]) {
        self.values = values
    }

    private func persist(values: [SavedAddress]) {
        @Dependency(\.savedAddresses) var savedAddressesStore
        Task {
            await savedAddressesStore.persist(accountId: accountId, values: values)
        }
    }
}

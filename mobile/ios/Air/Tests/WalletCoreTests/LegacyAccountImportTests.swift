import Foundation
import GRDB
import Testing
@testable import WalletCore
import WalletContext

@MainActor
@Suite("Legacy Account Import", .serialized)
struct LegacyAccountImportTests {
    @Test
    func `recovers valid accounts and ignores corrupt legacy records`() async throws {
        let dbQueue = try makeDatabaseQueue()
        let storage = makeStorage(accountsById: [
            "good-mainnet": [
                "title": "Good",
                "type": "mnemonic",
                "byChain": [
                    "ton": [
                        "address": "EQgood",
                        "domain": "good.ton",
                        "isMultisig": true,
                    ],
                    "solana": [
                        "address": 123,
                    ],
                ],
                "addressByChain": [
                    "solana": "SoFallback",
                ],
            ],
            "address-mainnet": [
                "title": "Address",
                "address": "EQaddress",
            ],
            "bad-mainnet": [
                "title": "Bad",
            ],
            "temp-mainnet": [
                "type": "view",
                "isTemporary": true,
                "byChain": [
                    "ton": [
                        "address": "EQtemporary",
                    ],
                ],
            ],
        ], currentAccountId: "bad-mainnet")

        try await withRestoredStartupDefaults {
            try await switchStorageFromCapacitorIfNeeded(global: storage, db: dbQueue)
        }

        let accounts = try await dbQueue.read { db in
            try MAccount.fetchAll(db)
        }
        let currentAccountId = try await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT current_account_id FROM common")
        }
        let switchedDate = try await dbQueue.read { db in
            try Date.fetchOne(db, sql: "SELECT switched_from_capacitor_dt FROM common")
        }
        let recoveredIds = Set(accounts.map(\.id))
        let expectedIds = Set(["good-mainnet", "address-mainnet"])
        let goodAccount = accounts.first { $0.id == "good-mainnet" }
        let addressAccount = accounts.first { $0.id == "address-mainnet" }
        let currentIdIsRecovered = recoveredIds.contains(currentAccountId ?? "")

        #expect(recoveredIds == expectedIds)
        #expect(goodAccount?.byChain["ton"]?.address == "EQgood")
        #expect(goodAccount?.byChain["ton"]?.domain == "good.ton")
        #expect(goodAccount?.byChain["ton"]?.isMultisig == true)
        #expect(goodAccount?.byChain["solana"]?.address == "SoFallback")
        #expect(addressAccount?.byChain["ton"]?.address == "EQaddress")
        #expect(currentIdIsRecovered)
        #expect(switchedDate != nil)
    }

    @Test
    func `fails migration when no account can be recovered`() async throws {
        let dbQueue = try makeDatabaseQueue()
        let storage = makeStorage(accountsById: [
            "bad-mainnet": [
                "title": "Bad",
            ],
            "temp-mainnet": [
                "type": "view",
                "isTemporary": true,
                "byChain": [
                    "ton": [
                        "address": "EQtemporary",
                    ],
                ],
            ],
        ], currentAccountId: "bad-mainnet")
        var didThrowInvalidLegacyStorage = false

        await withRestoredStartupDefaults {
            do {
                try await switchStorageFromCapacitorIfNeeded(global: storage, db: dbQueue)
            } catch GlobalStorageError.localStorageIsInvalidJson(_) {
                didThrowInvalidLegacyStorage = true
            } catch {
            }
        }

        let accountCount = try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts")
        }
        let switchedDate = try await dbQueue.read { db in
            try Date.fetchOne(db, sql: "SELECT switched_from_capacitor_dt FROM common")
        }

        #expect(didThrowInvalidLegacyStorage)
        #expect(accountCount == 0)
        #expect(switchedDate == nil)
    }

    private func makeStorage(accountsById: [String: Any], currentAccountId: String) -> GlobalStorage {
        let storage = GlobalStorage()
        storage.update {
            $0[""] = [
                "stateVersion": STATE_VERSION,
                "accounts": [
                    "byId": accountsById,
                ],
                "currentAccountId": currentAccountId,
                "settings": [
                    "orderedAccountIds": Array(accountsById.keys),
                ],
                "byAccountId": [:],
            ]
        }
        return storage
    }

    private func makeDatabaseQueue() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: configuration)
        try makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    private func withRestoredStartupDefaults<T>(_ operation: () async throws -> T) async rethrows -> T {
        let keys = [
            AppStorageHelper.selectedCurrencyKey,
            "settings.langCode",
            "settings.langMigrationToUserDefaultsCompleted",
            "AppleLanguages",
            "AppleTextDirection",
            "NSForceRightToLeftWritingDirection",
        ]
        let snapshots = [UserDefaults.standard, UserDefaults.appGroup].compactMap { store -> UserDefaultsSnapshot? in
            guard let store else { return nil }
            let values = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                store.object(forKey: key).map { (key, $0) }
            })
            return UserDefaultsSnapshot(store: store, values: values)
        }
        defer {
            for snapshot in snapshots {
                for key in keys {
                    if let value = snapshot.values[key] {
                        snapshot.store.set(value, forKey: key)
                    } else {
                        snapshot.store.removeObject(forKey: key)
                    }
                }
                snapshot.store.synchronize()
            }
        }
        return try await operation()
    }
}

private struct UserDefaultsSnapshot {
    let store: UserDefaults
    let values: [String: Any]
}

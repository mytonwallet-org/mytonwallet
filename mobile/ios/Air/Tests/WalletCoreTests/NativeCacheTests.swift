import Foundation
import GRDB
import OrderedCollections
import Testing
import WalletContext
@testable import WalletCore

@Suite("Native cache cleanup", .serialized)
struct NativeCacheTests {
    @Test
    func `activity cleanup preserves accounts and resets history pagination`() async throws {
        let db = try makeDatabase()
        try await db.write { db in
            try _ActivityStore.AccountState(
                accountId: "cache-test",
                byId: [:],
                idsMain: ["old-activity"],
                isMainHistoryEndReached: true,
                isHistoryEndReachedBySlug: [TONCOIN_SLUG: true]
            ).insert(db)
        }
        let store = _ActivityStore()
        await store.use(db: db)

        try await store.clearCache()

        let state = await store.getAccountState("cache-test")
        #expect(state.idsMain == nil)
        #expect(state.isMainHistoryEndReached == nil)
        #expect(state.isHistoryEndReachedBySlug == nil)
        let counts = try await db.read { db in
            (try _ActivityStore.AccountState.fetchCount(db), try MAccount.fetchCount(db))
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 1)
        await WalletCoreData.remove(observer: store)
    }

    @Test
    func `NFT cleanup removes cached data and queued writes but preserves hidden preferences`() async throws {
        let db = try makeDatabase()
        let directory = URL.temporaryDirectory.appending(component: UUID().uuidString)
        let cacheUrl = directory.appending(component: "nfts.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nft = ApiNft.sample
        let cached: [String: OrderedDictionary<String, DisplayNft>] = [
            "cache-test": [nft.id: DisplayNft(nft: nft, isHiddenByUser: false)],
        ]
        try JSONEncoder().encode(cached).write(to: cacheUrl)
        let store = _NftStore(cacheUrl: cacheUrl)
        await store.use(db: db, accountIds: ["cache-test"])
        store.setHiddenByUser(accountId: "cache-test", nft: nft, isHidden: true)

        try await store.clearCache()

        #expect(store.getAccountNfts(accountId: "cache-test") == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheUrl.path()))
        #expect(store.isHiddenByUser(accountId: "cache-test", nft: nft))
        #expect(try await db.read { try MAccountHiddenNft.fetchCount($0) } == 1)
        // The live database connection must still support changing a saved preference after cleanup.
        store.setHiddenByUser(accountId: "cache-test", nft: nft, isHidden: false)
        #expect(try await db.read { try MAccountHiddenNft.fetchCount($0) } == 0)
        try await store.clearCache()
        await WalletCoreData.remove(observer: store)
    }

    @Test
    func `NFT cleanup retains explicitly shown NFTs across a restart`() async throws {
        let db = try makeDatabase()
        let directory = URL.temporaryDirectory.appending(component: UUID().uuidString)
        let cacheUrl = directory.appending(component: "nfts.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        var nft = ApiNft.sample
        nft.isUnverified = true
        let store = _NftStore(cacheUrl: cacheUrl)
        await store.use(db: db, accountIds: ["cache-test"])
        store.setHiddenByUser(accountId: "cache-test", nft: nft, isHidden: false)

        try await store.clearCache()

        let restoredStore = _NftStore(cacheUrl: cacheUrl)
        await restoredStore.use(db: db, accountIds: ["cache-test"])
        #expect(restoredStore.getAccountNfts(accountId: "cache-test") == nil)
        let transaction = ApiTransactionActivity(
            id: "test", kind: "transaction", externalMsgHashNorm: nil, timestamp: 0,
            amount: 0, fromAddress: "from", toAddress: "to", comment: nil,
            encryptedComment: nil, fee: 0, slug: TONCOIN_SLUG, isIncoming: true,
            normalizedAddress: nil, type: nil, metadata: nil, nft: nft, status: .completed
        )
        #expect(!restoredStore.shouldHideTransaction(
            accountId: "cache-test", transaction: transaction, areUnverifiedNftsHidden: true
        ))
        await WalletCoreData.remove(observer: store)
        await WalletCoreData.remove(observer: restoredStore)
    }

    @Test
    func `token cleanup restores bundled defaults and preserves unrelated settings`() async throws {
        let defaults = UserDefaults.standard
        let keys = ["cache.tokens", "cache.currencyRates", "cache.swapAssets", "cache.tokens.currency", "cache-test.setting"]
        let originalValues = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            TokenStore.clean()
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set("keep", forKey: "cache-test.setting")
        defaults.set(Data("stale".utf8), forKey: "cache.tokens")
        defaults.set(Data("stale".utf8), forKey: "cache.swapAssets")
        TokenStore.swapPairs = ["old": []]

        await TokenStore.clearCache()

        #expect(TokenStore.tokens == _TokenStore.defaultTokens)
        #expect(TokenStore.swapAssets == nil)
        #expect(TokenStore.swapPairs.isEmpty)
        #expect(TokenStore.currencyRates.isEmpty)
        let persisted = try JSONDecoder().decode(
            [String: ApiToken].self,
            from: #require(defaults.data(forKey: "cache.tokens"))
        )
        #expect(persisted == _TokenStore.defaultTokens)
        #expect(defaults.object(forKey: "cache.swapAssets") == nil)
        #expect(defaults.string(forKey: "cache-test.setting") == "keep")
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try db.write { db in
            try MAccount(id: "cache-test", title: nil, type: .view, byChain: [ApiChain: AccountChain]()).insert(db)
        }
        return db
    }
}

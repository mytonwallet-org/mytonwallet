import Foundation
import GRDB
import Testing
@testable import WalletCore

@Suite("Hidden NFT Storage")
struct HiddenNftStorageTests {
    @Test
    func `store hides an NFT without an owned NFT cache entry`() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try db.execute(
                sql: """
                INSERT INTO accounts (id, type, byChain)
                VALUES (?, ?, ?)
                """,
                arguments: ["account-1", AccountType.mnemonic.rawValue, #"{"ton":{"address":"EQ-owner"}}"#]
            )
        }
        let store = _NftStore(cacheUrl: temporaryCacheUrl())
        await store.use(db: db, accountIds: ["account-1"])
        let nft = ApiNft.sample

        #expect(store.getAccountNfts(accountId: "account-1") == nil)
        store.setHiddenByUser(accountId: "account-1", nft: nft, isHidden: true)

        let rows = try await db.read { db in
            try MAccountHiddenNft.fetchAll(db)
        }
        #expect(store.shouldHideTransaction(accountId: "account-1", transaction: transaction(nft: nft)))
        #expect(rows.count == 1)
        #expect(rows.first?.nftAddress == nft.address)
    }

    @Test
    func `legacy file blacklist is migrated and no longer encoded`() async throws {
        struct LegacyDisplayNft: Encodable {
            let nft: ApiNft
            let isHiddenByUser: Bool
            let isUnhiddenByUser: Bool
        }

        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try db.execute(
                sql: """
                INSERT INTO accounts (id, type, byChain)
                VALUES (?, ?, ?)
                """,
                arguments: ["account-1", AccountType.mnemonic.rawValue, #"{"ton":{"address":"EQ-owner"}}"#]
            )
        }
        let nft = ApiNft.sample
        let cacheUrl = temporaryCacheUrl()
        try FileManager.default.createDirectory(
            at: cacheUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyDisplayNft = LegacyDisplayNft(nft: nft, isHiddenByUser: true, isUnhiddenByUser: false)
        let legacyDisplayNftObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyDisplayNft))
        let legacyCache: [String: Any] = [
            // OrderedDictionary encodes as alternating key/value entries so its order survives decoding.
            "account-1": [nft.id, legacyDisplayNftObject],
        ]
        try JSONSerialization.data(withJSONObject: legacyCache).write(to: cacheUrl)
        let store = _NftStore(cacheUrl: cacheUrl)

        await store.use(db: db, accountIds: ["account-1"])

        let rows = try await db.read { db in
            try MAccountHiddenNft.fetchAll(db)
        }
        let newlyEncodedDisplayNft = String(
            decoding: try JSONEncoder().encode(DisplayNft(nft: nft, isHiddenByUser: true)),
            as: UTF8.self
        )
        #expect(store.shouldHideTransaction(accountId: "account-1", transaction: transaction(nft: nft)))
        #expect(rows.first?.nftAddress == nft.address)
        #expect(!newlyEncodedDisplayNft.contains("isHiddenByUser"))
    }

    @Test
    func `hidden NFTs are removed with their account`() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO accounts (id, type, byChain)
                VALUES (?, ?, ?)
                """,
                arguments: ["account-1", AccountType.mnemonic.rawValue, #"{"ton":{"address":"EQ-owner"}}"#]
            )
            try MAccountHiddenNft(accountId: "account-1", chain: "ton", nftAddress: "EQ-nft").insert(db)
            try db.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: ["account-1"])
        }

        let count = try db.read { db in
            try MAccountHiddenNft.fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test
    func `unverified NFT visibility respects automatic filter and explicit choices`() {
        var nft = ApiNft.sample
        nft.isUnverified = true

        let automatic = DisplayNft(nft: nft, isHiddenByUser: false)
        #expect(automatic.shouldHide(areUnverifiedNftsHidden: true))
        #expect(!automatic.shouldHide(areUnverifiedNftsHidden: false))

        let shown = DisplayNft(nft: nft, isHiddenByUser: false, isUnhiddenByUser: true)
        #expect(!shown.shouldHide(areUnverifiedNftsHidden: true))

        let explicitlyHidden = DisplayNft(nft: nft, isHiddenByUser: true, isUnhiddenByUser: true)
        #expect(explicitlyHidden.shouldHide(areUnverifiedNftsHidden: true))
    }

    @Test
    func `full NFT refresh replaces cached metadata and preserves user preferences`() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try db.execute(
                sql: """
                INSERT INTO accounts (id, type, byChain)
                VALUES (?, ?, ?)
                """,
                arguments: ["account-1", AccountType.mnemonic.rawValue, #"{"ton":{"address":"EQ-owner"}}"#]
            )
        }

        var cachedShownNft = ApiNft.sample
        cachedShownNft.name = "Cached shown NFT"
        cachedShownNft.isUnverified = nil
        var cachedHiddenNft = ApiNft.sampleMtwCard
        cachedHiddenNft.name = "Cached hidden NFT"
        cachedHiddenNft.isUnverified = nil
        let cachedHiddenNftAddress = cachedHiddenNft.address

        try await db.write { db in
            try MAccountHiddenNft(
                accountId: "account-1",
                chain: ApiChain.ton.rawValue,
                nftAddress: cachedHiddenNftAddress
            ).insert(db)
        }

        let cacheUrl = temporaryCacheUrl()
        try FileManager.default.createDirectory(
            at: cacheUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let shownObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(
                DisplayNft(nft: cachedShownNft, isHiddenByUser: false, isUnhiddenByUser: true)
            )
        )
        let hiddenObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(DisplayNft(nft: cachedHiddenNft, isHiddenByUser: true))
        )
        let cache: [String: Any] = [
            "account-1": [cachedShownNft.id, shownObject, cachedHiddenNft.id, hiddenObject],
        ]
        try JSONSerialization.data(withJSONObject: cache).write(to: cacheUrl)

        let store = _NftStore(cacheUrl: cacheUrl)
        await store.use(db: db, accountIds: ["account-1"])

        var refreshedShownNft = cachedShownNft
        refreshedShownNft.name = "Refreshed shown NFT"
        refreshedShownNft.isUnverified = true
        var refreshedHiddenNft = cachedHiddenNft
        refreshedHiddenNft.name = "Refreshed hidden NFT"
        refreshedHiddenNft.isUnverified = true
        store.walletCore(event: .updateNfts(.init(
            accountId: "account-1",
            nfts: [refreshedHiddenNft, refreshedShownNft],
            chain: .ton,
            collectionAddress: nil,
            isFullLoading: true,
            streamedAddresses: nil
        )))

        for _ in 0..<100 {
            if store.getNft(accountId: "account-1", nftId: refreshedShownNft.id)?.nft.isUnverified == true {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let nfts = try #require(store.getAccountNfts(accountId: "account-1"))
        let shown = try #require(nfts[refreshedShownNft.id])
        let hidden = try #require(nfts[refreshedHiddenNft.id])
        #expect(Array(nfts.keys) == [refreshedShownNft.id, refreshedHiddenNft.id])
        #expect(shown.nft.name == "Refreshed shown NFT")
        #expect(shown.nft.isUnverified == true)
        #expect(shown.isUnhiddenByUser)
        #expect(hidden.nft.name == "Refreshed hidden NFT")
        #expect(hidden.nft.isUnverified == true)
        #expect(hidden.isHiddenByUser)
    }

    @Test
    func `only received non-trade unverified NFT activities are hidden`() {
        var nft = ApiNft.sample
        nft.isUnverified = true
        let store = _NftStore(cacheUrl: temporaryCacheUrl())

        #expect(store.shouldHideTransaction(
            accountId: "account-1",
            transaction: transaction(nft: nft, isIncoming: true),
            areUnverifiedNftsHidden: true
        ))
        #expect(!store.shouldHideTransaction(
            accountId: "account-1",
            transaction: transaction(nft: nft, isIncoming: false),
            areUnverifiedNftsHidden: true
        ))
        #expect(!store.shouldHideTransaction(
            accountId: "account-1",
            transaction: transaction(nft: nft, isIncoming: true, type: .nftTrade),
            areUnverifiedNftsHidden: true
        ))
        #expect(!store.shouldHideTransaction(
            accountId: "account-1",
            transaction: transaction(nft: nft, isIncoming: true),
            areUnverifiedNftsHidden: false
        ))
    }

    private func transaction(
        nft: ApiNft,
        isIncoming: Bool = true,
        type: ApiTransactionType? = nil
    ) -> ApiTransactionActivity {
        ApiTransactionActivity(
            id: "transaction-\(UUID().uuidString)",
            kind: "transaction",
            externalMsgHashNorm: nil,
            timestamp: 0,
            amount: 0,
            fromAddress: "EQ-sender",
            toAddress: "EQ-recipient",
            comment: nil,
            encryptedComment: nil,
            fee: 0,
            slug: "toncoin",
            isIncoming: isIncoming,
            normalizedAddress: nil,
            type: type,
            metadata: nil,
            nft: nft,
            status: .completed
        )
    }

    private func temporaryCacheUrl() -> URL {
        FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
            .appending(component: "nfts.json")
    }
}

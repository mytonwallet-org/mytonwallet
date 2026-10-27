import Foundation
import GRDB
import OrderedCollections
import Testing
import WalletContext
@testable import WalletCore

@Suite("Hidden NFT Storage")
struct HiddenNftStorageTests {
    @Test
    func `legacy EVM visibility choices survive canonical keys and explicit Show survives restart`() async throws {
        let accountId = "nft-test"
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let legacyAddress = "0x000000000000888741B254d37e1b27128AfEAaBC/42"
        try await db.write { db in
            try MAccount(id: accountId, title: nil, type: .view, byChain: [ApiChain: AccountChain]()).insert(db)
            try MAccountHiddenNft(accountId: accountId, chain: "base", nftAddress: legacyAddress).insert(db)
        }
        let cacheUrl = temporaryCacheUrl()
        try FileManager.default.createDirectory(at: cacheUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheUrl.deletingLastPathComponent()) }
        var galleryNft = ApiNft.sample
        galleryNft.chain = .base
        galleryNft.address = legacyAddress
        galleryNft.isHidden = false
        galleryNft.isScam = false
        galleryNft.isUnverified = false
        struct LegacyCache: Encodable {
            var nfts: [String: OrderedDictionary<String, DisplayNft>]
            var unhiddenNftIdsByAccount: [String: Set<String>]
        }
        let cache = LegacyCache(
            nfts: [accountId: ["base:\(legacyAddress)": DisplayNft(nft: galleryNft, isHiddenByUser: false)]],
            unhiddenNftIdsByAccount: [accountId: ["base:\(legacyAddress)1"]]
        )
        try JSONEncoder().encode(cache).write(to: cacheUrl)

        let store = _NftStore(cacheUrl: cacheUrl)
        await store.use(db: db, accountIds: [accountId])
        let canonicalNft = try #require(store.getNft(accountId: accountId, nftId: galleryNft.id)?.nft)
        #expect(canonicalNft.address == legacyAddress.lowercased())
        #expect(store.isHiddenByUser(accountId: accountId, nft: canonicalNft))
        #expect(try await db.read { try MAccountHiddenNft.fetchOne($0)?.nftAddress } == canonicalNft.address)

        var activityNft = canonicalNft
        activityNft.isHidden = true
        var previouslyShownNft = activityNft
        previouslyShownNft.address += "1"
        #expect(!store.shouldHideTransaction(
            accountId: accountId, transaction: transaction(nft: previouslyShownNft), areUnverifiedNftsHidden: false
        ))
        store.setHiddenByUser(accountId: accountId, nft: canonicalNft, isHidden: false)
        #expect(!store.shouldHideTransaction(
            accountId: accountId, transaction: transaction(nft: activityNft), areUnverifiedNftsHidden: false
        ))
        #expect(try await db.read { try MAccountHiddenNft.fetchCount($0) } == 0)

        try await store.clearCache()
        let restoredStore = _NftStore(cacheUrl: cacheUrl)
        await restoredStore.use(db: db, accountIds: [accountId])
        #expect(!restoredStore.shouldHideTransaction(
            accountId: accountId, transaction: transaction(nft: activityNft), areUnverifiedNftsHidden: false
        ))
        await WalletCoreData.remove(observer: store)
        await WalletCoreData.remove(observer: restoredStore)
    }

    @Test
    func `provider spam metadata survives the SDK and cache boundaries`() throws {
        let json = #"{"chain":"base","address":"0xcontract/42","isOnSale":false,"isHidden":true,"spamInfo":{"provider":"alchemy","isSpam":true,"classifications":["SpammyMetadata","FutureClassification"]}}"#
        let nft = try JSONDecoder().decode(ApiNft.self, from: Data(json.utf8))
        let cached = try JSONDecoder().decode(ApiNft.self, from: JSONEncoder().encode(nft))

        #expect(cached.spamInfo?.provider == "alchemy")
        #expect(cached.spamInfo?.isSpam == true)
        #expect(cached.spamInfo?.classifications == ["SpammyMetadata", "FutureClassification"])
        #expect(DisplayNft(nft: cached, isHiddenByUser: false).shouldHide(areUnverifiedNftsHidden: false))
        #expect(!DisplayNft(nft: cached, isHiddenByUser: false, isUnhiddenByUser: true).shouldHide(areUnverifiedNftsHidden: false))
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

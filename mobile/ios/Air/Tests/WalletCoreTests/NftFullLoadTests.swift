import Foundation
import Dependencies
import GRDB
import Testing
import WalletContext
@testable import WalletCore

@Suite("NFT full loads")
struct NftFullLoadTests {
    @Test
    func `a network is read in full from the end of a full load until another one starts`() {
        let store = _NftStore(cacheUrl: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
        let update = { (isFullLoading: Bool?, streamedAddresses: [String]?) in
            store.recordFullLoad(.init(
                accountId: "account", nfts: [], chain: .ton,
                isFullLoading: isFullLoading, streamedAddresses: streamedAddresses
            ))
        }

        update(true, nil)
        #expect(store.getAccountFullyLoadedChains(accountId: "account").isEmpty)
        update(false, ["nft-address"])
        #expect(store.getAccountFullyLoadedChains(accountId: "account") == [.ton])
        // A collection or a single NFT does not say whether the network was read in full
        update(nil, nil)
        #expect(store.getAccountFullyLoadedChains(accountId: "account") == [.ton])
        update(true, nil)
        #expect(store.getAccountFullyLoadedChains(accountId: "account").isEmpty)
    }

    @Test @MainActor
    func `NFT changes replace fields while preserving manual order and visibility choices`() async throws {
        let accountId = UUID().uuidString
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try MAccount(id: accountId, title: nil, type: .view, byChain: [ApiChain: AccountChain]()).insert(db)
        }
        let store = _NftStore(cacheUrl: temporaryCacheUrl())
        await store.use(db: db, accountIds: [accountId])
        defer { WalletCoreData.remove(observer: store) }
        let initial = ["first", "middle", "last", "hidden"].map {
            ApiNft(chain: .ton, name: "Original", address: $0, isOnSale: false)
        }
        store.walletCore(event: .updateNfts(.init(accountId: accountId, nfts: initial, chain: .ton)))
        try await waitUntil { store.getAccountNfts(accountId: accountId)?.count == 4 }
        store.setHiddenByUser(accountId: accountId, nft: initial[1], isHidden: false)
        store.setHiddenByUser(accountId: accountId, nft: initial[3], isHidden: true)
        store.reorderNfts(accountId: accountId, orderedIdsHint: ["last", "middle", "first"])
        let orderedIds = Array(try #require(store.getAccountNfts(accountId: accountId)).keys)

        var changed = initial[1]
        changed.name = "Updated"
        changed.isOnSale = true
        changed.isHidden = true
        changed.metadata = .init(lottie: "https://example.com/updated.json")
        var hidden = initial[3]
        hidden.name = "Updated hidden NFT"
        store.walletCore(event: .nftChanged(.init(accountId: accountId, chain: .ton, nft: changed)))
        store.walletCore(event: .nftChanged(.init(accountId: accountId, chain: .ton, nft: hidden)))
        try await waitUntil { store.getNft(accountId: accountId, nftId: hidden.id)?.nft.name == hidden.name }

        #expect(Array(try #require(store.getAccountNfts(accountId: accountId)).keys) == orderedIds)
        let updated = try #require(store.getNft(accountId: accountId, nftId: changed.id))
        #expect(updated.nft.name == "Updated")
        #expect(updated.nft.isOnSale)
        #expect(updated.nft.metadata?.lottie == changed.metadata?.lottie)
        #expect(updated.isUnhiddenByUser)
        #expect(!updated.isHiddenByUser)
        #expect(!updated.shouldHide)
        #expect(store.getNft(accountId: accountId, nftId: hidden.id)?.isHiddenByUser == true)

        var automaticallyHidden = initial[2]
        automaticallyHidden.isHidden = true
        store.walletCore(event: .nftChanged(.init(accountId: accountId, chain: .ton, nft: automaticallyHidden)))
        try await waitUntil {
            store.getAccountNfts(accountId: accountId).map { Array($0.keys) } == ["middle", "first", "hidden", "last"]
        }
    }

    @Test
    func `a missing changed NFT is inserted like a received NFT`() async throws {
        let store = _NftStore(cacheUrl: temporaryCacheUrl())
        let accountId = UUID().uuidString
        let existing = ApiNft(chain: .ton, address: "existing", isOnSale: false)
        let incoming = ApiNft(chain: .ton, name: "New NFT", address: "incoming", isOnSale: false)
        store.walletCore(event: .nftReceived(.init(accountId: accountId, nftAddress: existing.address, nft: existing)))
        store.walletCore(event: .nftChanged(.init(accountId: accountId, chain: .ton, nft: incoming)))
        try await waitUntil { store.getAccountNfts(accountId: accountId)?.count == 2 }

        #expect(Array(try #require(store.getAccountNfts(accountId: accountId)).keys) == [incoming.id, existing.id])
        #expect(store.getNft(accountId: accountId, nftId: incoming.id)?.nft.name == "New NFT")
        #expect(store.getAccountShownNfts(accountId: accountId)?.count == 2)
    }

    @Test @MainActor
    func `an NFT removed before its listing delta returns to the gallery on sale`() async throws {
        let store = _NftStore(cacheUrl: temporaryCacheUrl())
        let accountId = UUID().uuidString
        var nft = ApiNft(chain: .ton, address: "listed", isOnSale: false)
        store.walletCore(event: .nftReceived(.init(accountId: accountId, nftAddress: nft.address, nft: nft)))
        try await waitUntil { store.getNft(accountId: accountId, nftId: nft.id) != nil }
        withDependencies {
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            store.handleEvent(.nftSent(.init(
                accountId: accountId, chain: .ton, nftAddress: nft.address, newOwnerAddress: "marketplace"
            )))
        }
        #expect(store.getNft(accountId: accountId, nftId: nft.id) == nil)

        nft.isOnSale = true
        store.walletCore(event: .nftChanged(.init(accountId: accountId, chain: .ton, nft: nft)))
        try await waitUntil { store.getNft(accountId: accountId, nftId: nft.id)?.nft.isOnSale == true }

        #expect(store.getAccountShownNfts(accountId: accountId)?[nft.id]?.nft.isOnSale == true)
    }

    @Test @MainActor
    func `a change of the installed card replaces the card background`() async throws {
        let accountId = UUID().uuidString
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try MAccount(id: accountId, title: nil, type: .view, byChain: [ApiChain: AccountChain]()).insert(db)
        }
        let settingsStore = AccountSettingsStore()
        await settingsStore.use(db: db)
        defer { WalletCoreData.remove(observer: settingsStore) }
        withDependencies {
            $0[AccountSettingsStore.self] = settingsStore
        } operation: {
            let store = _NftStore(cacheUrl: temporaryCacheUrl())
            let settings = settingsStore.for(accountId: accountId)
            let installed = ApiNft(
                chain: .ton, name: "Card", address: "installed", collectionAddress: MTW_CARDS_COLLECTION, isOnSale: false
            )
            settings.setBackgroundNft(installed)

            let other = ApiNft(chain: .ton, name: "Other card", address: "other", collectionAddress: MTW_CARDS_COLLECTION, isOnSale: false)
            store.replaceInstalledMtwCard(accountId: accountId, nft: other)
            #expect(settings.backgroundNft?.id == installed.id)
            #expect(settings.backgroundNft?.name == "Card")

            var changed = installed
            changed.name = "Renamed card"
            changed.metadata = .init(lottie: "https://example.com/card.json")
            store.replaceInstalledMtwCard(accountId: accountId, nft: changed)
            // `ApiNft` equality compares only the chain and the address
            #expect(settings.backgroundNft?.id == changed.id)
            #expect(settings.backgroundNft?.name == "Renamed card")
            #expect(settings.backgroundNft?.metadata?.lottie == changed.metadata?.lottie)
        }
    }

    private func temporaryCacheUrl() -> URL {
        URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

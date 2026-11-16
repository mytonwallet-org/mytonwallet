import Testing
@testable import WalletCore
import WalletCoreTypes

@Suite("Telegram gift catalog")
struct TelegramGiftCatalogTests {
    private func gift(_ index: Int, collection: String = "large") -> DisplayNft {
        DisplayNft(nft: ApiNft(
            chain: .ton, address: "gift-\(index)", collectionName: collection,
            collectionAddress: collection, isOnSale: false, isTelegramGift: true
        ), isHiddenByUser: false)
    }

    @Test(arguments: [0, 1, 999, 1000, 1001, 2501])
    func boundaryCounts(_ count: Int) {
        let catalog = TelegramGiftCatalog(nfts: (0..<count).map { gift($0) })
        #expect(catalog.count == count)
        #expect((catalog.collections.first?.count ?? 0) == count)
    }

    @Test
    func identitiesCountsAndHiddenGifts() {
        var gifts = (0..<1501).map { gift($0, collection: "z") } + (1501..<2501).map { gift($0, collection: "a") }
        for index in gifts.indices { gifts[index].nft.collectionName = "Same" }
        gifts[0].isHiddenByUser = true
        let catalog = TelegramGiftCatalog(nfts: gifts)
        #expect(catalog.count == 2501)
        #expect(catalog.collections.map(\.count) == [1501, 1000])
        #expect(catalog.collections.map(\.collection.address) == ["z", "a"])
        #expect(catalog.hiddenCount == 1)
    }

    @Test
    func duplicatesNonGiftsOtherChainsAndMissingCollections() {
        var nonGift = gift(2)
        nonGift.nft.isTelegramGift = false
        var otherChain = gift(3)
        otherChain.nft.chain = .ethereum
        var noCollection = gift(4)
        noCollection.nft.collectionAddress = nil
        #expect(TelegramGiftCatalog(nfts: [gift(1), gift(1), nonGift, otherChain, noCollection]).count == 1)
    }

    @Test
    func hiddenCollectionsAreCountedWithoutBeingDisplayed() {
        var hidden = gift(2, collection: "hidden")
        hidden.isHiddenByUser = true
        let catalog = TelegramGiftCatalog(nfts: [gift(1, collection: "visible"), hidden])
        #expect(catalog.count == 2)
        #expect(catalog.hiddenCount == 1)
        #expect(catalog.visibleCollections.map(\.collection.address) == ["visible"])
    }

    @Test
    func equalCountsAndMissingNamesHaveAStableOrder() {
        var gifts = [gift(1, collection: "z"), gift(2, collection: "a")]
        for index in gifts.indices { gifts[index].nft.collectionName = nil }
        let catalog = TelegramGiftCatalog(nfts: gifts)
        #expect(catalog == TelegramGiftCatalog(nfts: Array(gifts.reversed())))
        #expect(catalog.collections.map(\.collection.name) == ["a", "z"])
    }

    @Test
    func labelsUseVisibleMetadataAndRemainStableAcrossPageOrder() {
        var gifts = [gift(1), gift(2), gift(3)]
        gifts[0].nft.collectionName = "  Z  "
        gifts[1].nft.collectionName = "A hidden metadata"
        gifts[1].isHiddenByUser = true
        gifts[2].nft.collectionName = "  "
        let catalog = TelegramGiftCatalog(nfts: gifts)
        #expect(catalog == TelegramGiftCatalog(nfts: Array(gifts.reversed())))
        #expect(catalog.collections.first?.collection.name == "Z")
        #expect(catalog.count == 3)
        #expect(catalog.hiddenCount == 1)
    }
}

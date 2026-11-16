import Foundation
import WalletCoreTypes

public struct TelegramGiftCollection: Equatable, Hashable, Sendable {
    public var collection: NftCollection
    public var count: Int
    public var hiddenCount: Int
}

public struct TelegramGiftCatalog: Equatable, Sendable {
    public var collections: [TelegramGiftCollection]
    public var count: Int { collections.reduce(0) { $0 + $1.count } }
    public var hiddenCount: Int { collections.reduce(0) { $0 + $1.hiddenCount } }
    public var visibleCollections: [TelegramGiftCollection] { collections.filter { $0.hiddenCount < $0.count } }

    public init(nfts: [DisplayNft]) {
        var seen = Set<String>()
        let gifts = nfts.filter {
            $0.nft.chain == .ton && $0.nft.isTelegramGift == true &&
                !($0.nft.collectionAddress ?? "").isEmpty && seen.insert($0.nft.address).inserted
        }
        collections = Dictionary(grouping: gifts, by: { $0.nft.collectionAddress! }).map { address, items in
            let visibleItems = items.filter { !$0.shouldHide }
            let name = visibleItems.compactMap { $0.nft.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.min() ?? address
            return TelegramGiftCollection(
                collection: NftCollection(chain: .ton, address: address, name: name),
                count: items.count,
                hiddenCount: items.count - visibleItems.count
            )
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.collection < $1.collection
        }
    }
}

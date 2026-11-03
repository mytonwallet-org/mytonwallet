import Foundation
import OrderedCollections
import Testing
import WalletContext
@testable import WalletCore

@Suite("NFT order")
struct NftOrderTests {
    @Test
    func `the order check of an out-of-order gallery moves hidden NFTs after the visible ones`() {
        let store = _NftStore(
            cacheUrl: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json"),
            assertsNftsOrder: false
        )
        let accountId = UUID().uuidString
        let gallery = [("hidden", true), ("first", false), ("second", false)].map { address, isHiddenByUser in
            DisplayNft(nft: ApiNft(chain: .ton, address: address, isOnSale: false), isHiddenByUser: isHiddenByUser)
        }
        store._nfts.withLock {
            $0[accountId] = OrderedDictionary(uniqueKeysWithValues: gallery.map { ($0.id, $0) })
        }

        // The repair runs under the store lock, which is not recursive
        store._checkNftsOrder(accountId: accountId)

        #expect(store.getAccountNfts(accountId: accountId).map { Array($0.keys) } == [gallery[1].id, gallery[2].id, gallery[0].id])
    }
}

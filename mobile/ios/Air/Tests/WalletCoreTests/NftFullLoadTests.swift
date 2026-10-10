import Foundation
import Testing
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
}

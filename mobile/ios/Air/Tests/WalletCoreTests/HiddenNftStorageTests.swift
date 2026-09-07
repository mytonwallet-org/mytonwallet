import Foundation
import Testing
@testable import WalletCore

@Suite("Hidden NFT Storage")
struct HiddenNftStorageTests {
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

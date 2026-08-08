import Testing
@testable import UISend
import WalletCore

@Suite("Send Navigation")
struct SendNavigationTests {
    @Test
    func `regular send maps external values into token configuration`() throws {
        let route = try SendRoute(prefilledValues: .init(
            address: "recipient",
            amount: 42,
            token: "toncoin",
            commentOrMemo: "memo"
        ))

        guard case .tokenCompose(let configuration) = route else {
            Issue.record("Expected token compose route")
            return
        }
        #expect(configuration.mode == .send)
        #expect(configuration.initialAddress == "recipient")
        #expect(configuration.initialAmount == 42)
        #expect(configuration.initialTokenSlug == "toncoin")
        #expect(configuration.initialComment == "memo")
    }

    @Test
    func `sell maps into token review`() throws {
        let route = try SendRoute(
            prefilledValues: .init(mode: .sellToMoonpay)
        )

        guard case .tokenReview(let configuration) = route else {
            Issue.record("Expected token review route")
            return
        }
        #expect(configuration.mode == .sellToMoonpay)
    }

    @Test
    func `NFT send maps into fixed-chain NFT configuration`() throws {
        let nft = makeNft(chain: .solana, address: "nft")
        let route = try SendRoute(prefilledValues: .init(
            mode: .sendNft,
            address: "recipient",
            nfts: [nft]
        ))

        guard case .nftCompose(let configuration) = route else {
            Issue.record("Expected NFT compose route")
            return
        }
        #expect(configuration.mode == .send)
        #expect(configuration.chain == .solana)
        #expect(configuration.nfts == [nft])
        #expect(configuration.initialAddress == "recipient")
    }

    @Test
    func `NFT burn maps into NFT review`() throws {
        let nft = makeNft(chain: .ton, address: "nft")
        let route = try SendRoute(prefilledValues: .init(
            mode: .burnNft,
            nfts: [nft]
        ))

        guard case .nftReview(let configuration) = route else {
            Issue.record("Expected NFT review route")
            return
        }
        #expect(configuration.mode == .burn)
        #expect(configuration.chain == .ton)
    }

    @Test
    func `prefilled NFTs select NFT flow at the boundary`() throws {
        let route = try SendRoute(prefilledValues: .init(
            nfts: [makeNft(chain: .ton, address: "nft")]
        ))

        guard case .nftCompose = route else {
            Issue.record("Expected NFT compose route")
            return
        }
    }

    @Test
    func `NFT route rejects an empty selection`() {
        #expect(throws: SendRouteError.missingNfts) {
            try SendRoute(
                prefilledValues: .init(mode: .sendNft)
            )
        }
    }

    @Test
    func `NFT route rejects mixed chains`() {
        #expect(throws: SendRouteError.mixedNftChains) {
            try SendRoute(prefilledValues: .init(
                mode: .sendNft,
                nfts: [
                    makeNft(chain: .ton, address: "ton-nft"),
                    makeNft(
                        chain: .solana,
                        address: "solana-nft"
                    ),
                ]
            ))
        }
    }
}

import Testing
@testable import WalletCore

@Suite("Account NFT Availability")
struct AccountNftAvailabilityValidatorTests {
    @Test
    func `finalized stream clears missing selected NFT without requiring cache sync`() {
        let nft = ApiNft(chain: .ton, address: "card-address", isOnSale: false)
        let context = AccountNftAvailabilityValidationContext(
            reason: "streamFinal:ton:count=1",
            chain: .ton,
            authoritativeAddresses: ["other-address"],
            removedAddress: nil
        )

        #expect(AccountNftAvailabilityValidator.shouldClearAccountNft(
            nft: nft,
            context: context,
            nftIds: [],
            nftAddresses: []
        ))
    }

    @Test
    func `finalized stream keeps selected NFT when authoritative list contains it`() {
        let nft = ApiNft(chain: .ton, address: "card-address", isOnSale: false)
        let context = AccountNftAvailabilityValidationContext(
            reason: "streamFinal:ton:count=1",
            chain: .ton,
            authoritativeAddresses: ["card-address"],
            removedAddress: nil
        )

        #expect(!AccountNftAvailabilityValidator.shouldClearAccountNft(
            nft: nft,
            context: context,
            nftIds: [],
            nftAddresses: []
        ))
    }

    @Test
    func `explicit sent update clears matching selected NFT`() {
        let nft = ApiNft(chain: .ton, address: "card-address", isOnSale: false)
        let context = AccountNftAvailabilityValidationContext(
            reason: "nftSent:ton:card-address",
            chain: .ton,
            authoritativeAddresses: nil,
            removedAddress: "card-address"
        )

        #expect(AccountNftAvailabilityValidator.shouldClearAccountNft(
            nft: nft,
            context: context,
            nftIds: ["card-address"],
            nftAddresses: ["card-address"]
        ))
    }
}

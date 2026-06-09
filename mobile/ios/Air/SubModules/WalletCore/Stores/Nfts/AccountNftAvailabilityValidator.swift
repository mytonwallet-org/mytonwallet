import Foundation
import WalletCoreTypes

struct AccountNftAvailabilityValidationContext: Equatable, Sendable {
    let reason: String
    let chain: ApiChain
    let authoritativeAddresses: Set<String>?
    let removedAddress: String?
}

enum AccountNftAvailabilityValidator {
    static func shouldClearAccountNft(
        nft: ApiNft,
        context: AccountNftAvailabilityValidationContext,
        nftIds: Set<String>,
        nftAddresses: Set<String>
    ) -> Bool {
        if let removedAddress = context.removedAddress {
            return matches(nft: nft, chain: context.chain, address: removedAddress)
        }

        if let authoritativeAddresses = context.authoritativeAddresses {
            return !contains(nft: nft, chain: context.chain, addresses: authoritativeAddresses)
        }

        return !nftIds.contains(nft.id) && !nftAddresses.contains(nft.address)
    }

    private static func matches(nft: ApiNft, chain: ApiChain, address: String) -> Bool {
        nft.address == address || nft.id == ApiNft.id(chain: chain, address: address)
    }

    private static func contains(nft: ApiNft, chain: ApiChain, addresses: Set<String>) -> Bool {
        addresses.contains(nft.address) || addresses.contains { address in
            nft.id == ApiNft.id(chain: chain, address: address)
        }
    }
}

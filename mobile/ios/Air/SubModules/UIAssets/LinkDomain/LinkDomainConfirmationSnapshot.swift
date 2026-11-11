import WalletContext
import WalletCore

struct LinkDomainConfirmationSnapshot: Sendable {
    let account: MAccount
    let nft: ApiNft
    /// A `nil` address unlinks the domain from its wallet
    let destinationAddress: String?
    let destinationName: String?
    let realFee: BigInt

    var isUnlinking: Bool { destinationAddress == nil }
}

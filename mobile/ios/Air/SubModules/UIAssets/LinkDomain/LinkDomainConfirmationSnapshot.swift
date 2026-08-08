import WalletContext
import WalletCore

struct LinkDomainConfirmationSnapshot: Sendable {
    let account: MAccount
    let nft: ApiNft
    let destinationAddress: String
    let destinationName: String?
    let realFee: BigInt
}

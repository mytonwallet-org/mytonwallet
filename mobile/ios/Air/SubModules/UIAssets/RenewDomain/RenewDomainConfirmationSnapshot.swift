import WalletContext
import WalletCore

struct RenewDomainConfirmationSnapshot: Sendable {
    let account: MAccount
    let nfts: [ApiNft]
    let realFee: BigInt
}

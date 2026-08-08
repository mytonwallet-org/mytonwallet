import WalletContext
import WalletCore

struct NftSendConfiguration: Equatable, Sendable {
    let mode: NftSendMode
    let initialAddress: String?
    let nfts: [ApiNft]
    let chain: ApiChain
    let initialComment: String
}

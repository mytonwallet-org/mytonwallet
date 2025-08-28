
import WalletContext

public enum NftSendMode {
    case send
    case burn
}

public struct SendPrefilledValues {
    public var address: String?
    public var amount: BigInt?
    public var token: String?
    public var jetton: String?
    public var commentOrMemo: String?
    public var binaryPayload: String?
    public var nfts: [ApiNft]?
    public var nftSendMode: NftSendMode?
    
    public init(address: String? = nil, amount: BigInt? = nil, token: String? = nil, jetton: String? = nil, commentOrMemo: String? = nil, binaryPayload: String? = nil, nfts: [ApiNft]? = nil, nftSendMode: NftSendMode? = nil) {
        self.address = address
        self.amount = amount
        self.token = token
        self.jetton = jetton
        self.commentOrMemo = commentOrMemo
        self.binaryPayload = binaryPayload
        self.nfts = nfts
        self.nftSendMode = nftSendMode
    }
}

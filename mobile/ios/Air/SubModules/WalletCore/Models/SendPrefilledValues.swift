
import WalletContext

public enum SendMode {
    case regular
    
    case sendNft, burnNft
    
    /// Read-only mode, all values are set, start from the confirmation screen
    case sellToMoonpay
            
    public var isNftRelated: Bool { self == .burnNft || self == .sendNft}
}

public struct SendPrefilledValues {
    public let mode: SendMode
    public let address: String?
    public let amount: BigInt?
    public let token: String?
    public let jetton: String?
    public let commentOrMemo: String?
    public let binaryPayload: String?
    public let nfts: [ApiNft]?
    public let stateInit: String?
    
    public init(mode: SendMode = .regular, address: String? = nil, amount: BigInt? = nil, token: String? = nil, jetton: String? = nil,
                commentOrMemo: String? = nil, binaryPayload: String? = nil, nfts: [ApiNft]? = nil, stateInit: String? = nil) {
        self.mode = mode
        self.address = address
        self.amount = amount
        self.token = token
        self.jetton = jetton
        self.commentOrMemo = commentOrMemo
        self.binaryPayload = binaryPayload
        self.nfts = nfts
        self.stateInit = stateInit
    }
}

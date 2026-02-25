
import UIKit
import WalletContext


public struct ApiTransactionActivity: BaseActivity, Codable, Equatable, Hashable, Sendable {
    
    // BaseActivity
    public let id: String
    public var kind: String = "transaction"
    public var shouldHide: Bool?
    /** Trace external message hash normalized. Only for TON. */
    public let externalMsgHashNorm: String?
    public var shouldReload: Bool?
    public var shouldLoadDetails: Bool?
    public var extra: BaseActivityExtra?

    public let timestamp: Int64
    /** The amount to show in the UI (may mismatch the actual attached TON amount */
    public let amount: BigInt
    public let fromAddress: String?
    public let toAddress: String?
    public let comment: String?
    public let encryptedComment: String?
    /**
      * The fee to show in the UI (not the same as the network fee). When not 0, should be shown even for incoming
      * transactions. It means that there was a hidden outgoing transaction with the given fee.
      */
    public let fee: BigInt
    public let slug: String
    public let isIncoming: Bool
    public let normalizedAddress: String?
    public let type: ApiTransactionType?
    public let metadata: ApiAddressInfo?
    public let nft: ApiNft?
    /**
     * Transaction confirmation status
     * Both 'pendingTrusted' and 'pending' mean the transaction is awaiting confirmation by the blockchain.
     * - 'pendingTrusted' — awaiting confirmation and trusted (initiated by our app)
     * - 'pending' — awaiting confirmation from an external/unauthenticated source, like TonConnect emulation
     */
    public var status: ApiTransactionStatus
    
    public init(id: String, kind: String, shouldHide: Bool? = nil, externalMsgHashNorm: String?, shouldReload: Bool? = nil, shouldLoadDetails: Bool? = nil, extra: BaseActivityExtra? = nil, timestamp: Int64, amount: BigInt, fromAddress: String, toAddress: String?, comment: String?, encryptedComment: String?, fee: BigInt, slug: String, isIncoming: Bool, normalizedAddress: String?, type: ApiTransactionType?, metadata: ApiAddressInfo?, nft: ApiNft?, status: ApiTransactionStatus) {
        self.id = id
        self.kind = kind
        self.shouldHide = shouldHide
        self.externalMsgHashNorm = externalMsgHashNorm
        self.shouldReload = shouldReload
        self.shouldLoadDetails = shouldLoadDetails
        self.extra = extra
        self.timestamp = timestamp
        self.amount = amount
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.comment = comment
        self.encryptedComment = encryptedComment
        self.fee = fee
        self.slug = slug
        self.isIncoming = isIncoming
        self.normalizedAddress = normalizedAddress
        self.type = type
        self.metadata = metadata
        self.nft = nft
        self.status = status
    }
    
    public var isStaking: Bool {
        type == .stake ||
        type == .unstake ||
        type == .unstakeRequest
    }
}

public enum ApiTransactionStatus: String, Equatable, Codable, Hashable, Sendable {
    case pending
    case pendingTrusted
    case confirmed
    case completed
    case failed
}

public extension ApiTransactionActivity {
    
    var peerAddress: String? {
        isIncoming ? fromAddress : toAddress
    }
    
    var addressToShow: String {
        metadata?.name ?? peerAddress ?? ""
    }
    
    enum AddressKind {
        case from
        case to
        case peer
    }
    
    func getAddress(for kind: AddressKind) -> String? {
        switch kind {
        case .from: return fromAddress
        case .to: return toAddress
        case .peer: return peerAddress
        }
    }
}

public struct ApiAddressInfo: Equatable, Hashable, Codable, Sendable {
    public let name: String?
    public let isScam: Bool?
    public let isMemoRequired: Bool?
    
    public init(name: String?, isScam: Bool?, isMemoRequired: Bool?) {
        self.name = name
        self.isScam = isScam
        self.isMemoRequired = isMemoRequired
    }
}

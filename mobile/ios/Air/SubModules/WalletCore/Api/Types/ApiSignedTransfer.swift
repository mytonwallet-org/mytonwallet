
import Foundation
import WalletContext

public struct ApiSignedTransfer: Equatable, Hashable, Codable, Sendable {
    public var base64: String
    public var seqno: Int
    
    public init(base64: String, seqno: Int) {
        self.base64 = base64
        self.seqno = seqno
    }
}


public struct ApiLocalTransactionParams: Equatable, Hashable, Codable, Sendable {
    
    public var kind = "transaction"
    public var amount: BigInt
    public var fromAddress: String
    public var toAddress: String
    public var comment: String?
    public var encryptedComment: String?
    public var fee: BigInt
    public var normalizedAddress: String?
    public var slug: String

    public var txId: String?
    public var externalMsgHashNorm: String?
    
    public init(amount: BigInt, fromAddress: String, toAddress: String, comment: String?, encryptedComment: String?, fee: BigInt, normalizedAddress: String?, slug: String, txId: String? = nil, externalMsgHashNorm: String? = nil) {
        self.amount = amount
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.comment = comment
        self.encryptedComment = encryptedComment
        self.fee = fee
        self.normalizedAddress = normalizedAddress
        self.slug = slug
        self.txId = txId
        self.externalMsgHashNorm = externalMsgHashNorm
    }
}

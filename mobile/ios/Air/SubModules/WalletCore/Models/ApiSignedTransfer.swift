
import Foundation
import WalletContext

public struct ApiSignedTransfer: Equatable, Hashable, Codable, Sendable {
    public var chain: ApiChain
    public var payload: ApiSignedTransferPayload
    
    public init(chain: ApiChain, payload: ApiSignedTransferPayload) {
        self.chain = chain
        self.payload = payload
    }
}

public enum ApiSignedTransferPayload: Equatable, Hashable, Codable, Sendable {
    case ton(base64: String, seqno: Int)
    case walletConnect(signature: String, base58Tx: String)

    enum CodingKeys: String, CodingKey {
        case base64
        case seqno
        case signature
        case base58Tx
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let base64 = try container.decodeIfPresent(String.self, forKey: .base64),
           let seqno = try container.decodeIfPresent(Int.self, forKey: .seqno) {
            self = .ton(base64: base64, seqno: seqno)
            return
        }
        if let signature = try container.decodeIfPresent(String.self, forKey: .signature),
           let base58Tx = try container.decodeIfPresent(String.self, forKey: .base58Tx) {
            self = .walletConnect(signature: signature, base58Tx: base58Tx)
            return
        }
        throw DecodingError.dataCorruptedError(forKey: .base64, in: container, debugDescription: "Unsupported signed transfer payload")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ton(let base64, let seqno):
            try container.encode(base64, forKey: .base64)
            try container.encode(seqno, forKey: .seqno)
        case .walletConnect(let signature, let base58Tx):
            try container.encode(signature, forKey: .signature)
            try container.encode(base58Tx, forKey: .base58Tx)
        }
    }
}

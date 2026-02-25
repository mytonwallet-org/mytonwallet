import Foundation

public struct TonConnectConnectRequest: Codable, Sendable {
    public var manifestUrl: String
    public var items: [TonConnectConnectItem]

    public init(manifestUrl: String, items: [TonConnectConnectItem]) {
        self.manifestUrl = manifestUrl
        self.items = items
    }
}

public struct TonConnectConnectItem: Codable, Sendable {
    public var name: String
    public var payload: String?

    public init(name: String, payload: String? = nil) {
        self.name = name
        self.payload = payload
    }
}

public enum TonConnectNetwork: String, Codable, Sendable {
    case mainnet = "-239"
    case testnet = "-3"
}

public struct TonConnectTransactionMessage: Codable, Sendable {
    public var address: String
    public var amount: String
    public var payload: String?
    public var stateInit: String?

    public init(address: String, amount: String, payload: String? = nil, stateInit: String? = nil) {
        self.address = address
        self.amount = amount
        self.payload = payload
        self.stateInit = stateInit
    }
}

public struct TonConnectTransactionPayload: Codable, Sendable {
    public var validUntil: Int?
    public var network: TonConnectNetwork?
    public var from: String?
    public var messages: [TonConnectTransactionMessage]

    enum CodingKeys: String, CodingKey {
        case validUntil = "valid_until"
        case network
        case from
        case messages
    }

    public init(validUntil: Int? = nil, network: TonConnectNetwork? = nil, from: String? = nil, messages: [TonConnectTransactionMessage]) {
        self.validUntil = validUntil
        self.network = network
        self.from = from
        self.messages = messages
    }
}

public struct TonConnectConnectEvent: Codable, Sendable {
    public var event: String
    public var id: Int
    public var payload: TonConnectConnectEventPayload

    public init(event: String, id: Int, payload: TonConnectConnectEventPayload) {
        self.event = event
        self.id = id
        self.payload = payload
    }

    public static func connect(id: Int, payload: TonConnectConnectPayload) -> TonConnectConnectEvent {
        TonConnectConnectEvent(event: "connect", id: id, payload: .connect(payload))
    }

    public static func connectError(id: Int, payload: TonConnectConnectErrorPayload) -> TonConnectConnectEvent {
        TonConnectConnectEvent(event: "connect_error", id: id, payload: .connectError(payload))
    }

    enum CodingKeys: String, CodingKey {
        case event
        case id
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.event = try container.decode(String.self, forKey: .event)
        self.id = try container.decode(Int.self, forKey: .id)

        switch event {
        case "connect":
            let payload = try container.decode(TonConnectConnectPayload.self, forKey: .payload)
            self.payload = .connect(payload)
        case "connect_error":
            let payload = try container.decode(TonConnectConnectErrorPayload.self, forKey: .payload)
            self.payload = .connectError(payload)
        default:
            let payload = try container.decode(AnyCodable.self, forKey: .payload)
            self.payload = .unknown(payload)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(id, forKey: .id)
        switch payload {
        case .connect(let value):
            try container.encode(value, forKey: .payload)
        case .connectError(let value):
            try container.encode(value, forKey: .payload)
        case .unknown(let value):
            try container.encode(value, forKey: .payload)
        }
    }
}

public enum TonConnectConnectEventPayload: Sendable {
    case connect(TonConnectConnectPayload)
    case connectError(TonConnectConnectErrorPayload)
    case unknown(AnyCodable)
}

public struct TonConnectConnectPayload: Codable, Sendable {
    public var items: [TonConnectConnectItemReply]
    public var device: TonConnectDeviceInfo

    public init(items: [TonConnectConnectItemReply], device: TonConnectDeviceInfo) {
        self.items = items
        self.device = device
    }
}

public struct TonConnectConnectErrorPayload: Codable, Sendable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public enum TonConnectConnectItemReply: Codable, Sendable {
    case tonAddress(TonConnectAddressItemReply)
    case tonProof(TonConnectProofItemReply)
    case unknown(AnyCodable)

    enum CodingKeys: String, CodingKey {
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        switch name {
        case "ton_addr":
            self = .tonAddress(try TonConnectAddressItemReply(from: decoder))
        case "ton_proof":
            self = .tonProof(try TonConnectProofItemReply(from: decoder))
        default:
            self = .unknown(try AnyCodable(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .tonAddress(let value):
            try value.encode(to: encoder)
        case .tonProof(let value):
            try value.encode(to: encoder)
        case .unknown(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct TonConnectAddressItemReply: Codable, Sendable {
    public var name: String
    public var address: String
    public var network: String
    public var publicKey: String
    public var walletStateInit: String

    public init(name: String, address: String, network: String, publicKey: String, walletStateInit: String) {
        self.name = name
        self.address = address
        self.network = network
        self.publicKey = publicKey
        self.walletStateInit = walletStateInit
    }
}

public struct TonConnectProofItemReply: Codable, Sendable {
    public var name: String
    public var proof: TonConnectProofReply

    public init(name: String, proof: TonConnectProofReply) {
        self.name = name
        self.proof = proof
    }
}

public struct TonConnectProofReply: Codable, Sendable {
    public var timestamp: Int
    public var domain: TonConnectDomain
    public var signature: String
    public var payload: String

    public init(timestamp: Int, domain: TonConnectDomain, signature: String, payload: String) {
        self.timestamp = timestamp
        self.domain = domain
        self.signature = signature
        self.payload = payload
    }
}

public struct TonConnectDomain: Codable, Sendable {
    public var lengthBytes: Int
    public var value: String

    enum CodingKeys: String, CodingKey {
        case lengthBytes
        case value
    }

    public init(lengthBytes: Int, value: String) {
        self.lengthBytes = lengthBytes
        self.value = value
    }
}

public struct TonConnectDeviceInfo: Codable, Sendable {
    public var platform: String
    public var appName: String
    public var appVersion: String
    public var maxProtocolVersion: Int
    public var features: [TonConnectDeviceFeature]

    public init(platform: String, appName: String, appVersion: String, maxProtocolVersion: Int, features: [TonConnectDeviceFeature]) {
        self.platform = platform
        self.appName = appName
        self.appVersion = appVersion
        self.maxProtocolVersion = maxProtocolVersion
        self.features = features
    }
}

public enum TonConnectDeviceFeature: Codable, Sendable {
    case string(String)
    case sendTransaction(TonConnectSendTransactionFeature)
    case signData(TonConnectSignDataFeature)
    case unknown(AnyCodable)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let feature = try? container.decode(TonConnectSendTransactionFeature.self), feature.name == "SendTransaction" {
            self = .sendTransaction(feature)
            return
        }
        if let feature = try? container.decode(TonConnectSignDataFeature.self), feature.name == "SignData" {
            self = .signData(feature)
            return
        }
        self = .unknown(try AnyCodable(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .sendTransaction(let value):
            try value.encode(to: encoder)
        case .signData(let value):
            try value.encode(to: encoder)
        case .unknown(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct TonConnectSendTransactionFeature: Codable, Sendable {
    public var name: String
    public var maxMessages: Int?

    public init(name: String = "SendTransaction", maxMessages: Int? = nil) {
        self.name = name
        self.maxMessages = maxMessages
    }
}

public struct TonConnectSignDataFeature: Codable, Sendable {
    public var name: String
    public var types: [String]

    public init(name: String = "SignData", types: [String]) {
        self.name = name
        self.types = types
    }
}

public struct ApiDappTransactionRequest<Payload: Codable & Sendable>: Codable, Sendable {
    public var id: String
    public var chain: ApiChain
    public var payload: Payload

    public init(id: String, chain: ApiChain, payload: Payload) {
        self.id = id
        self.chain = chain
        self.payload = payload
    }
}

public struct ApiDappSignDataRequest<Payload: Codable & Sendable>: Codable, Sendable {
    public var id: String
    public var chain: ApiChain
    public var payload: Payload

    public init(id: String, chain: ApiChain, payload: Payload) {
        self.id = id
        self.chain = chain
        self.payload = payload
    }
}

public typealias ApiTonConnectSendTransactionRequest = ApiDappTransactionRequest<TonConnectTransactionPayload>
public typealias ApiTonConnectSignDataRequest = ApiDappSignDataRequest<SignDataPayload>

public struct ApiDappSignDataResult: Codable, Sendable {
    public var chain: ApiChain
    public var result: ApiDappSignDataPayloadResult

    public init(chain: ApiChain, result: ApiDappSignDataPayloadResult) {
        self.chain = chain
        self.result = result
    }
}

public struct ApiTonConnectSignDataResponse: Codable, Sendable {
    public var id: String
    public var result: ApiDappSignDataResult

    public init(id: String, result: ApiDappSignDataResult) {
        self.id = id
        self.result = result
    }
}

public struct ApiDappSignDataPayloadResult: Codable, Sendable {
    public var signature: String
    public var address: String
    public var timestamp: Int
    public var domain: String
    public var payload: SignDataPayload

    public init(signature: String, address: String, timestamp: Int, domain: String, payload: SignDataPayload) {
        self.signature = signature
        self.address = address
        self.timestamp = timestamp
        self.domain = domain
        self.payload = payload
    }
}

public struct ApiEmptyResult: Codable, Sendable {
    public init() {}
}

public struct ApiTonConnectDisconnectResult: Codable, Sendable {
    public var id: String
    public var result: ApiEmptyResult

    public init(id: String, result: ApiEmptyResult) {
        self.id = id
        self.result = result
    }
}

import Foundation
import WalletContext

public enum ApiDappProtocolType: String, Codable, Sendable {
    case tonConnect = "tonConnect"
    case walletConnect = "walletConnect"
}

public enum ApiDappTransportType: String, Codable, Sendable {
    case `extension` = "extension"
    case inAppBrowser = "inAppBrowser"
    case sse = "sse"
    case relay = "relay"
}

public struct ApiDappPermissions: Codable, Sendable {
    public var isAddressRequired: Bool?
    public var isPasswordRequired: Bool?

    public init(isAddressRequired: Bool? = nil, isPasswordRequired: Bool? = nil) {
        self.isAddressRequired = isAddressRequired
        self.isPasswordRequired = isPasswordRequired
    }
}

public struct ApiDappRequestedChain: Codable, Sendable {
    public var chain: ApiChain
    public var network: ApiNetwork

    public init(chain: ApiChain, network: ApiNetwork) {
        self.chain = chain
        self.network = network
    }
}

public struct ApiDappConnectionRequest<ProtocolData: Codable & Sendable>: Codable, Sendable {
    public var protocolType: ApiDappProtocolType
    public var transport: ApiDappTransportType
    public var requestedChains: [ApiDappRequestedChain]
    public var permissions: ApiDappPermissions
    public var protocolData: ProtocolData

    public init(
        protocolType: ApiDappProtocolType,
        transport: ApiDappTransportType,
        requestedChains: [ApiDappRequestedChain],
        permissions: ApiDappPermissions,
        protocolData: ProtocolData
    ) {
        self.protocolType = protocolType
        self.transport = transport
        self.requestedChains = requestedChains
        self.permissions = permissions
        self.protocolData = protocolData
    }
}

public struct ApiDappProtocolError: Codable, Sendable {
    public var code: Int
    public var message: String
    public var displayError: ApiAnyDisplayError?

    public init(code: Int, message: String, displayError: ApiAnyDisplayError? = nil) {
        self.code = code
        self.message = message
        self.displayError = displayError
    }
}

public struct ApiDappSessionChain: Codable, Sendable {
    public var chain: ApiChain
    public var address: String
    public var network: ApiNetwork
    public var publicKey: String?

    public init(chain: ApiChain, address: String, network: ApiNetwork, publicKey: String? = nil) {
        self.chain = chain
        self.address = address
        self.network = network
        self.publicKey = publicKey
    }
}

public struct ApiDappSession<ProtocolData: Codable & Sendable>: Codable, Sendable {
    public var id: String?
    public var protocolType: ApiDappProtocolType?
    public var accountId: String?
    public var dapp: ApiDapp?
    public var chains: [ApiDappSessionChain]?
    public var connectedAt: Int?
    public var expiresAt: Int?
    public var protocolData: ProtocolData?

    public init(
        id: String? = nil,
        protocolType: ApiDappProtocolType? = nil,
        accountId: String? = nil,
        dapp: ApiDapp? = nil,
        chains: [ApiDappSessionChain]? = nil,
        connectedAt: Int? = nil,
        expiresAt: Int? = nil,
        protocolData: ProtocolData?
    ) {
        self.id = id
        self.protocolType = protocolType
        self.accountId = accountId
        self.dapp = dapp
        self.chains = chains
        self.connectedAt = connectedAt
        self.expiresAt = expiresAt
        self.protocolData = protocolData
    }
}

public struct ApiDappConnectionResult<ProtocolData: Codable & Sendable>: Codable, Sendable {
    public var success: Bool
    public var session: ApiDappSession<ProtocolData>?
    public var error: ApiDappProtocolError?

    public init(success: Bool, session: ApiDappSession<ProtocolData>? = nil, error: ApiDappProtocolError? = nil) {
        self.success = success
        self.session = session
        self.error = error
    }
}

public struct ApiDappMethodResult<ResultData: Codable & Sendable>: Codable, Sendable {
    public var success: Bool
    public var result: ResultData?
    public var error: ApiDappProtocolError?

    public init(success: Bool, result: ResultData? = nil, error: ApiDappProtocolError? = nil) {
        self.success = success
        self.result = result
        self.error = error
    }
}

public struct ApiDappDisconnectRequest: Codable, Sendable {
    public var requestId: String

    public init(requestId: String) {
        self.requestId = requestId
    }
}

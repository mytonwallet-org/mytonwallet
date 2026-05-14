import Foundation

public struct ApiDappEvmRpcProxyRequest: Codable, Sendable {
    public var chain: ApiChain
    public var method: String
    public var params: [AnyCodable]

    public init(chain: ApiChain, method: String, params: [AnyCodable]) {
        self.chain = chain
        self.method = method
        self.params = params
    }
}

extension Api {
    @MainActor static var _lastWalletConnectRequestId = 0
    @MainActor public static var walletConnectRequestId: Int {
        _lastWalletConnectRequestId += 1
        return _lastWalletConnectRequestId
    }

    public static func walletConnect_connect(request: ApiDappRequest, message: ApiDappConnectionRequest<AnyCodable>, requestId: Int) async throws -> ApiDappConnectionResult<AnyCodable> {
        try await bridge.callApi("walletConnect_connect", request, message, requestId, decoding: ApiDappConnectionResult<AnyCodable>.self)
    }

    public static func walletConnect_reconnect(request: ApiDappRequest, requestId: Int) async throws -> ApiDappConnectionResult<AnyCodable> {
        try await bridge.callApi("walletConnect_reconnect", request, requestId, decoding: ApiDappConnectionResult<AnyCodable>.self)
    }

    public static func walletConnect_disconnect(request: ApiDappRequest, message: ApiDappDisconnectRequest) async throws -> ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess> {
        try await bridge.callApi("walletConnect_disconnect", request, message, decoding: ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess>.self)
    }

    public static func walletConnect_sendTransaction(request: ApiDappRequest, message: ApiDappTransactionRequest<AnyCodable>) async throws -> ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess> {
        try await bridge.callApi("walletConnect_sendTransaction", request, message, decoding: ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess>.self)
    }

    public static func walletConnect_signData(request: ApiDappRequest, message: ApiDappSignDataRequest<AnyCodable>) async throws -> ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess> {
        try await bridge.callApi("walletConnect_signData", request, message, decoding: ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess>.self)
    }

    public static func walletConnect_proxyEvmRpc(request: ApiDappRequest, message: ApiDappEvmRpcProxyRequest) async throws -> ApiDappMethodResult<AnyCodable> {
        try await bridge.callApi("walletConnect_proxyEvmRpc", request, message, decoding: ApiDappMethodResult<AnyCodable>.self)
    }

    public static func walletConnect_handleDeepLink(_ url: String) async throws {
        _ = try await bridge.callApiOptional(
            "walletConnect_handleDeepLink",
            url,
            decodingOptional: String.self
        )
    }
}

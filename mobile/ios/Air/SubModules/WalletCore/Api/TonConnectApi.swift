//
//  Api+TC.swift
//  WalletCore
//
//  Created by Sina on 8/29/24.
//

import Foundation
import WalletContext

// see: src/api/tonConnect/index.ts

extension Api {
    
    // MARK: Incrementing id
    
    static var _lastTonConnectRequestId = 0
    public static var tonConnectRequestId: Int {
        _lastTonConnectRequestId += 1
        return _lastTonConnectRequestId
    }
    
    // MARK: Methods
    
    public static func tonConnect_connect(request: ApiDappRequest, message: ApiDappConnectionRequest<TonConnectConnectRequest>, requestId: Int? = nil) async throws -> ApiDappConnectionResult<TonConnectConnectEvent> {
        let id = requestId ?? self.tonConnectRequestId
        return try await bridge.callApi("tonConnect_connect", request, message, id, decoding: ApiDappConnectionResult<TonConnectConnectEvent>.self)
    }
    
    public static func tonConnect_reconnect(request: ApiDappRequest, requestId: Int? = nil) async throws -> ApiDappConnectionResult<TonConnectConnectEvent> {
        let id = requestId ?? self.tonConnectRequestId
        return try await bridge.callApi("tonConnect_reconnect", request, id, decoding: ApiDappConnectionResult<TonConnectConnectEvent>.self)
    }
    
    public static func tonConnect_disconnect(request: ApiDappRequest, message: ApiDappDisconnectRequest) async throws -> ApiDappMethodResult<ApiTonConnectDisconnectResult> {
        try await bridge.callApi("tonConnect_disconnect", request, message, decoding: ApiDappMethodResult<ApiTonConnectDisconnectResult>.self)
    }
    
    public static func tonConnect_sendTransaction(request: ApiDappRequest, message: ApiTonConnectSendTransactionRequest) async throws -> ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess> {
        try await bridge.callApi("tonConnect_sendTransaction", request, message, decoding: ApiDappMethodResult<ApiSendTransactionRpcResponseSuccess>.self)
    }
    
    public static func tonConnect_signData(request: ApiDappRequest, message: ApiTonConnectSignDataRequest) async throws -> ApiDappMethodResult<ApiTonConnectSignDataResponse> {
        try await bridge.callApi("tonConnect_signData", request, message, decoding: ApiDappMethodResult<ApiTonConnectSignDataResponse>.self)
    }
}

public struct ApiSendTransactionRpcResponseSuccess: Codable, Sendable {
    public let id: String
    public let result: String
}

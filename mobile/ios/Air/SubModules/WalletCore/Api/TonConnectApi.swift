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
    
    public static func tonConnect_connect(request: ApiDappRequest, message: [String: Any]) async throws -> Any? {
        let id = self.tonConnectRequestId
        return try await bridge.callApiRaw("tonConnect_connect", request, AnyEncodable(dict: message), id)
    }
    
    public static func tonConnect_reconnect(request: ApiDappRequest) async throws -> Any? {
        let id = self.tonConnectRequestId
        return try await bridge.callApiRaw("tonConnect_reconnect", request, id)
    }
    
    public static func tonConnect_disconnect(request: ApiDappRequest) async throws -> Any? {
        let id = self.tonConnectRequestId
        let message = AnyEncodable(dict: [
            "id": id,
            "method": "disconnect",
            "params": []
        ])
        return try await bridge.callApiRaw("tonConnect_disconnect", request, message)
    }
    
    public static func tonConnect_sendTransaction(request: ApiDappRequest, message: ApiSendTransactionRpcRequest) async throws -> ApiSendTransactionRpcResponseSuccess {
        let result = try await bridge.callApiRaw("tonConnect_sendTransaction", request, message)
        guard let result else { throw NilError() }
        let data = try JSONSerialization.data(withJSONObject: result)
        do {
            let value = try JSONDecoder().decode(ApiSendTransactionRpcResponseSuccess.self, from: data)
            return value
        } catch {
            let error = try JSONDecoder().decode(ApiSendTransactionRpcResponseError.self, from: data)
            throw error
        }
    }
    
    public static func tonConnect_signData(request: ApiDappRequest, params: [String]) async throws -> Any? {
        let id = self.tonConnectRequestId
        let message = AnyEncodable(dict: [
            "id": id,
            "method": "signData",
            "params": params,
        ])
        return try await bridge.callApiRaw("tonConnect_signData", request, message)
    }
}

// MARK: - Support types

public struct ApiSendTransactionRpcRequest: Hashable, Codable {
    let method: String
    let params: [String]
    let id: String
    
    public init(method: String, params: [String], id: String) {
        self.method = method
        self.params = params
        self.id = id
    }
}

public struct ApiSendTransactionRpcResponseSuccess: Decodable {
    public let id: String
    public let result: String
}

public struct ApiSendTransactionRpcResponseError: Error, Decodable {
    public struct ErrorInfo: Decodable {
        public var code: Int
        public var message: String
    }
    public var error: ErrorInfo
    public var id: String
}

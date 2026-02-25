//
//  Api+WalletData.swift
//  Wallet
//
//  Created by Sina on 3/28/24.
//

import Foundation
import WalletContext

extension Api {
    
    public static func fetchPrivateKey(accountId: String, chain: ApiChain, password: String) async throws -> String {
        try await bridge.callApi("fetchPrivateKey", accountId, chain, password, decoding: String.self)
    }

    public static func fetchMnemonic(accountId: String, password: String) async throws -> [String] {
        try await bridge.callApi("fetchMnemonic", accountId, password, decoding: [String].self)
    }
    
    public static func getMnemonicWordList() async throws -> [String] {
        try await bridge.callApi("getMnemonicWordList", decoding: [String].self)
    }
    
    /// - Important: Do not call this method directly, use **AuthSupport** instead
    internal static func verifyPassword(password: String) async throws -> Bool {
        try await bridge.callApi("verifyPassword", password, decoding: Bool.self)
    }
    
    public static func confirmDappRequest(promiseId: String, password: String?) async throws {
        try await bridge.callApiVoid("confirmDappRequest", promiseId, password)
    }
    
    public static func confirmDappRequestConnect(promiseId: String, data: ApiDappRequestConfirmation) async throws {
        try await bridge.callApiVoid("confirmDappRequestConnect", promiseId, data)
    }
    
    public static func confirmDappRequestSendTransaction(promiseId: String, data: [ApiSignedTransfer]) async throws {
        try await bridge.callApiVoid("confirmDappRequestSendTransaction", promiseId, data)
    }
    
    public static func confirmDappRequestSignData(promiseId: String, data: AnyEncodable) async throws {
        try await bridge.callApiVoid("confirmDappRequestSignData", promiseId, data)
    }
    
    public static func cancelDappRequest(promiseId: String, reason: String?) async throws {
        try await bridge.callApiVoid("cancelDappRequest", promiseId, reason)
    }

    public static func fetchAddress(accountId: String, chain: ApiChain) async throws -> String {
        try await bridge.callApi("fetchAddress", accountId, chain, decoding: String.self)
    }
    
    public static func getWalletBalance(chain: ApiChain, network: ApiNetwork, address: String) async throws -> BigInt {
        try await bridge.callApi("getWalletBalance", chain, network, address, decoding: BigInt.self)
    }
    
    public static func getAddressInfo(chain: ApiChain, network: ApiNetwork, address: String) async throws -> ApiGetAddressInfoResult {
        try await bridge.callApi("getAddressInfo", chain, network, address, decoding: ApiGetAddressInfoResult.self)
    }
}


// MARK: - Types

public struct ApiDappRequestConfirmation: Encodable {
    public var accountId: String
    /** Base64. Shall miss when no proof is required. Can be multiple for multichain. */
    public var proofSignatures: [String]?
    
    public init(accountId: String, proofSignatures: [String]?) {
        self.accountId = accountId
        self.proofSignatures = proofSignatures
    }
}

public struct ApiGetAddressInfoResult: Decodable {
    public var addressName: String?
    public var isScam: Bool?
    public var resolvedAddress: String?
    public var isToAddressNew: Bool?
    public var isBounceable: Bool?
    public var isMemoRequired: Bool?
    public var error: String?
}

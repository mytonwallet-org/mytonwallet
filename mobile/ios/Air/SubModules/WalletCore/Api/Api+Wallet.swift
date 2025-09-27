//
//  Api+WalletData.swift
//  Wallet
//
//  Created by Sina on 3/28/24.
//

import Foundation
import WalletContext

extension Api {
    
    public static func fetchPrivateKey(accountId: String, password: String) async throws -> String {
        try await bridge.callApi("fetchPrivateKey", accountId, password, decoding: String.self)
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
    
    public static func getAddressInfo(network: ApiNetwork, toAddress: String) async throws -> ApiGetAddressInfoResult {
        try await bridge.callApi("getAddressInfo", network, toAddress, decoding: ApiGetAddressInfoResult.self)
    }
}


// MARK: - Types

public struct ApiDappRequestConfirmation: Encodable {
    public var accountId: String
    /** Base64. Shall miss when no proof is required. */
    public var proofSignature: String?
    
    public init(accountId: String, proofSignature: String?) {
        self.accountId = accountId
        self.proofSignature = proofSignature
    }
}

public struct ContractInfo: Equatable, Hashable, Codable, Sendable {
    public var name: ContractName
    public var type: ContractType?
    public var hash: String
    public var isSwapAllowed: Bool?
};

public enum ContractName: String, Equatable, Hashable, Codable, Sendable {
        
    // from ApiTonWalletVersion
    case simpleR1 = "simpleR1"
    case simpleR2 = "simpleR2"
    case simpleR3 = "simpleR3"
    case v2R1 = "v2R1"
    case v2R2 = "v2R2"
    case v3R1 = "v3R1"
    case v3R2 = "v3R2"
    case v4R2 = "v4R2"
    case W5 = "W5"

    case v4R1 = "v4R1"
    case highloadV2 = "highloadV2"
    case multisig = "multisig"
    case multisigV2 = "multisigV2"
    case multisigNew = "multisigNew"
    case nominatorPool = "nominatorPool"
    case vesting = "vesting"
    case dedustPool = "dedustPool"
    case dedustVaultNative = "dedustVaultNative"
    case dedustVaultJetton = "dedustVaultJetton"
    case stonPtonWallet = "stonPtonWallet"
    case stonRouter = "stonRouter"
    case stonRouterV2_1 = "stonRouterV2_1"
    case stonPoolV2_1 = "stonPoolV2_1"
    case stonRouterV2_2 = "stonRouterV2_2"
    case stonPoolV2_2 = "stonPoolV2_2"
    case stonPtonWalletV2 = "stonPtonWalletV2"
}

public enum ContractType: String, Equatable, Hashable, Codable, Sendable {
    case wallet = "wallet"
    case staking = "staking"
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

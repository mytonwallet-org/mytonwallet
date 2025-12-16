//
//  Api+Auth.swift
//  WalletCore
//
//  Created by Sina on 3/28/24.
//

import Foundation
import WalletContext

extension Api {
    
    public static func generateMnemonic(isBip39: Bool = true) async throws -> [String] {
        try await bridge.callApi("generateMnemonic", isBip39, decoding: [String].self)
    }
    
    public static func validateMnemonic(mnemonic: [String]) async throws -> Bool {
        try await bridge.callApi("validateMnemonic", mnemonic, decoding: Bool.self)
    }
    
    /// - Important: Do not call this method directly, use **AccountStore** instead
    internal static func importMnemonic(networks: [ApiNetwork], mnemonic: [String], password: String, version: ApiTonWalletVersion?) async throws -> [ApiAddWalletResult] {
        try await bridge.callApi("importMnemonic", networks, mnemonic, password, version, decoding: [ApiAddWalletResult].self)
    }
    
    internal static func importPrivateKey(chain: ApiChain, networks: [ApiNetwork], privateKey: String, password: String) async throws -> [ApiAddWalletResult] {
        try await bridge.callApi("importPrivateKey", chain, networks, privateKey, password, decoding: [ApiAddWalletResult].self)
    }

    public static func addressFromPublicKey(publicKey: [UInt8], network: ApiNetwork, version: ApiTonWalletVersion?) async throws -> ApiTonWallet {
        try await bridge.callApi("addressFromPublicKey", publicKey, network, version, decoding: ApiTonWallet.self)
    }
    
    /// - Important: Do not call this method directly, use **AccountStore** instead
    internal static func importLedgerAccount(network: ApiNetwork, accountInfo: ApiLedgerAccountInfo) async throws -> ApiAddWalletResult {
        try await bridge.callApi("importLedgerAccount", network, accountInfo, decoding: ApiAddWalletResult.self)
    }

    public static func getLedgerWallets(chain: ApiChain, network: ApiNetwork, startWalletIndex: Int, count: Int) async throws -> [ApiLedgerWalletInfo] {
        try await bridge.callApi("getLedgerWallets", chain, network, startWalletIndex, count, decoding: [ApiLedgerWalletInfo].self)
    }
    
    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func resetAccounts() async throws {
        try await bridge.callApiVoid("resetAccounts")
    }
    
    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func removeAccount(accountId: String, nextAccountId: String, newestActivityTimestamps: ApiActivityTimestamps?) async throws {
        try await bridge.callApiVoid("removeAccount", accountId, nextAccountId, newestActivityTimestamps)
    }

    /// - Important: updates **keychain credentials**
    public static func changePassword(oldPassword: String, newPassword: String) async throws {
        try await bridge.callApiVoid("changePassword", oldPassword, newPassword)
        // TODO: remove this logic from API
        KeychainHelper.save(biometricPasscode: newPassword)
    }

    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func importViewAccount(network: ApiNetwork, addressByChain: ApiImportAddressByChain, isTemporary: Bool?) async throws -> ApiImportViewAccountResult {
        try await bridge.callApi("importViewAccount", network, addressByChain, isTemporary, decoding: ApiImportViewAccountResult.self)
    }
    
    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func importNewWalletVersion(accountId: String, version: ApiTonWalletVersion) async throws -> ApiImportNewWalletVersionResult {
        try await bridge.callApi("importNewWalletVersion", accountId, version, decoding: ApiImportNewWalletVersionResult.self)
    }
    
}


// MARK: - Types

public struct ApiAddWalletResult: Decodable, Sendable {
    public var accountId: String
    public var byChain: [String: AccountChain]
}

public typealias ApiImportAddressByChain = [String: String]

public struct ApiImportViewAccountResult: Decodable, Sendable {
    public var accountId: String
    public var title: String?
    public var byChain: [String: AccountChain]
}

public struct ApiImportNewWalletVersionResult: Decodable, Sendable {
    public var isNew: Bool
    public var accountId: String
    public var address: String?
}

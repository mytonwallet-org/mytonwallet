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
    
    /// - Important: Do not call this method directly, use **AccountStore** instead
    internal static func createWallet(network: ApiNetwork, mnemonic: [String], password: String, version: ApiTonWalletVersion?) async throws -> ApiAddWalletResult {
        try await bridge.callApi("createWallet", network, mnemonic, password, version, decoding: ApiAddWalletResult.self)
    }
    
    public static func validateMnemonic(mnemonic: [String]) async throws -> Bool {
        try await bridge.callApi("validateMnemonic", mnemonic, decoding: Bool.self)
    }
    
    /// - Important: Do not call this method directly, use **AccountStore** instead
    internal static func importMnemonic(network: ApiNetwork, mnemonic: [String], password: String, version: ApiTonWalletVersion?) async throws -> ApiAddWalletResult {
        try await bridge.callApi("importMnemonic", network, mnemonic, password, version, decoding: ApiAddWalletResult.self)
    }
    
    public static func addressFromPublicKey(publicKey: [UInt8], network: ApiNetwork, version: ApiTonWalletVersion?) async throws -> ApiTonWallet {
        try await bridge.callApi("addressFromPublicKey", publicKey, network, version, decoding: ApiTonWallet.self)
    }
    
    /// - Important: Do not call this method directly, use **AccountStore** instead
    internal static func importLedgerWallet(network: ApiNetwork, walletInfo: LedgerWalletInfo) async throws -> ApiImportLedgerWalletResult {
        try await bridge.callApi("importLedgerWallet", network, walletInfo, decoding: ApiImportLedgerWalletResult.self)
    }
    
    /// - Important: updates **keychain credentials**
    public static func changePassword(oldPassword: String, newPassword: String) async throws {
        try await bridge.callApiVoid("changePassword", oldPassword, newPassword)
        // TODO: remove this logic from API
        KeychainHelper.save(biometricPasscode: newPassword)
    }

    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func importViewAccount(network: ApiNetwork, addressByChain: ApiImportAddressByChain) async throws -> ApiImportViewAccountResult {
        try await bridge.callApi("importViewAccount", network, addressByChain, decoding: ApiImportViewAccountResult.self)
    }
    
    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func importNewWalletVersion(accountId: String, version: ApiTonWalletVersion) async throws -> ApiImportNewWalletVersionResult {
        try await bridge.callApi("importNewWalletVersion", accountId, version, decoding: ApiImportNewWalletVersionResult.self)
    }
    
    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func resetAccounts() async throws {
        try await bridge.callApiVoid("resetAccounts")
    }
    
    /// - Important: Do not call this methods directly, use **AccountStore** instead
    internal static func removeAccount(accountId: String, nextAccountId: String) async throws {
        try await bridge.callApiVoid("removeAccount", accountId, nextAccountId)
    }
}


// MARK: - Types

public struct ApiAddWalletResult: Decodable, Sendable {
    public var accountId: String
    public var addressByChain: [String: String]
    
    public var tonAddress: String? { addressByChain[ApiChain.ton.rawValue] }
    public var tronAddress: String? { addressByChain[ApiChain.tron.rawValue] }
}

public struct ApiImportLedgerWalletResult: Decodable, Sendable {
    public var accountId: String
    public var address: String
    public var walletInfo: LedgerWalletInfo
}

public typealias ApiImportAddressByChain = [String: String]

public struct ApiImportViewAccountResult: Decodable, Sendable {
    public var accountId: String
    public var title: String?
    public var resolvedAddresses: ApiImportAddressByChain
}

public struct ApiImportNewWalletVersionResult: Decodable, Sendable {
    public var accountId: String
    public var address: String
    public var ledger: MAccount.Ledger?
}

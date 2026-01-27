//
//  Api+Domains.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

import Foundation
import WalletContext

extension Api {
    
    public static func checkDnsRenewalDraft(accountId: String, nfts: [ApiNft]) async throws -> ApiDnsRenewalDraft {
        try await bridge.callApi("checkDnsRenewalDraft", accountId, nfts, decoding: ApiDnsRenewalDraft.self)
    }
    
    public static func submitDnsRenewal(accountId: String, password: String?, nfts: [ApiNft], realFee: BigInt?) async throws -> Any? {
        try await bridge.callApiRaw("submitDnsRenewal", accountId, password, nfts, realFee)
    }
    
    public static func checkDnsChangeWalletDraft(accountId: String, nft: ApiNft, address: String) async throws -> ApiDnsChangeWalletDraft {
        try await bridge.callApi("checkDnsChangeWalletDraft", accountId, nft, address, decoding: ApiDnsChangeWalletDraft.self)
    }
    
    public static func submitDnsChangeWallet(accountId: String, password: String?, nft: ApiNft, address: String, realFee: BigInt?) async throws -> ApiDnsChangeWalletResult {
        try await bridge.callApi("submitDnsChangeWallet", accountId, password, nft, address, realFee, decoding: ApiDnsChangeWalletResult.self)
    }
}

public struct ApiDnsRenewalDraft: Decodable {
    public let realFee: BigInt
}

public struct ApiDnsChangeWalletDraft: Decodable {
    public let realFee: BigInt
}

public struct ApiDnsChangeWalletResult: Decodable {
    public let activityId: String
}

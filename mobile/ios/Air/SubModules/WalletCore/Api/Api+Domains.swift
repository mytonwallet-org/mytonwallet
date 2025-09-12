//
//  Api+Domains.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

import Foundation
import WalletContext

extension Api {
    
    public static func checkDnsRenewalDraft(accountId: String, nfts: [ApiNft]) async throws -> Any? {
        try await bridge.callApiRaw("checkDnsRenewalDraft", accountId, nfts)
    }
    
    public static func submitDnsRenewal(accountId: String, password: String?, nfts: [ApiNft], realFee: BigInt?) async throws -> Any? {
        try await bridge.callApiRaw("submitDnsRenewal", accountId, password, nfts, realFee)
    }
    
    public static func checkDnsChangeWalletDraft(accountId: String, nft: ApiNft, address: String) async throws -> Any? {
        try await bridge.callApiRaw("checkDnsChangeWalletDraft", accountId, nft, address)
    }
    
    public static func submitDnsChangeWallet(accountId: String, password: String?, nft: ApiNft, address: String, realFee: BigInt?) async throws -> Any? {
        try await bridge.callApiRaw("submitDnsChangeWallet", accountId, password, nft, address, realFee)
    }
}


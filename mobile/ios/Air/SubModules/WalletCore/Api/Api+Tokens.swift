//
//  Api+Tokens.swift
//  WalletCore
//
//  Created by Sina on 3/28/24.
//

import Foundation
import WalletContext

extension Api {
    public static func fetchToken(accountId: String, chain: ApiChain, tokenAddress: String) async throws -> ApiToken {
        try await bridge.callApi("fetchToken", accountId, chain, tokenAddress, decoding: ApiToken.self)
    }

    public static func importToken(accountId: String, chain: ApiChain, tokenAddress: String) async throws {
        try await bridge.callApiVoid("importToken", accountId, chain, tokenAddress)
    }

    public static func buildTokenSlug(chain: ApiChain, tokenAddress: String) async throws -> String {
        try await bridge.callApi("buildTokenSlug", chain, tokenAddress, decoding: String.self)
    }
}

//
//  Api+Swap.swift
//  WalletCore
//
//  Created by Sina on 5/11/24.
//

import Foundation
import WalletContext


extension Api {

    public static func swapBuildTransfer(accountId: String, password: String, request: ApiSwapBuildRequest) async throws -> ApiSwapBuildResponse {
        try await bridge.callApi("swapBuildTransfer", accountId, password, request, decoding: ApiSwapBuildResponse.self)
    }
    
    public static func swapSubmit(accountId: String, password: String, transfers: [ApiSwapTransfer], historyItem: ApiSwapHistoryItem, isGasless: Bool?) async throws -> ApiSwapSubmitResult {
        try await bridge.callApi("swapSubmit", accountId, password, transfers, historyItem, isGasless, decoding: ApiSwapSubmitResult.self)
    }
    
    public static func swapEstimate(accountId: String, request: ApiSwapEstimateRequest) async throws -> ApiSwapEstimateResponse {
        try await bridge.callApi("swapEstimate", accountId, request, decoding: ApiSwapEstimateResponse.self)
    }
    
    /// - Important: call through TokenStore
    internal static func swapGetAssets() async throws -> [ApiToken] {
        return try await bridge.callApi("swapGetAssets", decoding: [ApiToken].self)
    }

    public static func swapGetPairs(symbolOrMinter: String) async throws -> [MPair] {
        if let pairs = TokenStore.swapPairs[symbolOrMinter] {
            return pairs
        }
        let pairs = try await bridge.callApi("swapGetPairs", symbolOrMinter == "toncoin" ? "TON" : symbolOrMinter, decoding: [MPair].self)
        TokenStore.swapPairs[symbolOrMinter] = pairs
        return pairs
    }
    
    public static func swapCexEstimate(swapEstimateOptions: ApiSwapCexEstimateOptions) async throws -> ApiSwapCexEstimateResponse? {
        return try await bridge.callApi("swapCexEstimate", swapEstimateOptions, decoding: ApiSwapCexEstimateResponse.self)
    }
    
    public static func swapCexValidateAddress(params: ApiSwapCexValidateAddressParams) async throws -> ApiSwapCexValidateAddressResult {
        try await bridge.callApi("swapCexValidateAddress", params, decoding: ApiSwapCexValidateAddressResult.self)
    }

    public static func swapCexCreateTransaction(accountId: String, password: String, params: ApiSwapCexCreateTransactionParams) async throws -> ApiSwapCexCreateTransactionResult {
        try await bridge.callApi("swapCexCreateTransaction", accountId, password, params, decoding: ApiSwapCexCreateTransactionResult.self)
    }

    public static func swapCexSubmit(chain: ApiChain, options: ApiSubmitTransferOptions, swapId: String) async throws -> ApiSubmitTransferResult {
        try await bridge.callApi("swapCexSubmit", chain, options, swapId, decoding: ApiSubmitTransferResult.self)
    }
}

// MARK: Types

public struct ApiSwapBuildResponse: Codable {
    public let id: String
    public var transfers: [ApiSwapTransfer]
    public let fee: BigInt?
}

public struct ApiSwapSubmitResult: Codable {
    public let paymentLink: String?
}

public struct ApiSwapCexValidateAddressParams: Encodable {
    public var slug: String
    public var address: String

    public init(slug: String, address: String) {
        self.slug = slug
        self.address = address
    }
}

public struct ApiSwapCexValidateAddressResult: Decodable {
    public var result: Bool
    public var message: String?
}

public struct ApiSwapCexCreateTransactionResult: Decodable {
    public var swap: ApiSwapHistoryItem
    public var activity: ApiActivity
}

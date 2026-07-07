//
//  Api+Swap.swift
//  WalletCore
//
//  Created by Sina on 5/11/24.
//

import Foundation
import WalletContext
import WalletCoreTypes

private let apiSwapLog = Log("Api+Swap")

extension Api {

    public static func swapBuildTransfer(accountId: String, password: String, request: ApiSwapBuildRequest) async throws -> ApiSwapBuildResponse {
        try await bridge.callApi("swapBuildTransfer", accountId, password, request, decoding: ApiSwapBuildResponse.self)
    }
    
    public static func swapSubmit(chain: ApiChain, accountId: String, password: String, transfers: [ApiSwapTransfer]?, historyItem: ApiSwapHistoryItem, isGasless: Bool?, transaction: String?) async throws -> ApiSwapSubmitResult {
        try await bridge.callApi("swapSubmit", chain, accountId, password, transfers, historyItem, isGasless, transaction, decoding: ApiSwapSubmitResult.self)
    }
    
    public static func swapEstimate(accountId: String, request: ApiSwapEstimateRequest) async throws -> ApiSwapEstimateResponse {
        let response = try await bridge.callApi("swapEstimate", accountId, request, decoding: ApiSwapEstimateRouteResponse.self)
        guard case .dex(let estimate) = response else {
            throw SdkError.unexpected(message: "Unexpected CEX estimate response", context: response)
        }
        return estimate
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
    
    public static func swapCexEstimate(accountId: String, swapEstimateOptions: ApiSwapCexEstimateOptions) async throws -> ApiSwapCexEstimateResponse? {
        let request = ApiSwapEstimateRequest(
            from: swapEstimateOptions.from,
            to: swapEstimateOptions.to,
            slippage: nil,
            fromAmount: swapEstimateOptions.fromAmount,
            toAmount: nil,
            fromAddress: swapEstimateOptions.fromAddress,
            toAddress: swapEstimateOptions.toAddress,
            cexLabel: swapEstimateOptions.cexLabel,
            shouldTryDiesel: nil,
            swapVersion: nil,
            toncoinBalance: nil,
            walletVersion: nil,
            isFromAmountMax: swapEstimateOptions.isFromAmountMax
        )
        let response = try await bridge.callApi("swapEstimate", accountId, request, decoding: ApiSwapEstimateRouteResponse.self)
        guard case .cex(let estimate) = response else {
            throw SdkError.unexpected(message: "Unexpected DEX estimate response", context: response)
        }
        return estimate
    }
    
    public static func swapCexValidateAddress(params: ApiSwapCexValidateAddressParams) async throws -> ApiSwapCexValidateAddressResult {
        try await bridge.callApi("swapCexValidateAddress", params, decoding: ApiSwapCexValidateAddressResult.self)
    }

    public static func swapCexCreateTransaction(accountId: String, password: String, params: ApiSwapCexCreateTransactionParams) async throws -> ApiSwapCexCreateTransactionResult {
        try await bridge.callApi("swapCexCreateTransaction", accountId, password, params, decoding: ApiSwapCexCreateTransactionResult.self)
    }

    public static func swapCexSubmit(chain: ApiChain, options: ApiSubmitTransferOptions, swapId: String) async throws -> ApiSwapSubmitResult {
        try await bridge.callApi("swapCexSubmit", chain, options, swapId, decoding: ApiSwapSubmitResult.self)
    }

    public static func confirmSwapMfaRequest(accountId: String, swapId: String, txHash: String) async throws {
        do {
            try await bridge.callApiVoid("confirmSwapMfaRequest", accountId, swapId, txHash)
        } catch {
            apiSwapLog.error("confirmSwapMfaRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func fetchSwaps(accountId: String, items: [ApiFetchSwapItem]) async throws -> ApiFetchSwapsResult {
        try await bridge.callApi("fetchSwaps", accountId, items, decoding: ApiFetchSwapsResult.self)
    }
}

// MARK: Types

public struct ApiSwapBuildResponse: Codable, Sendable {
    public let id: String?
    public var transfers: [ApiSwapTransfer]?
    public let fee: BigInt?
    public let chain: ApiChain?
    public let transaction: String?
    public let error: ApiAnyDisplayError?
}

public struct ApiSwapSubmitResult: Codable, Sendable {
    public let activityId: String?
    public let swapId: String?
    public let mfaRequestHash: String?
    public let error: String?
    public let paymentLink: String?
}

extension ApiSwapSubmitResult: MfaProtectedActionResult {
    public var protectedActionError: String? { error }
}

public struct ApiSwapCexValidateAddressParams: Encodable, Sendable {
    public var slug: String
    public var address: String
    public var cexLabel: ApiSwapCexLabel?

    public init(slug: String, address: String, cexLabel: ApiSwapCexLabel? = nil) {
        self.slug = slug
        self.address = address
        self.cexLabel = cexLabel
    }
}

public struct ApiSwapCexValidateAddressResult: Decodable, Sendable {
    public var result: Bool
    public var message: String?
}

public struct ApiSwapCexCreateTransactionResult: Decodable, Sendable {
    public var swap: ApiSwapHistoryItem
    public var activity: ApiActivity
}

public struct ApiFetchSwapsResult: Decodable, Sendable {
    public var nonExistentIds: [String]
    public var swaps: [ApiSwapActivity]
}

public struct ApiFetchSwapItem: Encodable, Hashable, Sendable {
    public var id: String
    public var chain: ApiChain?

    public init(id: String, chain: ApiChain?) {
        self.id = id
        self.chain = chain
    }
}

public enum ApiSwapEstimateRouteResponse: Decodable, Sendable {
    case dex(ApiSwapEstimateResponse)
    case cex(ApiSwapCexEstimateResponse)

    private enum CodingKeys: String, CodingKey {
        case route
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let route = try container.decodeIfPresent(String.self, forKey: .route)
        switch route {
        case "dex":
            self = .dex(try ApiSwapEstimateResponse(from: decoder))
        case "cex":
            self = .cex(try ApiSwapCexEstimateResponse(from: decoder))
        default:
            if let dex = try? ApiSwapEstimateResponse(from: decoder) {
                self = .dex(dex)
            } else {
                self = .cex(try ApiSwapCexEstimateResponse(from: decoder))
            }
        }
    }
}

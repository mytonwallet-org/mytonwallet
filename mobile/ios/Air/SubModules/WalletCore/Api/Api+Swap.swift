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

    public static func resolveSwapDefaults(_ request: ApiSwapDefaultsRequest) async throws -> ApiSwapDefaults {
        try await bridge.callApi("resolveSwapDefaults", request, decoding: ApiSwapDefaults.self)
    }

    public static func swapBuildTransfer(accountId: String, enclaveToken: EnclaveToken, request: ApiSwapBuildRequest) async throws -> ApiSwapBuildResponse {
        return try await bridge.callApi("swapBuildTransfer", accountId, enclaveToken, request, decoding: ApiSwapBuildResponse.self)
    }
    
    public static func swapSubmit(chain: ApiChain, accountId: String, enclaveToken: EnclaveToken, transfers: [ApiSwapTransfer]?, historyItem: ApiSwapHistoryItem, isGasless: Bool?, transaction: String?) async throws -> ApiSwapSubmitResult {
        try await bridge.callApi("swapSubmit", chain, accountId, enclaveToken, transfers, historyItem, isGasless, transaction, decoding: ApiSwapSubmitResult.self)
    }
    
    public static func swapEstimate(accountId: String, request: ApiSwapEstimateRequest) async throws -> ApiSwapEstimateResponse {
        try await bridge.callApi("swapEstimate", accountId, request, decoding: ApiSwapEstimateResponse.self)
    }
    
    public static func swapGetPairs(symbolOrMinter: String) async throws -> [MPair] {
        if let pairs = TokenStore.swapPairs[symbolOrMinter] {
            return pairs
        }
        let pairs = try await bridge.callApi("swapGetPairs", symbolOrMinter == "toncoin" ? "TON" : symbolOrMinter, decoding: [MPair].self)
        TokenStore.swapPairs[symbolOrMinter] = pairs
        return pairs
    }
    
    public static func swapCexValidateAddress(params: ApiSwapCexValidateAddressParams) async throws -> ApiSwapCexValidateAddressResult {
        try await bridge.callApi("swapCexValidateAddress", params, decoding: ApiSwapCexValidateAddressResult.self)
    }

    public static func swapCexCreateTransaction(accountId: String, enclaveToken: EnclaveToken, request: ApiSwapBuildRequest) async throws -> ApiSwapCexCreateTransactionResult {
        return try await bridge.callApi("swapCexCreateTransaction", accountId, enclaveToken, request, decoding: ApiSwapCexCreateTransactionResult.self)
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

    public static func fetchSwaps(
        accountId: String,
        items: [ApiFetchSwapItem],
        existingActivities: [ApiActivity] = []
    ) async throws -> ApiFetchSwapsResult {
        try await bridge.callApi(
            "fetchSwaps",
            accountId,
            items,
            existingActivities,
            decoding: ApiFetchSwapsResult.self
        )
    }
}

// MARK: Types

public struct ApiSwapDefaultsRequest: Encodable, Equatable, Sendable {
    public var tokenIn: ApiToken?
    public var tokenOut: ApiToken?
    public var accountChains: [ApiChain]
    public var network: ApiNetwork
    public var balancesUsdBySlug: [String: Double]

    @MainActor
    public init(accountContext: AccountContext, tokenIn: ApiToken?, tokenOut: ApiToken?) {
        self.tokenIn = tokenIn
        self.tokenOut = tokenOut
        let displayedChains = accountContext.displayedChains.map(\.0)
        accountChains = displayedChains + accountContext.orderedChains.map(\.0).filter { !displayedChains.contains($0) }
        network = accountContext.account.network
        balancesUsdBySlug = Dictionary(uniqueKeysWithValues:
            (accountContext.walletTokensData?.allTokenBalances ?? [])
                .filter { !$0.isStaking }
                .map { ($0.tokenSlug, $0.toUsd ?? 0) }
        )
    }
}

public struct ApiSwapDefaults: Decodable, Sendable {
    public let tokenIn: ApiToken?
    public let tokenOut: ApiToken?

    public init(tokenIn: ApiToken?, tokenOut: ApiToken?) {
        self.tokenIn = tokenIn
        self.tokenOut = tokenOut
    }
}

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
    public var patch: ApiActivitiesPatch?
}

public struct ApiFetchSwapItem: Encodable, Hashable, Sendable {
    public var id: String
    public var chain: ApiChain?

    public init(id: String, chain: ApiChain?) {
        self.id = id
        self.chain = chain
    }
}

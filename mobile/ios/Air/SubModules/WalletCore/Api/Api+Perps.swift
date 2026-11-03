import Foundation
import WalletContext

public struct ApiPerpsTradingAvailability: Codable, Sendable, Equatable {
    public var isAvailable: Bool
    public var reason: String?

    public init(isAvailable: Bool, reason: String? = nil) {
        self.isAvailable = isAvailable
        self.reason = reason
    }
}

public struct ApiPerpsAsset: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var symbol: String
    public var chain: String
    public var provider: String
    public var dex: String
    public var image: String?
    public var displayName: String?
    public var description: String?
    public var label: String?
    public var keywords: [String]?
    public var tintColor: String?
    public var sparkline: [Double]?
    public var szDecimals: Int
    public var maxLeverage: Int
    public var onlyIsolated: Bool?
    public var isDelisted: Bool?
    public var tradingAvailability: ApiPerpsTradingAvailability?
    public var marginMode: String?
    public var context: Context

    public struct Context: Codable, Sendable, Equatable {
        public var markPx: String
        public var prevDayPx: String
        public var funding: String?
        public var fundingPercent: String?
        public var fundingIntervalHours: Int?
        public var percentChange24h: Double?
        public var openInterest: String?
        public var openInterestUsd: String?
        public var dayNtlVlm: String?
    }
}

public struct ApiPerpsPosition: Codable, Sendable, Equatable {
    public var coin: String
    public var entryPx: String?
    public var liquidationPx: String?
    public var leverage: Leverage
    public var marginUsed: String
    public var positionValue: String
    public var returnOnEquity: String
    public var szi: String
    public var unrealizedPnl: String

    public struct Leverage: Codable, Sendable, Equatable {
        public var type: String
        public var value: Int
        public var rawUsd: String?
    }
}

public struct ApiPerpsAccountPosition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var assetId: String
    public var dex: String
    public var side: String
    public var size: String?
    public var collateral: String
    public var equity: String
    public var isNearLiquidation: Bool?
    public var returnOnEquity: String?
    public var funding: String?
    public var raw: ApiPerpsPosition
}

public struct ApiPerpsSnapshot: Codable, Sendable, Equatable {
    public var tradingAvailability: ApiPerpsTradingAvailability?
    public var abstractionMode: String?
    public var spotUsdcTotal: String?
    public var spotUsdcAvailable: String?
    public var withdrawable: String?
    public var assets: [ApiPerpsAsset]
    public var marketSections: [ApiMarketSection<ApiPerpsAsset>]?
    public var assetsFetchedAt: Int64?
    public var limits: Limits?
    public struct Limits: Codable, Sendable, Equatable {
        public var minOpenDepositUsdc: String
        public var minIncreaseDepositUsdc: String
        public var minPositionMarginUsdc: String?
    }
    public var positions: [ApiPerpsAccountPosition]
    public var totalEquity: String
    public var totalPnl: String
    public var totalReturnOnEquity: String?
    public var timestamp: Int64
    public var unavailableDexs: [String]
}

public struct ApiPerpsMarketSnapshot: Codable, Sendable, Equatable {
    public var assets: [ApiPerpsAsset]
    public var marketSections: [ApiMarketSection<ApiPerpsAsset>]?
    public var limits: ApiPerpsSnapshot.Limits?
    public var assetsFetchedAt: Int64
}

public struct ApiPerpsDraft: Encodable, Sendable {
    public var assetId: String
    public var side: String
    public var amount: String
    public var unit: String
    public var leverage: Int
    public var editing: Bool?
    public var close: Bool?
    public var fraction: Int?
    public var reset: Bool?
    public var convertFrom: String?
    public var leverageOnly: Bool?

    public init(assetId: String, side: String, amount: String, unit: String = "currency", leverage: Int,
                editing: Bool = false, close: Bool = false, fraction: Int? = nil, reset: Bool = false,
                convertFrom: String? = nil, leverageOnly: Bool = false) {
        self.assetId = assetId; self.side = side; self.amount = amount; self.unit = unit; self.leverage = leverage
        self.editing = editing; self.close = close; self.fraction = fraction; self.reset = reset; self.convertFrom = convertFrom
        self.leverageOnly = leverageOnly
    }
}

public struct ApiPerpsFees: Codable, Sendable, Equatable {
    public var exchange: String?
    public var service: String?
    public var trading: String
    public var bridge: String?
    public var total: String
}

public struct ApiPerpsLeverageEstimate: Codable, Sendable, Equatable {
    public var leverage: Int
    public var liquidationPrice: String?
}

public struct ApiPerpsFundingRequirements: Codable, Sendable, Equatable {
    public var requiredUsdc: String
    public var requiredEth: String
    public var requiredEthUsd: String
    public var usdcBalance: String
    public var availableCollateral: String?
    public var ethBalance: String
    public var needsUsdc: Bool
    public var needsEth: Bool
}

public struct ApiPerpsReceiptDetails: Codable, Sendable, Equatable {
    public var receiveAmount: String?
    public var fees: ApiPerpsFees?
    public var remainingCollateral: String?
}

public struct ApiPerpsReceiptInput: Encodable, Sendable {
    public var quote: ApiPerpsQuote
    public var operation: ApiPerpsOperation
    public var position: ApiPerpsAccountPosition?
    public var fill: ApiPerpsFill?
}

public struct ApiPerpsQuote: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var accountId: String
    public var assetId: String
    public var kind: String
    public var side: String
    public var leverage: Int
    public var inputAmount: String
    public var previousLeverage: Int?
    public var currentInputAmount: String?
    public var collateral: String
    public var previousCollateral: String?
    public var estimatedCollateral: String?
    public var estimatedRemainingCollateral: String?
    public var estimatedFees: ApiPerpsFees?
    public var leverageEstimates: [ApiPerpsLeverageEstimate]?
    public var fundingRequirements: ApiPerpsFundingRequirements?
    public var previousFunding: String?
    public var equity: String?
    public var profitLoss: String?
    public var returnOnEquity: String?
    public var size: String
    public var previousSize: String?
    public var notional: String
    public var previousNotional: String?
    public var markPrice: String
    public var entryPrice: String?
    public var liquidationPrice: String?
    public var estimatedLiquidationPrice: String?
    public var paymentAmount: String
    public var receiveStatus: String?
    public var receiveAmount: String?
    public var bridgeFee: String
    public var expiresAt: Int64
    public var createdAt: Int64
}

public struct ApiPerpsOperation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var accountId: String
    public var assetId: String
    public var kind: String
    public var state: String
    public var stage: String
    public var createdAt: Int64
    public var depositTxHash: String?
    public var acknowledgedAt: Int64?
    public var orderId: Int64?
    public var orderStatus: String?
    public var filledSize: String?
    public var positionSize: String?
    public var averagePrice: String?
    public var withdrawalAmount: String?
    public var withdrawalRequestedAmount: String?
    public var error: String?
    /// Native receipt context. Keep the reviewed values when SDK progress replaces this record.
    public var reviewedQuote: ApiPerpsQuote?
    /// Captured once from an SDK snapshot correlated with this operation's latest fill.
    public var receiptPosition: ApiPerpsAccountPosition?
    public var receiptDetails: ApiPerpsReceiptDetails?

    public var needsReconciliation: Bool { !["completed", "failed"].contains(state) }
    public var blocksTrading: Bool { needsReconciliation && !(state == "unknown" && acknowledgedAt != nil) }

    public init(id: String, accountId: String, assetId: String, kind: String, createdAt: Int64) {
        self.id = id; self.accountId = accountId; self.assetId = assetId; self.kind = kind
        self.createdAt = createdAt; self.state = "running"; self.stage = "preparing"
    }
}

extension ApiUpdate {
    public struct UpdatePerpsAssets: Decodable, Sendable {
        public let langCode: String?
        public let fetchedAt: Int64
    }

    public struct PerpsOperationUpdated: Decodable, Sendable {
        public let operation: ApiPerpsOperation
    }
}

public struct ApiPerpsFill: Codable, Sendable, Equatable, Identifiable {
    public var activityId: String?
    public var assetId: String?
    public var leverage: Int?
    public var collateralBefore: String?
    public var collateralAfter: String?
    /// USDC added on an increase or withdrawn on a reduce. Absent without a matching bridge row.
    public var transferredAmount: String?
    public var bridgeFee: String?
    public var receiptFees: ApiPerpsFees?
    public var deposit: Deposit?
    public var withdrawal: Withdrawal?
    public struct Deposit: Codable, Sendable, Equatable {
        public var grossAmount: String
        public var bridgeFee: String
        public var creditedAmount: String
        public var txHash: String?
    }
    public struct Withdrawal: Codable, Sendable, Equatable {
        public var amount: String
        public var bridgeFee: String
        public var receivedAmount: String
        public var txHash: String?
        public var status: String
    }
    public var coin: String
    public var tid: Int64?
    public var oid: Int64?
    public var time: Int64
    public var px: String?
    public var sz: String?
    public var side: String?
    public var dir: String?
    public var startPosition: String?
    public var closedPnl: String?
    public var fee: String?
    public var feeToken: String
    public var builderFee: String?
    public var hash: String?
    public var eventKind: String?
    public var positionSide: String?
    public var netPnl: String?
    public var notional: String?
    public var previousSize: String?
    public var positionSize: String?
    public var previousNotional: String?
    public var positionNotional: String?
    public var endPosition: String?
    public var entryPrice: String?
    public var positionOpenedAt: Int64?
    public var fillIds: [Int64]?
    public var liquidation: Liquidation?
    public var id: String { activityId ?? "\(coin)/\(time)/\(tid ?? 0)" }
    public struct Liquidation: Codable, Sendable, Equatable {
        public var liquidatedUser: String?
        public var markPx: String
        public var method: String
    }
}

public struct ApiPerpsCashFlow: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case funding, deposit, withdrawal, transfer }
    public enum Direction: String, Codable, Sendable { case incoming, outgoing, `internal` }
    public struct Fee: Codable, Sendable, Equatable {
        public var amount: String
        public var token: String
    }
    public var id: String
    public var kind: Kind
    public var direction: Direction
    public var time: Int64
    public var amount: String
    public var token: String
    public var coin: String?
    public var assetId: String?
    public var positionSide: String?
    public var fundingRate: String?
    public var positionSize: String?
    public var sourceDex: String?
    public var destinationDex: String?
    public var sourceAddress: String?
    public var destinationAddress: String?
    public var fees: [Fee]
    public var hash: String?
}

public struct ApiPerpsActivityHistory: Codable, Sendable, Equatable {
    public var fills: [ApiPerpsFill]
    public var cashFlows: [ApiPerpsCashFlow]
    public var nextCursor: String?
    public var hasActivity: Bool?
    public init(fills: [ApiPerpsFill], cashFlows: [ApiPerpsCashFlow], nextCursor: String? = nil, hasActivity: Bool? = nil) {
        self.nextCursor = nextCursor
        self.hasActivity = hasActivity
        self.fills = fills
        self.cashFlows = cashFlows
    }
}

public struct ApiPerpsAssetDetail: Codable, Sendable {
    public var asset: ApiPerpsAsset
    public var history: ApiPerpsActivityHistory
}

extension Api {
    public static func isPerpsSupported() async throws -> Bool {
        try await bridge.callApi("isPerpsSupported", decoding: Bool.self)
    }

    public static func perpsGetSnapshot(accountId: String) async throws -> ApiPerpsSnapshot {
        try await bridge.callApi("perpsGetSnapshot", accountId, LocalizationSupport.shared.langCode, decoding: ApiPerpsSnapshot.self)
    }
    public static func perpsGetMarketSnapshot() async throws -> ApiPerpsMarketSnapshot {
        try await bridge.callApi("perpsGetMarketSnapshot", LocalizationSupport.shared.langCode, decoding: ApiPerpsMarketSnapshot.self)
    }
    public static func perpsGetFills(accountId: String) async throws -> [ApiPerpsFill] {
        try await bridge.callApi("perpsGetFills", accountId, decoding: [ApiPerpsFill].self)
    }
    public static func perpsGetActivityHistory(accountId: String, cursor: String? = nil) async throws -> ApiPerpsActivityHistory {
        try await bridge.callApi("perpsGetActivityHistory", accountId, cursor.map { ["cursor": $0] } ?? [:], decoding: ApiPerpsActivityHistory.self)
    }
    public static func perpsGetAssetDetail(accountId: String, assetId: String, cursor: String? = nil) async throws -> ApiPerpsAssetDetail {
        try await bridge.callApi("perpsGetAssetDetail", accountId, assetId, cursor.map { ["cursor": $0] } ?? [:], decoding: ApiPerpsAssetDetail.self)
    }
    public static func perpsGetCandles(assetId: String, period: String) async throws -> [[Double]] {
        try await bridge.callApi("perpsGetCandles", assetId, period, decoding: [[Double]].self)
    }
    public static func perpsPrepareOrder(accountId: String, draft: ApiPerpsDraft) async throws -> ApiPerpsQuote {
        try await bridge.callApi("perpsPrepareOrder", accountId, draft, decoding: ApiPerpsQuote.self)
    }
    public static func perpsPreviewOrder(accountId: String, draft: ApiPerpsDraft) async throws -> ApiPerpsQuote {
        try await bridge.callApi("perpsPreviewOrder", accountId, draft, decoding: ApiPerpsQuote.self)
    }
    public static func perpsGetFundingRequirements(accountId: String, draft: ApiPerpsDraft) async throws -> ApiPerpsFundingRequirements {
        try await bridge.callApi("perpsGetFundingRequirements", accountId, draft, decoding: ApiPerpsFundingRequirements.self)
    }
    public static func perpsGetLeverageEstimates(accountId: String, draft: ApiPerpsDraft) async throws -> [ApiPerpsLeverageEstimate] {
        try await bridge.callApi("perpsGetLeverageEstimates", accountId, draft, decoding: [ApiPerpsLeverageEstimate].self)
    }
    public static func perpsGetReceiptDetails(_ input: ApiPerpsReceiptInput) async throws -> ApiPerpsReceiptDetails {
        try await bridge.callApi("perpsGetReceiptDetails", input, decoding: ApiPerpsReceiptDetails.self)
    }
    public static func perpsExecuteReviewedOrder(accountId: String, enclaveToken: EnclaveToken, quoteId: String, operationId: String) async throws -> ApiPerpsOperation {
        try await bridge.callApi("perpsExecuteReviewedOrder", accountId, enclaveToken, quoteId, operationId, decoding: ApiPerpsOperation.self)
    }
    public static func perpsReconcileOperation(accountId: String, saved: ApiPerpsOperation) async throws -> ApiPerpsOperation {
        try await bridge.callApi("perpsReconcileOperation", accountId, saved, decoding: ApiPerpsOperation.self)
    }
    public static func perpsAcknowledgeOperation(accountId: String, saved: ApiPerpsOperation) async throws -> ApiPerpsOperation {
        try await bridge.callApi("perpsAcknowledgeOperation", accountId, saved, decoding: ApiPerpsOperation.self)
    }
    public static func perpsPrepareWithdrawal(accountId: String, operationId: String) async throws -> String {
        try await bridge.callApi("perpsPrepareWithdrawal", accountId, operationId, decoding: String.self)
    }
    public static func perpsRetryWithdrawal(accountId: String, enclaveToken: EnclaveToken, operationId: String) async throws -> ApiPerpsOperation {
        try await bridge.callApi("perpsRetryWithdrawal", accountId, enclaveToken, operationId, decoding: ApiPerpsOperation.self)
    }
    public static func perpsGetOperation(accountId: String, id: String) async throws -> ApiPerpsOperation? {
        try await bridge.callApiOptional("perpsGetOperation", accountId, id, decodingOptional: ApiPerpsOperation.self)
    }
}

@MainActor public struct PerpsClient {
    public var supported: () async throws -> Bool = { try await Api.isPerpsSupported() }
    public var snapshot: (String) async throws -> ApiPerpsSnapshot = { try await Api.perpsGetSnapshot(accountId: $0) }
    public var marketSnapshot: () async throws -> ApiPerpsMarketSnapshot = { try await Api.perpsGetMarketSnapshot() }
    public var history: (String) async throws -> ApiPerpsActivityHistory = { try await Api.perpsGetActivityHistory(accountId: $0) }
    public var historyPage: (String, String) async throws -> ApiPerpsActivityHistory = { try await Api.perpsGetActivityHistory(accountId: $0, cursor: $1) }
    public var assetDetail: (String, String, String?) async throws -> ApiPerpsAssetDetail = { try await Api.perpsGetAssetDetail(accountId: $0, assetId: $1, cursor: $2) }
    public var candles: (String, String) async throws -> [[Double]] = { try await Api.perpsGetCandles(assetId: $0, period: $1) }
    public var prepare: (String, ApiPerpsDraft) async throws -> ApiPerpsQuote = { try await Api.perpsPrepareOrder(accountId: $0, draft: $1) }
    public var preview: (String, ApiPerpsDraft) async throws -> ApiPerpsQuote = { try await Api.perpsPreviewOrder(accountId: $0, draft: $1) }
    public var fundingRequirements: (String, ApiPerpsDraft) async throws -> ApiPerpsFundingRequirements = { try await Api.perpsGetFundingRequirements(accountId: $0, draft: $1) }
    public var leverageEstimates: (String, ApiPerpsDraft) async throws -> [ApiPerpsLeverageEstimate] = { try await Api.perpsGetLeverageEstimates(accountId: $0, draft: $1) }
    public var receiptDetails: (ApiPerpsReceiptInput) async throws -> ApiPerpsReceiptDetails = { try await Api.perpsGetReceiptDetails($0) }
    public var execute: (String, EnclaveToken, String, String) async throws -> ApiPerpsOperation = {
        try await Api.perpsExecuteReviewedOrder(accountId: $0, enclaveToken: $1, quoteId: $2, operationId: $3)
    }
    public var operation: (String, String) async throws -> ApiPerpsOperation? = { try await Api.perpsGetOperation(accountId: $0, id: $1) }
    public var reconcile: (String, ApiPerpsOperation) async throws -> ApiPerpsOperation = { try await Api.perpsReconcileOperation(accountId: $0, saved: $1) }
    public var acknowledge: (String, ApiPerpsOperation) async throws -> ApiPerpsOperation = { try await Api.perpsAcknowledgeOperation(accountId: $0, saved: $1) }
    public var prepareWithdrawal: (String, String) async throws -> String = { try await Api.perpsPrepareWithdrawal(accountId: $0, operationId: $1) }
    public var retryWithdrawal: (String, EnclaveToken, String) async throws -> ApiPerpsOperation = { try await Api.perpsRetryWithdrawal(accountId: $0, enclaveToken: $1, operationId: $2) }
    public init() {}
}

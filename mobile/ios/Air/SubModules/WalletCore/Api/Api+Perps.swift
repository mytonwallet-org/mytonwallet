import Foundation
import WalletContext

public enum ApiPerpsPositionSide: String, Codable, Sendable {
    case long, short
}

/// Where an order's margin comes from: an Arbitrum USDC deposit, or USDC already on Hyperliquid.
public enum ApiPerpsFundingSource: String, Codable, Sendable {
    case wallet, balance
}

public enum ApiPerpsFillEvent: String, Codable, Sendable {
    case opened, increased, reduced, closed, liquidated

    /// Reductions, closes and liquidations realize profit or loss; openings and increases add to the position.
    public var realizesProfitLoss: Bool { self == .reduced || self == .closed || self == .liquidated }
    /// The position no longer exists after this event.
    public var endsPosition: Bool { self == .closed || self == .liquidated }
}

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
    public var tradingAvailability: ApiPerpsTradingAvailability?
    public var context: Context

    public struct Context: Codable, Sendable, Equatable {
        public var markPx: String
        public var fundingPercent: String?
        public var fundingIntervalHours: Int?
        public var percentChange24h: Double?
        public var openInterestUsd: String?
        public var dayNtlVlm: String?
    }
}

public struct ApiPerpsPosition: Codable, Sendable, Equatable {
    public var entryPx: String?
    public var liquidationPx: String?
    public var leverage: Leverage
    public var positionValue: String
    public var unrealizedPnl: String

    public struct Leverage: Codable, Sendable, Equatable {
        public var value: Int
    }
}

public struct ApiPerpsAccountPosition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var assetId: String
    public var dex: String
    public var side: ApiPerpsPositionSide
    public var size: String?
    public var collateral: String
    public var equity: String
    public var isNearLiquidation: Bool?
    public var returnOnEquity: String?
    public var funding: String?
    public var raw: ApiPerpsPosition
}

/// The account's positions, totals and Hyperliquid balances; market data comes from `ApiPerpsMarketSnapshot`.
public struct ApiPerpsAccountSnapshot: Codable, Sendable, Equatable {
    public var tradingAvailability: ApiPerpsTradingAvailability?
    public var abstractionMode: String?
    public var positions: [ApiPerpsAccountPosition]
    public var totalEquity: String
    public var totalPnl: String
    public var totalReturnOnEquity: String?
    public var timestamp: Int64
    public var unavailableDexs: [String]
    /// USDC an order in each book can post from the Hyperliquid balance, keyed by dex (`""` is the native book).
    public var spendableUsdcByDex: [String: String]?
    /// Absent unless the balance exceeds the minimum a withdrawal is offered for.
    public var balanceWithdrawal: ApiPerpsBalanceWithdrawalPreview?
}

/// What one withdrawal can send from the Hyperliquid balance to the wallet.
public struct ApiPerpsBalanceWithdrawalPreview: Codable, Sendable, Equatable {
    /// The larger of native `withdrawable` and free spot USDC.
    public var balance: String
    /// Gross USDC sent: `balance` less the gas reserve and `firstTransferFee`.
    public var amount: String
    public var bridgeFee: String
    /// Hyperliquid's fee on the account's first outbound transfer, debited on top of `amount`.
    public var firstTransferFee: String?
    /// Net USDC delivered: `amount` less `bridgeFee`.
    public var receiveAmount: String
}

public struct ApiPerpsBalanceWithdrawalQuote: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var accountId: String
    /// The account's Arbitrum wallet, which receives the USDC.
    public var destination: String
    public var balance: String
    public var amount: String
    public var bridgeFee: String
    public var firstTransferFee: String?
    public var receiveAmount: String
    public var expiresAt: Int64
}

public struct ApiPerpsMarketSnapshot: Codable, Sendable, Equatable {
    public var assets: [ApiPerpsAsset]
    public var marketSections: [ApiMarketSection<ApiPerpsAsset>]?
    public var assetsFetchedAt: Int64
    public var onboarding: ApiPerpsOnboarding?

    public init(assets: [ApiPerpsAsset], marketSections: [ApiMarketSection<ApiPerpsAsset>]? = nil, assetsFetchedAt: Int64,
                onboarding: ApiPerpsOnboarding? = nil) {
        self.assets = assets
        self.marketSections = marketSections
        self.assetsFetchedAt = assetsFetchedAt
        self.onboarding = onboarding
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assets = try container.decode([ApiPerpsAsset].self, forKey: .assets)
        marketSections = try container.decodeIfPresent([ApiMarketSection<ApiPerpsAsset>].self, forKey: .marketSections)
        assetsFetchedAt = try container.decode(Int64.self, forKey: .assetsFetchedAt)
        // Stories are optional content; a shape they cannot be read in must not cost the market catalogue.
        onboarding = try? container.decodeIfPresent(ApiPerpsOnboarding.self, forKey: .onboarding)
    }
}

public struct ApiPerpsOnboarding: Codable, Sendable, Equatable {
    public var stories: [ApiPerpsOnboardingStory]

    public init(stories: [ApiPerpsOnboardingStory]) {
        self.stories = stories
    }
}

public struct ApiPerpsOnboardingStory: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var url: URL
    /// First frame of `url`, shown until the video has a frame of its own.
    public var preview: URL
    public var duration: TimeInterval
    public var bytes: Int

    public init(id: String, url: URL, preview: URL, duration: TimeInterval, bytes: Int) {
        self.id = id
        self.url = url
        self.preview = preview
        self.duration = duration
        self.bytes = bytes
    }
}

public struct ApiPerpsDraft: Encodable, Sendable {
    public var assetId: String
    public var side: ApiPerpsPositionSide
    public var amount: String
    public var leverage: Int
    public var editing: Bool?
    public var close: Bool?
    public var fraction: Int?
    public var reset: Bool?
    public var leverageOnly: Bool?
    /// Omitted for a wallet deposit.
    public var funding: ApiPerpsFundingSource?

    public init(assetId: String, side: ApiPerpsPositionSide, amount: String, leverage: Int,
                editing: Bool = false, close: Bool = false, fraction: Int? = nil, reset: Bool = false,
                leverageOnly: Bool = false, funding: ApiPerpsFundingSource? = nil) {
        self.assetId = assetId; self.side = side; self.amount = amount; self.leverage = leverage
        self.editing = editing; self.close = close; self.fraction = fraction; self.reset = reset
        self.leverageOnly = leverageOnly; self.funding = funding
    }
}

public struct ApiPerpsFees: Codable, Sendable, Equatable {
    public var exchange: String?
    public var service: String?
    public var trading: String
    public var bridge: String?
    /// Hyperliquid's fee on the account's first outbound transfer, when a withdrawal the order makes pays it.
    public var firstTransfer: String?
    public var total: String
}

public struct ApiPerpsLeverageEstimate: Codable, Sendable, Equatable {
    public var leverage: Int
    public var liquidationPrice: String?
}

public struct ApiPerpsFundingRequirements: Codable, Sendable, Equatable {
    public var requiredUsdc: String
    /// The bridge fee that `requiredUsdc` includes.
    public var requiredBridgeFeeUsdc: String?
    /// Paymaster cost in USDC when the deposit is gasless. `"0"` when the wallet pays gas in ETH.
    public var requiredGasUsdc: String
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
    public enum ReceiveStatus: String, Codable, Sendable { case pending, available }

    public var id: String
    public var accountId: String
    public var assetId: String
    public var kind: String
    public var side: ApiPerpsPositionSide
    public var leverage: Int
    public var inputAmount: String
    public var previousLeverage: Int?
    public var collateral: String
    public var previousCollateral: String?
    /// Margin of the resulting position.
    public var estimatedCollateral: String?
    /// Deposited USDC left free on Hyperliquid after the order's margin and estimated trading fees.
    public var estimatedRemainingCollateral: String?
    /// USDC a reduce or close should deliver to the wallet after trading and bridge fees.
    public var estimatedReceiveAmount: String?
    public var estimatedFees: ApiPerpsFees?
    /// Arbitrum gas of the deposit, in ETH. Set when the wallet pays that gas.
    public var estimatedNetworkFeeEth: String?
    /// USD value of `estimatedNetworkFeeEth`.
    public var estimatedNetworkFeeUsd: String?
    /// Paymaster cost of the deposit, in USDC. Set when the wallet pays gas in USDC.
    public var estimatedNetworkFeeUsdc: String?
    public var fundingRequirements: ApiPerpsFundingRequirements?
    /// `.balance` when the margin comes from the Hyperliquid balance: `paymentAmount` is that margin, with no bridge fee.
    public var funding: ApiPerpsFundingSource?
    /// The order also switches the whole Hyperliquid account to Unified, which the review shows.
    public var switchesToUnified: Bool?
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
    /// Released margin of a reduce or close is known only after it settles.
    public var receiveStatus: ReceiveStatus?
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
    /// Kept so that reconciling a restored record can tell a partial fill.
    public var submittedOrderSize: String?
    public var orderStatus: String?
    public var filledSize: String?
    public var positionSize: String?
    public var averagePrice: String?
    public var withdrawalAmount: String?
    public var withdrawalRequestedAmount: String?
    /// The figures the user reviewed for a balance withdrawal.
    public var balanceWithdrawal: ApiPerpsBalanceWithdrawalQuote?
    public var error: String?
    /// Native receipt context. Keep the reviewed values when SDK progress replaces this record.
    public var reviewedQuote: ApiPerpsQuote?
    /// Captured once from an SDK snapshot correlated with this operation's latest fill.
    public var receiptPosition: ApiPerpsAccountPosition?
    public var receiptDetails: ApiPerpsReceiptDetails?

    public var needsReconciliation: Bool { !["completed", "failed"].contains(state) }
    public var blocksTrading: Bool { needsReconciliation && !(state == "unknown" && acknowledgedAt != nil) }
    public var isBalanceWithdrawal: Bool { kind == Self.balanceWithdrawalKind }
    /// A submitted order that failed. An order refused before submission never reached Hyperliquid.
    public var isFailedOrder: Bool { state == "failed" && stage != "preparing" && !isBalanceWithdrawal }
    /// The order filled, and Hyperliquid refused to send its proceeds, which stay on the Hyperliquid balance.
    public var isWithdrawalRejected: Bool { !isBalanceWithdrawal && error?.hasPrefix("PerpsWithdrawalRejected") == true }

    static let balanceWithdrawalKind = "withdraw"
    static let balanceWithdrawalAssetId = "USDC"

    public init(id: String, accountId: String, assetId: String, kind: String, createdAt: Int64) {
        self.id = id; self.accountId = accountId; self.assetId = assetId; self.kind = kind
        self.createdAt = createdAt; self.state = "running"; self.stage = "preparing"
    }
}

extension ApiUpdate {
    /// Reads of the active account's positions failed for a minute. The next successful read publishes them again.
    public struct UpdatePerpsPositionsUnavailable: Decodable, Sendable {
        public let accountId: String
    }

    /// The SDK polls the active account and publishes its positions when they change.
    public struct UpdatePerpsPositions: Decodable, Sendable {
        public let accountId: String
        public let snapshot: ApiPerpsAccountSnapshot

        public init(accountId: String, snapshot: ApiPerpsAccountSnapshot) {
            self.accountId = accountId
            self.snapshot = snapshot
        }

        private enum CodingKeys: String, CodingKey { case accountId }

        public init(from decoder: any Decoder) throws {
            accountId = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .accountId)
            snapshot = try ApiPerpsAccountSnapshot(from: decoder)
        }
    }

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
    public var leverage: Int?
    public var collateralBefore: String?
    public var collateralAfter: String?
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
    public var oid: Int64?
    public var time: Int64
    public var px: String?
    public var sz: String?
    public var fee: String?
    public var feeToken: String
    public var eventKind: ApiPerpsFillEvent
    public var positionSide: ApiPerpsPositionSide
    public var netPnl: String?
    public var notional: String?
    public var positionSize: String?
    public var previousNotional: String?
    public var positionNotional: String?
    public var entryPrice: String?
    public var positionOpenedAt: Int64?
    public var id: String { activityId ?? "\(coin)/\(time)/\(oid ?? 0)" }
}

public struct ApiPerpsActivityHistory: Codable, Sendable, Equatable {
    public var fills: [ApiPerpsFill]
    public var nextCursor: String?
    /// Any trade on this page, including one without a catalogue market, or an older page.
    public var hasActivity: Bool
    public init(fills: [ApiPerpsFill], nextCursor: String? = nil, hasActivity: Bool? = nil) {
        self.fills = fills
        self.nextCursor = nextCursor
        self.hasActivity = hasActivity ?? (!fills.isEmpty || nextCursor != nil)
    }
}

public struct ApiPerpsAssetDetail: Codable, Sendable {
    public var asset: ApiPerpsAsset
    public var history: ApiPerpsActivityHistory
}

@MainActor public struct PerpsClient {
    public var supported: () async throws -> Bool = { try await Api.bridge.callApi("isPerpsSupported", decoding: Bool.self) }
    public var positions: (String) async throws -> ApiPerpsAccountSnapshot = {
        try await Api.bridge.callApi("perpsRefreshPositions", $0, decoding: ApiPerpsAccountSnapshot.self)
    }
    public var marketSnapshot: () async throws -> ApiPerpsMarketSnapshot = {
        try await Api.bridge.callApi("perpsGetMarketSnapshot", LocalizationSupport.shared.langCode, decoding: ApiPerpsMarketSnapshot.self)
    }
    public var history: (String) async throws -> ApiPerpsActivityHistory = {
        try await Api.bridge.callApi("perpsGetActivityHistory", $0, [String: String](), decoding: ApiPerpsActivityHistory.self)
    }
    public var historyPage: (String, String) async throws -> ApiPerpsActivityHistory = {
        try await Api.bridge.callApi("perpsGetActivityHistory", $0, ["cursor": $1], decoding: ApiPerpsActivityHistory.self)
    }
    public var assetDetail: (String, String, String?) async throws -> ApiPerpsAssetDetail = { accountId, assetId, cursor in
        try await Api.bridge.callApi("perpsGetAssetDetail", accountId, assetId, cursor.map { ["cursor": $0] } ?? [:], decoding: ApiPerpsAssetDetail.self)
    }
    public var candles: (String, String) async throws -> [[Double]] = {
        try await Api.bridge.callApi("perpsGetCandles", $0, $1, decoding: [[Double]].self)
    }
    public var prepare: (String, ApiPerpsDraft) async throws -> ApiPerpsQuote = {
        try await Api.bridge.callApi("perpsPrepareOrder", $0, $1, decoding: ApiPerpsQuote.self)
    }
    public var preview: (String, ApiPerpsDraft) async throws -> ApiPerpsQuote = {
        try await Api.bridge.callApi("perpsPreviewOrder", $0, $1, decoding: ApiPerpsQuote.self)
    }
    public var fundingRequirements: (String, ApiPerpsDraft) async throws -> ApiPerpsFundingRequirements = {
        try await Api.bridge.callApi("perpsGetFundingRequirements", $0, $1, decoding: ApiPerpsFundingRequirements.self)
    }
    public var leverageEstimate: (String, ApiPerpsDraft) async throws -> ApiPerpsLeverageEstimate = {
        try await Api.bridge.callApi("perpsGetLeverageEstimate", $0, $1, decoding: ApiPerpsLeverageEstimate.self)
    }
    public var receiptDetails: (ApiPerpsReceiptInput) async throws -> ApiPerpsReceiptDetails = {
        try await Api.bridge.callApi("perpsGetReceiptDetails", $0, decoding: ApiPerpsReceiptDetails.self)
    }
    public var execute: (String, EnclaveToken, String, String) async throws -> ApiPerpsOperation = {
        try await Api.bridge.callApi("perpsExecuteReviewedOrder", $0, $1, $2, $3, decoding: ApiPerpsOperation.self)
    }
    public var reconcile: (String, ApiPerpsOperation) async throws -> ApiPerpsOperation = {
        try await Api.bridge.callApi("perpsReconcileOperation", $0, $1, decoding: ApiPerpsOperation.self)
    }
    public var acknowledge: (String, ApiPerpsOperation) async throws -> ApiPerpsOperation = {
        try await Api.bridge.callApi("perpsAcknowledgeOperation", $0, $1, decoding: ApiPerpsOperation.self)
    }
    public var prepareWithdrawal: (String, String) async throws -> String = {
        try await Api.bridge.callApi("perpsPrepareWithdrawal", $0, $1, decoding: String.self)
    }
    public var retryWithdrawal: (String, EnclaveToken, String) async throws -> ApiPerpsOperation = {
        try await Api.bridge.callApi("perpsRetryWithdrawal", $0, $1, $2, decoding: ApiPerpsOperation.self)
    }
    public var prepareBalanceWithdrawal: (String) async throws -> ApiPerpsBalanceWithdrawalQuote = {
        try await Api.bridge.callApi("perpsPrepareBalanceWithdrawal", $0, decoding: ApiPerpsBalanceWithdrawalQuote.self)
    }
    public var executeBalanceWithdrawal: (String, EnclaveToken, String, String) async throws -> ApiPerpsOperation = {
        try await Api.bridge.callApi("perpsExecuteBalanceWithdrawal", $0, $1, $2, $3, decoding: ApiPerpsOperation.self)
    }
    public init() {}
}

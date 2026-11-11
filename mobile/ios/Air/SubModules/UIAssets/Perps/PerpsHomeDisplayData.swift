import UIComponents
import WalletCore

/// Account-scoped, render-ready snapshots built by `PerpsHomeAdapter`.
public struct PerpsPositionsDisplayData {
    public enum Status: Equatable { case loading, ready, unavailable(String) }
    public let accountID: String
    public var totalValue: BaseCurrencyAmount
    public var profitLoss: PerpsValue
    public var positions: [PerpsPositionRowDisplayData]
    public var hasOpenPositions: Bool { !positions.isEmpty || hasUnresolvedPositions }
    public var status: Status
    public var isStale: Bool
    private let hasUnresolvedPositions: Bool

    public init(accountID: String, totalValue: BaseCurrencyAmount, profitLoss: PerpsValue,
                positions: [PerpsPositionRowDisplayData], status: Status = .ready, isStale: Bool = false,
                hasUnresolvedPositions: Bool = false) {
        self.accountID = accountID
        self.totalValue = totalValue
        self.profitLoss = profitLoss
        self.positions = positions
        self.status = status
        self.isStale = isStale
        self.hasUnresolvedPositions = hasUnresolvedPositions
    }

    public func shouldAnimatePositionsChange(from previous: Self?) -> Bool {
        guard let previous, previous.accountID == accountID else { return false }
        let previousIDs = previous.status == .ready ? previous.positions.map(\.id) : []
        let currentIDs = status == .ready ? positions.map(\.id) : []
        return previousIDs != currentIDs
    }
}

public struct PerpsPositionRowDisplayData: Identifiable {
    public let id: String
    public var token: ApiToken
    public var directionAndLeverage: String
    public var value: String
    public var profitLoss: PerpsValue
    public var isAtRisk: Bool

    public init(id: String, token: ApiToken, directionAndLeverage: String, value: String,
                profitLoss: PerpsValue, isAtRisk: Bool = false) {
        self.id = id
        self.token = token
        self.directionAndLeverage = directionAndLeverage
        self.value = value
        self.profitLoss = profitLoss
        self.isAtRisk = isAtRisk
    }
}

public struct PerpsOperationStatusDisplayData {
    public let title: String
    public let message: String
    public let onSelect: @MainActor () -> Void
    public let onDismiss: @MainActor () -> Void

    public init(title: String, message: String, onSelect: @escaping @MainActor () -> Void, onDismiss: @escaping @MainActor () -> Void) {
        self.title = title; self.message = message; self.onSelect = onSelect; self.onDismiss = onDismiss
    }
}

/// The Hyperliquid balance a withdrawal can send back to the wallet.
public struct PerpsBalanceWithdrawalRowDisplayData {
    public var token: ApiToken
    public var balance: String
    /// A view account sees its balance and cannot withdraw it.
    public var canWithdraw: Bool
    public var isStale: Bool
    public var isPreparing: Bool

    public init(token: ApiToken, balance: String, canWithdraw: Bool = true, isStale: Bool = false, isPreparing: Bool = false) {
        self.token = token
        self.balance = balance
        self.canWithdraw = canWithdraw
        self.isStale = isStale
        self.isPreparing = isPreparing
    }
}

public struct PerpsHomeDisplayData {
    public var positions: PerpsPositionsDisplayData
    /// Set when the account cannot use Futures. It replaces the balance summary, the positions and the balance row.
    public var accountNotice: String?
    public var balanceWithdrawal: PerpsBalanceWithdrawalRowDisplayData?
    public var operationStatus: PerpsOperationStatusDisplayData?
    public var marketSections: [MarketSectionDisplayData]
    public var isMarketStale: Bool
    public var activities: [PerpsTradeActivity]
    public var isActivityStale: Bool
    public var showsOnboarding: Bool

    public init(positions: PerpsPositionsDisplayData, accountNotice: String? = nil, balanceWithdrawal: PerpsBalanceWithdrawalRowDisplayData? = nil,
                operationStatus: PerpsOperationStatusDisplayData? = nil,
                marketSections: [MarketSectionDisplayData] = [], isMarketStale: Bool = false,
                activities: [PerpsTradeActivity] = [], isActivityStale: Bool = false, showsOnboarding: Bool = false) {
        self.positions = positions
        self.accountNotice = accountNotice
        self.balanceWithdrawal = balanceWithdrawal
        self.operationStatus = operationStatus
        self.marketSections = marketSections
        self.isMarketStale = isMarketStale
        self.activities = activities
        self.isActivityStale = isActivityStale
        self.showsOnboarding = showsOnboarding
    }
}

public enum PerpsHomeAction: Equatable {
    case position(String)
    case allPositions
    case withdrawBalance
    case refresh
    case marketToken(sectionID: String, tokenID: String)
    case marketSection(String)
    case activity(String)
}

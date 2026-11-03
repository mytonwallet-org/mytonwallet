import WalletCore

/// Account-scoped, render-ready snapshots. The adapter owns prices, totals, ordering and pagination.
public struct PerpsPositionsDisplayData {
    public enum Status: Equatable { case loading, ready, unavailable(String) }
    public let accountID: String
    public var totalValue: BaseCurrencyAmount
    public var profitLoss: PerpsHomeValue
    public var positions: [PerpsPositionRowDisplayData]
    public var totalCount: Int
    public var status: Status
    public var isStale: Bool

    public init(accountID: String, totalValue: BaseCurrencyAmount, profitLoss: PerpsHomeValue,
                positions: [PerpsPositionRowDisplayData], totalCount: Int? = nil, status: Status = .ready, isStale: Bool = false) {
        self.accountID = accountID
        self.totalValue = totalValue
        self.profitLoss = profitLoss
        self.positions = positions
        self.totalCount = totalCount ?? positions.count
        self.status = status
        self.isStale = isStale
    }

    public func shouldAnimatePositionsChange(from previous: Self?) -> Bool {
        guard let previous, previous.accountID == accountID else { return false }
        let previousIDs = previous.status == .ready ? previous.positions.map(\.id) : []
        let currentIDs = status == .ready ? positions.map(\.id) : []
        return previousIDs != currentIDs
    }
}

public struct PerpsHomeValue {
    public enum Tone { case neutral, positive, negative }
    public var text: String
    public var tone: Tone
    public init(_ text: String, tone: Tone = .neutral) { self.text = text; self.tone = tone }
}

public struct PerpsPositionRowDisplayData: Identifiable {
    public let id: String
    public var token: ApiToken
    public var directionAndLeverage: String
    public var value: String
    public var profitLoss: PerpsHomeValue
    public var isAtRisk: Bool
    public var canSelect: Bool
    public var isStale: Bool

    public init(id: String, token: ApiToken, directionAndLeverage: String, value: String,
                profitLoss: PerpsHomeValue, isAtRisk: Bool = false, canSelect: Bool = true, isStale: Bool = false) {
        self.id = id
        self.token = token
        self.directionAndLeverage = directionAndLeverage
        self.value = value
        self.profitLoss = profitLoss
        self.isAtRisk = isAtRisk
        self.canSelect = canSelect
        self.isStale = isStale
    }
}

public struct PerpsHomeActivity: Identifiable {
    public enum Kind { case opened, increased, reduced, closed, liquidated, received, sent, transfer }
    public let id: String
    public var kind: Kind
    public var title: String
    public var badge: String
    public var date: String
    public var amount: PerpsHomeValue
    public var previousAmount: String?
    public var amountDetail: String?
    public var canSelect: Bool
    public var isStale: Bool

    public init(id: String, kind: Kind, title: String, badge: String, date: String,
                amount: PerpsHomeValue, previousAmount: String? = nil, canSelect: Bool = true, amountDetail: String? = nil,
                isStale: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.badge = badge
        self.date = date
        self.amount = amount
        self.previousAmount = previousAmount
        self.amountDetail = amountDetail
        self.canSelect = canSelect
        self.isStale = isStale
    }
}

public struct PerpsHomeDisplayData {
    public var positions: PerpsPositionsDisplayData
    public var marketSections: [MarketSectionDisplayData]
    public var activities: [PerpsHomeActivity]
    public var showsOnboarding: Bool

    public init(positions: PerpsPositionsDisplayData, marketSections: [MarketSectionDisplayData] = [],
                activities: [PerpsHomeActivity] = [], showsOnboarding: Bool = false) {
        self.positions = positions
        self.marketSections = marketSections
        self.activities = activities
        self.showsOnboarding = showsOnboarding
    }
}

public enum HomeExploreDestination: String, CaseIterable { case market, agent, futures, apps }

public enum PerpsHomeAction: Equatable {
    case position(String)
    case allPositions
    case refresh
    case marketToken(sectionID: String, tokenID: String)
    case marketSection(String)
    case activity(String)
}

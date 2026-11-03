import WalletCore

/// Display values supplied by the caller. Fetching, pricing, and trading belong to the SDK adapter.
public struct PerpsMarketDisplayData {
    public var title: String
    public var token: ApiToken
    public var price: Double?
    /// Percentage points, matching `ApiToken` (for example, `3.23` means +3.23%).
    public var percentChange24h: Double?
    public var baseCurrency: MBaseCurrency
    public var period: ApiPriceHistoryPeriod
    /// `nil` shows loading; an empty array shows the chart's empty state.
    public var history: [[Double]]?
    public var isHistoryRestored = false
    public var isStale = false
    public var description: String
    public var fundingRate: String?
    public var maxLeverage: String?
    public var volume24h: String?
    public var openInterest: String?
    public var distribution: InterestDistribution?
    public var canTrade: Bool
    public var tradingUnavailableReason: String?

    public struct InterestDistribution: Equatable {
        public var longValue: Double
        public var shortValue: Double
        public var longLabel: String
        public var shortLabel: String

        public init(longValue: Double, shortValue: Double, longLabel: String, shortLabel: String) {
            self.longValue = longValue
            self.shortValue = shortValue
            self.longLabel = longLabel
            self.shortLabel = shortLabel
        }
    }

    public init(
        title: String, token: ApiToken, price: Double?, percentChange24h: Double?,
        baseCurrency: MBaseCurrency = .USD, period: ApiPriceHistoryPeriod = .day,
        history: [[Double]]?, description: String, fundingRate: String?, maxLeverage: String?,
        volume24h: String?, openInterest: String?, distribution: InterestDistribution? = nil,
        canTrade: Bool = false, tradingUnavailableReason: String? = nil
    ) {
        self.title = title
        self.token = token
        self.price = price
        self.percentChange24h = percentChange24h
        self.baseCurrency = baseCurrency
        self.period = period
        self.history = history
        self.description = description
        self.fundingRate = fundingRate
        self.maxLeverage = maxLeverage
        self.volume24h = volume24h
        self.openInterest = openInterest
        self.distribution = distribution
        self.canTrade = canTrade
        self.tradingUnavailableReason = tradingUnavailableReason
    }
}

public enum PerpsTradeDirection {
    case long
    case short
}

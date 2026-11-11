import WalletCore
import WalletContext

public typealias PerpsTradeDirection = ApiPerpsPositionSide

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
    public var canTrade: Bool
    public var tradingUnavailableReason: String?
    /// The reason explains what the account needs, rather than warning about the market.
    public var isUnavailableReasonInformational = false

    public init(
        title: String, token: ApiToken, price: Double?, percentChange24h: Double?,
        baseCurrency: MBaseCurrency = .USD, period: ApiPriceHistoryPeriod = .day,
        history: [[Double]]?, description: String, fundingRate: String?, maxLeverage: String?,
        volume24h: String?, openInterest: String?, canTrade: Bool = false, tradingUnavailableReason: String? = nil
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
        self.canTrade = canTrade
        self.tradingUnavailableReason = tradingUnavailableReason
    }

    var infoSummary: AssetInfoSummary {
        .init(description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, fields: [
            .init(id: "fundingRate", title: lang("Funding Rate"), info: lang("$perps_funding_rate_hint"), value: fundingRate ?? "—"),
            .init(id: "maxLeverage", title: lang("Max Leverage"), info: lang("$perps_max_leverage_hint"), value: maxLeverage ?? "—"),
            .init(id: "volume24h", title: lang("24h Volume"), info: lang("$perps_volume_24h_hint"), value: volume24h ?? "—"),
            .init(id: "openInterest", title: lang("Open Interest"), info: lang("$perps_open_interest_hint"), value: openInterest ?? "—"),
        ], isStale: isStale)
    }
}

extension PerpsMarketDisplayData {
    /// A view account gets the normal screen with its actions disabled, with nothing to explain or fix.
    /// An account without Arbitrum is told what it needs.
    @MainActor public mutating func applyAccountAvailability(_ account: MAccount, store: PerpsStore = .shared) {
        isUnavailableReasonInformational = PerpsAvailability.requiresMultichainAccount(account, store: store)
        if account.isView, !isUnavailableReasonInformational { tradingUnavailableReason = nil }
    }
}

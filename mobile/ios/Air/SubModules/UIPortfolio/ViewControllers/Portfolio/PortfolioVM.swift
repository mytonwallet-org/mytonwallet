import Dependencies
import Foundation
import Perception
import WalletCore
import WalletContext

private let portfolioHistoryDiskCacheMaxAge: TimeInterval = 6 * 60 * 60

struct PortfolioHistoryResponses: Codable, Equatable, Sendable {
    let netWorth: ApiPortfolioHistoryResponse
    let pnlCumulative: ApiPortfolioHistoryResponse
    let pnl: ApiPortfolioHistoryResponse

    var hasHistoryScanCursor: Bool {
        netWorth.historyScanCursor != nil
            || pnlCumulative.historyScanCursor != nil
            || pnl.historyScanCursor != nil
    }

    func normalizedForPortfolioDisplay() -> PortfolioHistoryResponses {
        PortfolioHistoryResponses(
            netWorth: netWorth.normalizedForPortfolioDisplay(),
            pnlCumulative: pnlCumulative,
            pnl: pnl
        )
    }
}

struct PortfolioOverviewModel: Equatable {
    let dateRangeText: String?
    let netChangeText: String?
    let netChangePercentText: String?
    let isNetChangePositive: Bool
}

enum PortfolioTimeRange: String, CaseIterable, Equatable, Hashable, Sendable {
    case all = "ALL"
    case year = "1Y"
    case threeMonths = "3M"
    case month = "1M"
    case week = "7D"
    case day = "1D"

    static let displayOrder: [PortfolioTimeRange] = [
        .all,
        .year,
        .threeMonths,
        .month,
        .week,
        .day,
    ]

    var title: String {
        switch self {
        case .all:
            lang("All")
        case .year:
            lang("Y")
        case .threeMonths:
            lang("3M")
        case .month:
            lang("M")
        case .week:
            lang("W")
        case .day:
            lang("D")
        }
    }

    var density: String {
        switch self {
        case .day:
            "5m"
        case .week:
            "1h"
        case .month:
            "4h"
        case .all, .year, .threeMonths:
            "1d"
        }
    }

    var historyRequest: ApiPortfolioHistoryRequest {
        ApiPortfolioHistoryRequest(from: startDate(), density: density)
    }

    private func startDate(relativeTo now: Date = Date()) -> Date {
        switch self {
        case .all:
            return Self.allStartDate
        case .year:
            return Calendar.current.date(byAdding: .year, value: -1, to: now)
                ?? now.addingTimeInterval(-365 * 24 * 60 * 60)
        case .threeMonths:
            return Calendar.current.date(byAdding: .month, value: -3, to: now)
                ?? now.addingTimeInterval(-90 * 24 * 60 * 60)
        case .month:
            return Calendar.current.date(byAdding: .month, value: -1, to: now)
                ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .week:
            return now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .day:
            return now.addingTimeInterval(-24 * 60 * 60)
        }
    }

    private static let allStartDate: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2020
        components.month = 1
        components.day = 1
        return components.date ?? Date(timeIntervalSince1970: 1_577_836_800)
    }()
}

private struct PortfolioHistoryDiskCacheKey: Sendable {
    let accountId: String
    let network: ApiNetwork
    let baseCurrency: MBaseCurrency
    let range: PortfolioTimeRange
    let density: String

    var fileName: String {
        [
            "v1",
            accountId,
            network.rawValue,
            baseCurrency.rawValue,
            range.rawValue,
            density,
        ]
            .map(Self.sanitizedFileNamePart)
            .joined(separator: "_")
            + ".json"
    }

    private static func sanitizedFileNamePart(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedValue = value.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
        return sanitizedValue.isEmpty ? "_" : sanitizedValue
    }
}

private struct PortfolioHistoryDiskCacheEntry: Codable, Sendable {
    let storedAt: Date
    let responses: PortfolioHistoryResponses
}

private actor PortfolioHistoryDiskCache {
    static let shared = PortfolioHistoryDiskCache()

    private let directoryURL = URL.cachesDirectory.appending(components: "air", "portfolio-history")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func load(key: PortfolioHistoryDiskCacheKey, maxAge: TimeInterval) -> PortfolioHistoryResponses? {
        let url = directoryURL.appendingPathComponent(key.fileName, isDirectory: false)

        do {
            let data = try Data(contentsOf: url)
            let entry = try decoder.decode(PortfolioHistoryDiskCacheEntry.self, from: data)
            guard abs(entry.storedAt.timeIntervalSinceNow) <= maxAge else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return entry.responses
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func save(_ responses: PortfolioHistoryResponses, key: PortfolioHistoryDiskCacheKey) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let entry = PortfolioHistoryDiskCacheEntry(storedAt: Date(), responses: responses)
            let data = try encoder.encode(entry)
            try data.write(to: directoryURL.appendingPathComponent(key.fileName, isDirectory: false), options: .atomic)
        } catch {
        }
    }
}

@MainActor
@Perceptible
final class PortfolioVM: Sendable {
    @PerceptionIgnored
    @AccountContext private var account: MAccount

    let accountContext: AccountContext

    private(set) var responses: PortfolioHistoryResponses?
    private(set) var selectedRange: PortfolioTimeRange = .threeMonths
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isShowingStaleRangeData = false
    private(set) var errorText: String?
    private(set) var chartDataToken = 0

    @PerceptionIgnored
    private var loadTask: Task<Void, Never>?
    @PerceptionIgnored
    private var historyRefreshTask: Task<Void, Never>?
    @PerceptionIgnored
    private var hasLoaded = false
    @PerceptionIgnored
    private var historyRefreshAttempts = 0
    @PerceptionIgnored
    private var cachedResponses: [PortfolioTimeRange: PortfolioHistoryResponses] = [:]

    init(accountContext: AccountContext) {
        self.accountContext = accountContext
        self._account = accountContext
        selectedRange = savedRange()
        WalletCoreData.add(eventObserver: self)
    }

    isolated deinit {
        loadTask?.cancel()
        historyRefreshTask?.cancel()
        WalletCoreData.remove(observer: self)
    }

    var localInsightCards: [PortfolioInsightCardModel] {
        var cards: [PortfolioInsightCardModel] = []

        if account.isMultichain {
            cards.append(makeChainSplitCard())
        }

        cards.append(makeAssetClassesCard())
        cards.append(makeStakedCard())

        return cards
    }

    var overview: PortfolioOverviewModel {
        makeOverviewFromHistory()
            ?? makeOverviewFromBalanceChange()
            ?? PortfolioOverviewModel(
                dateRangeText: nil,
                netChangeText: nil,
                netChangePercentText: nil,
                isNetChangePositive: true
            )
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        load(
            range: selectedRange,
            resetHistoryRefreshAttempts: true,
            useCache: true,
            readsDiskCache: true
        )
    }

    func selectRange(_ range: PortfolioTimeRange) {
        guard selectedRange != range else { return }
        let previousRange = selectedRange
        let shouldDimCurrentData = responses != nil && cachedResponses[range] == nil
        selectedRange = range
        persistRange(range)
        load(
            range: range,
            resetHistoryRefreshAttempts: true,
            useCache: true,
            readsDiskCache: true,
            fadesCurrentResponsesWhileLoading: shouldDimCurrentData,
            fallbackRangeOnError: previousRange
        )
    }

    func reload(resetHistoryRefreshAttempts: Bool) {
        load(range: selectedRange, resetHistoryRefreshAttempts: resetHistoryRefreshAttempts, useCache: false)
    }

    private func reloadAfterDataChange() {
        cachedResponses.removeAll()
        hasLoaded = true
        selectedRange = savedRange()
        reload(resetHistoryRefreshAttempts: true)
    }

    private func load(
        range: PortfolioTimeRange,
        resetHistoryRefreshAttempts: Bool,
        useCache: Bool,
        readsDiskCache: Bool = false,
        fadesCurrentResponsesWhileLoading: Bool = false,
        fallbackRangeOnError: PortfolioTimeRange? = nil
    ) {
        loadTask?.cancel()
        historyRefreshTask?.cancel()

        if resetHistoryRefreshAttempts {
            historyRefreshAttempts = 0
        }

        if useCache, let responses = cachedResponses[range] {
            apply(
                responses: responses,
                for: range,
                resetHistoryRefreshAttempts: resetHistoryRefreshAttempts,
                scheduleRefresh: false,
                savesToDiskCache: false,
                diskCacheKey: nil
            )
            return
        }

        let wallets = portfolioWallets
        guard !wallets.isEmpty else {
            responses = nil
            isLoading = false
            isRefreshing = false
            isShowingStaleRangeData = false
            errorText = lang("Unavailable")
            chartDataToken &+= 1
            return
        }

        beginLoading(fadesCurrentResponsesWhileLoading: fadesCurrentResponsesWhileLoading)
        let historyRequest = range.historyRequest
        let baseCurrency = TokenStore.baseCurrency
        let diskCacheKey = makeDiskCacheKey(range: range, baseCurrency: baseCurrency)

        loadTask = Task { [weak self] in
            guard let self else { return }

            if readsDiskCache,
               cachedResponses[range] == nil,
               let cachedResponses = await PortfolioHistoryDiskCache.shared.load(
                key: diskCacheKey,
                maxAge: portfolioHistoryDiskCacheMaxAge
               ) {
                guard !Task.isCancelled else { return }
                apply(
                    responses: cachedResponses,
                    for: range,
                    resetHistoryRefreshAttempts: resetHistoryRefreshAttempts,
                    scheduleRefresh: false,
                    savesToDiskCache: false,
                    diskCacheKey: nil
                )
                beginLoading(fadesCurrentResponsesWhileLoading: false)
            }

            do {
                async let netWorthResponse = Api.fetchPortfolioNetWorthHistory(
                    wallets: wallets,
                    baseCurrency: baseCurrency,
                    historyRequest: historyRequest
                )
                async let pnlCumulativeResponse = Api.fetchPortfolioPnlCumulativeHistory(
                    wallets: wallets,
                    baseCurrency: baseCurrency,
                    historyRequest: historyRequest
                )
                async let pnlResponse = Api.fetchPortfolioPnlHistory(
                    wallets: wallets,
                    baseCurrency: baseCurrency,
                    historyRequest: historyRequest
                )
                let (netWorth, pnlCumulative, pnl) = try await (
                    netWorthResponse,
                    pnlCumulativeResponse,
                    pnlResponse
                )
                guard !Task.isCancelled else { return }

                apply(
                    responses: PortfolioHistoryResponses(
                        netWorth: netWorth,
                        pnlCumulative: pnlCumulative,
                        pnl: pnl
                    ),
                    for: range,
                    resetHistoryRefreshAttempts: resetHistoryRefreshAttempts,
                    diskCacheKey: diskCacheKey
                )
            } catch {
                guard !Task.isCancelled else { return }
                handleLoadError(
                    error,
                    failedRange: range,
                    fallbackRangeOnError: cachedResponses[range] == nil ? fallbackRangeOnError : nil
                )
            }
        }
    }

    private func makeDiskCacheKey(
        range: PortfolioTimeRange,
        baseCurrency: MBaseCurrency
    ) -> PortfolioHistoryDiskCacheKey {
        PortfolioHistoryDiskCacheKey(
            accountId: account.id,
            network: account.network,
            baseCurrency: baseCurrency,
            range: range,
            density: range.density
        )
    }

    private var portfolioWallets: [String] {
        guard account.network == .mainnet else { return [] }

        return backendSupportedPortfolioChains
            .compactMap { chain in
                guard let address = account.getAddress(chain: chain)?.nilIfEmpty else {
                    return nil
                }
                return "\(chain.rawValue):\(address)"
            }
    }

    private var backendSupportedPortfolioChains: [ApiChain] {
        ApiChain.allCases.filter { chain in
            account.supports(chain: chain)
                && account.getAddress(chain: chain)?.nilIfEmpty != nil
        }
    }

    private var localSupportedChains: [ApiChain] {
        ApiChain.allCases.filter { chain in
            account.supports(chain: chain)
                && account.getAddress(chain: chain)?.nilIfEmpty != nil
        }
    }

    private func makeChainSplitCard() -> PortfolioInsightCardModel {
        let segments = localSupportedChains
            .compactMap { chain -> PortfolioInsightSegment? in
                let value = max(0, ($account.balanceUsdByChain?[chain] ?? 0) * TokenStore.baseCurrencyRate)

                return PortfolioInsightSegment(
                    id: chain.rawValue,
                    title: chain.title,
                    value: value,
                    valueText: formatBaseValue(value),
                    colorHex: PortfolioPalette.barrelChainColor(for: chain)
                )
            }
            .sorted { $0.value > $1.value }

        let visibleSegments = segments.filter { $0.value > 0 }

        return PortfolioInsightCardModel(
            id: .chainSplit,
            title: lang("By Chain"),
            segments: visibleSegments,
            emptyText: lang("No chain balances")
        )
    }

    private func makeAssetClassesCard() -> PortfolioInsightCardModel {
        enum AssetClass: CaseIterable {
            case native
            case stablecoins
            case altcoins

            var id: String {
                switch self {
                case .native:
                    return "native"
                case .stablecoins:
                    return "stablecoins"
                case .altcoins:
                    return "altcoins"
                }
            }

            var title: String {
                switch self {
                case .native:
                    return lang("Native")
                case .stablecoins:
                    return lang("Stablecoins")
                case .altcoins:
                    return lang("Altcoins")
                }
            }

            var colorHex: String {
                switch self {
                case .native:
                    return PortfolioPalette.barrelNative
                case .stablecoins:
                    return PortfolioPalette.barrelStable
                case .altcoins:
                    return PortfolioPalette.barrelAltcoins
                }
            }
        }

        var totals = Dictionary(uniqueKeysWithValues: AssetClass.allCases.map { ($0, Double.zero) })

        for tokenBalance in $account.walletTokens ?? [] {
            let value = max(0, tokenBalance.toBaseCurrency ?? 0)
            guard value > 0 else {
                continue
            }

            let assetClass: AssetClass
            if tokenBalance.token?.isNative == true {
                assetClass = .native
            } else if isStablecoin(tokenBalance.token) {
                assetClass = .stablecoins
            } else {
                assetClass = .altcoins
            }

            totals[assetClass, default: 0] += value
        }

        let segments = AssetClass.allCases.compactMap { assetClass -> PortfolioInsightSegment? in
            let value = totals[assetClass, default: 0]
            guard value > 0 else {
                return nil
            }

            return PortfolioInsightSegment(
                id: assetClass.id,
                title: assetClass.title,
                value: value,
                valueText: formatBaseValue(value),
                colorHex: assetClass.colorHex
            )
        }

        return PortfolioInsightCardModel(
            id: .assetClasses,
            title: lang("Asset Mix"),
            segments: segments,
            emptyText: lang("No asset balances")
        )
    }

    private func makeStakedCard() -> PortfolioInsightCardModel {
        let stakedValue = ($account.walletStaked ?? [])
            .reduce(0) { partialResult, tokenBalance in
                partialResult + max(0, tokenBalance.toBaseCurrency ?? 0)
            }
        let unstakedValue = ($account.walletTokens ?? [])
            .reduce(0) { partialResult, tokenBalance in
                partialResult + max(0, tokenBalance.toBaseCurrency ?? 0)
            }

        let segments = [
            PortfolioInsightSegment(
                id: "staked",
                title: lang("Staked"),
                value: stakedValue,
                valueText: formatBaseValue(stakedValue),
                colorHex: PortfolioPalette.barrelStaked
            ),
            PortfolioInsightSegment(
                id: "unstaked",
                title: lang("Not staked"),
                value: unstakedValue,
                valueText: formatBaseValue(unstakedValue),
                colorHex: PortfolioPalette.barrelNotStaked
            ),
        ]
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }

        return PortfolioInsightCardModel(
            id: .staked,
            title: lang("Staked"),
            segments: segments,
            emptyText: lang("No staked assets")
        )
    }

    private func formatBaseValue(_ value: Double) -> String {
        BaseCurrencyAmount.fromDouble(value, TokenStore.baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
    }

    private func isStablecoin(_ token: ApiToken?) -> Bool {
        guard let token else {
            return false
        }

        let symbol = token.symbol
            .uppercased()
            .replacingOccurrences(of: "₮", with: "T")

        return symbol.contains("USD")
            && token.priceUsd.map { (0.95...1.05).contains($0) } == true
    }

    private func makeOverviewFromHistory() -> PortfolioOverviewModel? {
        guard let response = responses?.netWorth else {
            return nil
        }

        let points = makeTotalHistoryPoints(response)
        guard let start = points.first,
              let latest = points.last,
              start.timestamp < latest.timestamp
        else {
            return nil
        }

        let baseCurrency = MBaseCurrency(rawValue: response.base.uppercased()) ?? TokenStore.baseCurrency
        let netChange = latest.value - start.value
        let netChangePercent = start.value > 0 ? netChange / start.value : nil
        let formatter = MtwChartDateFormatter(
            rangeAlwaysShowsYear: true,
            omitsCurrentYearInSingleDate: false
        )

        return PortfolioOverviewModel(
            dateRangeText: formatter.rangeString(
                from: Date(timeIntervalSince1970: start.timestamp),
                to: Date(timeIntervalSince1970: latest.timestamp)
            ),
            netChangeText: BaseCurrencyAmount.fromDouble(netChange, baseCurrency)
                .formatted(.baseCurrencyEquivalent, showPlus: true, roundHalfUp: true),
            netChangePercentText: netChangePercent.map {
                formatPercent($0, decimals: 0, showPlus: false)
            },
            isNetChangePositive: netChange >= 0
        )
    }

    private func makeOverviewFromBalanceChange() -> PortfolioOverviewModel? {
        guard let balance = accountContext.balance,
              let balance24h = accountContext.balance24h,
              balance.amount > 0,
              balance24h.amount > 0
        else {
            return nil
        }

        let netChange = BaseCurrencyAmount(balance.amount - balance24h.amount, balance.baseCurrency)
        let isPositive = netChange.amount >= 0

        return PortfolioOverviewModel(
            dateRangeText: nil,
            netChangeText: netChange.formatted(.baseCurrencyEquivalent, showPlus: true, roundHalfUp: true),
            netChangePercentText: accountContext.balanceChange.map {
                formatPercent($0, decimals: 0, showPlus: false)
            },
            isNetChangePositive: isPositive
        )
    }

    private func makeTotalHistoryPoints(_ response: ApiPortfolioHistoryResponse) -> [(timestamp: TimeInterval, value: Double)] {
        if let points = response.points?.compactMap(Self.historyPoint(from:)), !points.isEmpty {
            return points.sorted { $0.timestamp < $1.timestamp }
        }

        var valuesByTimestamp: [TimeInterval: Double] = [:]
        for dataset in response.datasets ?? [] {
            for point in dataset.points {
                guard let point = Self.historyPoint(from: point) else {
                    continue
                }
                valuesByTimestamp[point.timestamp, default: 0] += point.value
            }
        }

        return valuesByTimestamp
            .map { (timestamp: $0.key, value: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static func historyPoint(from point: [Double?]) -> (timestamp: TimeInterval, value: Double)? {
        guard point.count >= 2,
              let timestamp = point[0],
              let value = point[1]
        else {
            return nil
        }

        return (timestamp, value)
    }

    private func beginLoading(fadesCurrentResponsesWhileLoading: Bool) {
        isShowingStaleRangeData = responses != nil && fadesCurrentResponsesWhileLoading

        if responses == nil {
            isLoading = true
            errorText = nil
        } else {
            isRefreshing = true
        }
    }

    private func apply(
        responses: PortfolioHistoryResponses,
        for range: PortfolioTimeRange,
        resetHistoryRefreshAttempts: Bool,
        scheduleRefresh: Bool = true,
        savesToDiskCache: Bool = true,
        diskCacheKey: PortfolioHistoryDiskCacheKey? = nil
    ) {
        let normalizedResponses = responses.normalizedForPortfolioDisplay()
        cachedResponses[range] = normalizedResponses

        if savesToDiskCache, let diskCacheKey {
            Task.detached(priority: .background) {
                await PortfolioHistoryDiskCache.shared.save(normalizedResponses, key: diskCacheKey)
            }
        }

        guard selectedRange == range else {
            return
        }

        self.responses = normalizedResponses
        isLoading = false
        isRefreshing = false
        isShowingStaleRangeData = false
        errorText = nil
        chartDataToken &+= 1

        if resetHistoryRefreshAttempts {
            historyRefreshAttempts = 0
        }

        if scheduleRefresh {
            scheduleHistoryRefreshIfNeeded(for: range)
        }
    }

    private func handleLoadError(
        _ error: Error,
        failedRange: PortfolioTimeRange,
        fallbackRangeOnError: PortfolioTimeRange?
    ) {
        if let fallbackRangeOnError,
           selectedRange == failedRange
        {
            selectedRange = fallbackRangeOnError
        }

        isLoading = false
        isRefreshing = false
        isShowingStaleRangeData = false

        if responses == nil {
            errorText = (error as? DisplayError)?.text ?? error.localizedDescription
        }
    }

    private func savedRange() -> PortfolioTimeRange {
        guard let raw = accountContext.settings.portfolioTimeRange,
              let result = PortfolioTimeRange(rawValue: raw) else {
             return .threeMonths
        }
        return result
    }

    private func persistRange(_ range: PortfolioTimeRange) {
        accountContext.settings.setPortfolioTimeRange(range.rawValue)
    }

    private func scheduleHistoryRefreshIfNeeded(for range: PortfolioTimeRange) {
        historyRefreshTask?.cancel()

        guard responses?.hasHistoryScanCursor == true,
              historyRefreshAttempts < 6
        else {
            return
        }

        historyRefreshAttempts += 1

        historyRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            load(range: range, resetHistoryRefreshAttempts: false, useCache: false)
        }
    }
}

extension PortfolioVM: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            if $account.source == .current {
                reloadAfterDataChange()
            }
        case .rawBalancesChanged(let accountId):
            if accountId == $account.accountId {
                reloadAfterDataChange()
            }
        case .baseCurrencyChanged:
            reloadAfterDataChange()
        default:
            break
        }
    }
}

import Foundation
import UIComponents
import WalletCore
import WalletContext

@MainActor public enum PerpsHomeAdapter {
    public static func positions(store: PerpsStore, accountId: String) -> PerpsPositionsDisplayData {
        let snapshot = store.snapshots[accountId]
        let error = store.snapshotErrors[accountId]
        let isStale = snapshot != nil && store.isSnapshotStale(accountId: accountId)
        let hasCompleteTotals = snapshot?.unavailableDexs.isEmpty == true
        let rows = snapshot?.positions.compactMap { position -> PerpsPositionRowDisplayData? in
            guard let asset = snapshot?.assets.first(where: { $0.id == position.assetId }) else { return nil }
            return .init(id: position.id, token: PerpsFormatting.token(asset),
                         directionAndLeverage: "\(lang(position.side == "long" ? "Long" : "Short")) \(position.raw.leverage.value)x",
                         value: PerpsFormatting.money(position.equity),
                         profitLoss: profitLoss(position.raw.unrealizedPnl, returnOnEquity: position.returnOnEquity),
                         isAtRisk: position.isNearLiquidation == true, isStale: isStale)
        } ?? []
        return .init(accountID: accountId, totalValue: PerpsFormatting.usd(hasCompleteTotals ? snapshot?.totalEquity : nil),
                     profitLoss: profitLoss(hasCompleteTotals ? snapshot?.totalPnl : nil,
                         returnOnEquity: hasCompleteTotals ? snapshot?.totalReturnOnEquity : nil, summary: true), positions: rows,
                     status: snapshot != nil ? .ready : error.map { .unavailable(lang($0)) } ?? .loading, isStale: isStale)
    }

    public static func home(store: PerpsStore, accountId: String, previewMarkets: Bool = true,
                            charts: [String: [[Double]]] = [:]) -> PerpsHomeDisplayData {
        let snapshot = store.snapshots[accountId]
        let assets = snapshot?.assets ?? []
        let sections = marketSections(snapshot: snapshot, preview: previewMarkets, charts: charts).map { section in
            var section = section
            section.tokens = section.tokens.map { item in
                var item = item
                item.isStale = store.isMarketStale(accountId: accountId)
                return item
            }
            return section
        }
        var activities = (store.fills[accountId] ?? []).compactMap { fill -> (Int64, PerpsHomeActivity)? in
            guard let asset = assets.first(where: { $0.name == fill.coin }) else { return nil }
            return activity(fill: fill, asset: asset).map { (fill.time, $0) }
        }
        activities += (store.cashFlows[accountId] ?? []).filter { $0.kind != .funding }.map { flow in
            (flow.time, cashFlow(flow, asset: assets.first { $0.id == flow.assetId || $0.name == flow.coin }))
        }
        return .init(positions: positions(store: store, accountId: accountId), marketSections: sections,
                     activities: activities.sorted { $0.0 > $1.0 }.map {
                         var activity = $0.1
                         activity.isStale = store.isHistoryStale(accountId: accountId)
                         return activity
                     }, showsOnboarding: showsOnboarding(store: store, accountId: accountId))
    }

    static func showsOnboarding(store: PerpsStore, accountId: String) -> Bool {
        guard let snapshot = store.snapshots[accountId], snapshot.unavailableDexs.isEmpty,
              snapshot.positions.isEmpty, store.hasActivityHistory[accountId] == false,
              store.pendingOperation(accountId: accountId) == nil,
              !store.operations.values.contains(where: {
                  $0.accountId == accountId && ["completed", "partial"].contains($0.state)
              }) else { return false }
        return true
    }

    public static func cashFlow(_ flow: ApiPerpsCashFlow, asset: ApiPerpsAsset?) -> PerpsHomeActivity {
        let kind: PerpsHomeActivity.Kind = flow.direction == .internal ? .transfer : flow.direction == .incoming ? .received : .sent
        let tone: PerpsHomeValue.Tone = Decimal(string: flow.amount) == 0 ? .neutral
            : flow.direction == .incoming ? .positive : .neutral
        let market = flow.coin.map { asset?.symbol ?? $0.components(separatedBy: ":").last ?? $0 } ?? ""
        return .init(id: flow.id, kind: kind, title: PerpsFormatting.cashFlowTitle(flow), badge: market,
                     date: activityDate(flow.time), amount: .init(PerpsFormatting.cashFlowAmount(flow), tone: tone))
    }

    private static func marketSections(snapshot: ApiPerpsSnapshot?, preview: Bool, charts: [String: [[Double]]]) -> [MarketSectionDisplayData] {
        if let sections = snapshot?.marketSections {
            return sections.compactMap { section in
                let assets = section.assets.filter { $0.isDelisted != true }
                guard !assets.isEmpty else { return nil }
                let limit = (section.mobileLimit ?? section.limit).flatMap { $0 > 0 ? $0 : nil }
                let visible = preview ? Array(assets.prefix(limit ?? assets.count)) : assets
                let layout: MarketSectionDisplayData.Layout = switch section.layout {
                case .largeHorizontal: .largeHorizontal
                case .grid: .grid
                case .rows: .rows
                }
                return .init(id: section.id, title: section.title, layout: layout,
                             tokens: visible.map { marketItem($0, chart: layout == .largeHorizontal, charts: charts) },
                             showsSeeAll: section.hasMore || visible.count < assets.count)
            }
        }

        // Rolling deployments can still return a catalogue without editorial sections.
        let assets = snapshot?.assets ?? []
        let groups = Dictionary(grouping: assets.filter { $0.isDelisted != true }, by: \.dex)
        var sections = groups.keys.sorted().map { dex in
            let tokens = (groups[dex] ?? []).map { marketItem($0, chart: false, charts: charts) }
            return MarketSectionDisplayData(id: dex.isEmpty ? "hyperliquid" : dex,
                title: dex.isEmpty ? "Hyperliquid" : dex, layout: .rows, tokens: preview ? Array(tokens.prefix(5)) : tokens, showsSeeAll: tokens.count > 5)
        }
        let movers = featuredAssets(assets).map { marketItem($0, chart: true, charts: charts) }
        if !movers.isEmpty {
            sections.insert(.init(id: "movers", title: "", layout: .largeHorizontal, tokens: movers), at: 0)
        }
        return sections
    }

    private static func marketItem(_ asset: ApiPerpsAsset, chart: Bool, charts: [String: [[Double]]]) -> MarketItemDisplayData {
        let change = asset.context.percentChange24h
        return .init(id: asset.id, token: PerpsFormatting.token(asset), price: PerpsFormatting.money(asset.context.markPx),
                     change: change.map { formatPercent($0 / 100) } ?? "—", isPositive: (change ?? 0) >= 0,
                     chart: chart ? .sparkline(values: asset.sparkline ?? charts[asset.id]?.compactMap { $0.count > 1 ? $0[1] : nil },
                                              tintColor: asset.tintColor ?? "#2C92F0") : nil,
                     showsChain: false)
    }

    public static func featuredAssets(_ snapshot: ApiPerpsSnapshot?) -> [ApiPerpsAsset] {
        guard let sections = snapshot?.marketSections else { return featuredAssets(snapshot?.assets ?? []) }
        var seen = Set<String>()
        return sections.filter { $0.layout == .largeHorizontal }.flatMap { section in
            let assets = section.assets.filter { $0.isDelisted != true }
            let limit = (section.mobileLimit ?? section.limit).flatMap { $0 > 0 ? $0 : nil }
            return Array(assets.prefix(limit ?? assets.count))
        }.filter { seen.insert($0.id).inserted }
    }

    /// Until the catalogue provides editorial sections, feature the most traded active markets.
    public static func featuredAssets(_ assets: [ApiPerpsAsset]) -> [ApiPerpsAsset] {
        Array(assets.filter { $0.isDelisted != true }.sorted {
            let lhs = Decimal(string: $0.context.dayNtlVlm ?? "") ?? 0
            let rhs = Decimal(string: $1.context.dayNtlVlm ?? "") ?? 0
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }.prefix(6))
    }

    public static func value(_ text: String?) -> PerpsHomeValue {
        .init(PerpsFormatting.money(text), tone: text == nil ? .neutral : text!.hasPrefix("-") ? .negative : .positive)
    }

    static func profitLoss(_ amount: String?, returnOnEquity: String?, summary: Bool = false) -> PerpsHomeValue {
        guard let amount, let decimal = Decimal(string: amount) else { return .init("—") }
        let tone: PerpsHomeValue.Tone = decimal == 0 ? .neutral : decimal < 0 ? .negative : .positive
        var text = (decimal > 0 ? "+" : "") + PerpsFormatting.money(amount)
        if let returnOnEquity, let ratio = Decimal(string: returnOnEquity) {
            let percentage = formatPercent(NSDecimalNumber(decimal: ratio).doubleValue, showPlus: false, showMinus: false)
            text += summary ? " · " + percentage : " (" + percentage + ")"
        }
        return .init(text, tone: tone)
    }
    static func activity(fill: ApiPerpsFill, asset: ApiPerpsAsset) -> PerpsHomeActivity? {
        let kind: PerpsHomeActivity.Kind
        let title: String
        switch fill.eventKind {
        case "opened": kind = .opened; title = L10n.perpsActivityOpened(asset: asset.symbol)
        case "increased": kind = .increased; title = L10n.perpsActivityIncreased(asset: asset.symbol)
        case "reduced": kind = .reduced; title = L10n.perpsActivityReduced(asset: asset.symbol)
        case "closed": kind = .closed; title = L10n.perpsActivityClosed(asset: asset.symbol)
        case "liquidated": kind = .liquidated; title = L10n.perpsActivityLiquidated(asset: asset.symbol)
        default: return nil
        }
        let direction: String = switch fill.positionSide {
        case "long": lang("Long")
        case "short": lang("Short")
        default: ""
        }
        let badge = if let leverage = fill.leverage, leverage > 0, !direction.isEmpty {
            L10n.perpsLeverageDirection(leverage: leverage.formatted(.number.locale(.forNumberFormatters)), direction: direction)
        } else {
            direction
        }
        let realizesPnl = ["reduced", "closed", "liquidated"].contains(fill.eventKind)
        let amount: PerpsHomeValue
        if realizesPnl {
            amount = profitLoss(fill.netPnl, returnOnEquity: nil)
        } else {
            // The venue records traded notional, but does not expose historical collateral.
            amount = .init(PerpsFormatting.money(fill.notional))
        }
        return .init(id: fill.id, kind: kind, title: title, badge: badge, date: activityDate(fill.time),
                     amount: amount, canSelect: true, amountDetail: lang(realizesPnl ? "Profit and Loss" : "Trade Size"))
    }

    private static func activityDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let locale = LocalizationSupport.shared.locale
        let calendar = LocalizationSupport.shared.calendar
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let day = ActivityDateFormatting.shortDateText(for: date, relativeTo: .now)
        return day + " · " + date.formatted(format.hour().minute())
    }
}

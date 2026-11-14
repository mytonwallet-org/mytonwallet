import Foundation
import UIComponents
import WalletCore
import WalletContext

@MainActor public enum PerpsHomeAdapter {
    public static func positions(store: PerpsStore, accountId: String) -> PerpsPositionsDisplayData {
        let snapshot = store.snapshots[accountId]
        let error = store.snapshotErrors[accountId]
        let hasCompleteTotals = snapshot?.unavailableDexs.isEmpty == true
        let rows = snapshot?.positions.compactMap { position -> PerpsPositionRowDisplayData? in
            guard let asset = store.asset(id: position.assetId) else { return nil }
            return .init(id: position.id, token: PerpsFormatting.token(asset),
                         directionAndLeverage: "\(lang(position.side == .long ? "Long" : "Short")) \(position.raw.leverage.value)x",
                         value: PerpsFormatting.money(position.equity),
                         profitLoss: PerpsFormatting.profitLoss(position.raw.unrealizedPnl, returnOnEquity: position.returnOnEquity),
                         isAtRisk: position.isNearLiquidation == true)
        } ?? []
        return .init(accountID: accountId, totalValue: PerpsFormatting.usd(hasCompleteTotals ? snapshot?.totalEquity : nil),
                     profitLoss: PerpsFormatting.profitLoss(hasCompleteTotals ? snapshot?.totalPnl : nil,
                         returnOnEquity: hasCompleteTotals ? snapshot?.totalReturnOnEquity : nil, summary: true), positions: rows,
                     status: snapshot != nil ? .ready : error.map { .unavailable(lang($0)) } ?? .loading,
                     isStale: snapshot != nil && store.isSnapshotStale(accountId: accountId),
                     hasUnresolvedPositions: (snapshot?.positions.count ?? 0) > rows.count)
    }

    public static func home(store: PerpsStore, accountId: String, previewMarkets: Bool = true) -> PerpsHomeDisplayData {
        let fills = store.fills[accountId] ?? []
        var timedActivities = fills.compactMap { fill in
            store.asset(named: fill.coin).map { (time: fill.time, activity: PerpsTradeActivity(fill: fill, asset: $0)) }
        }
        // A failed order older than the loaded trades waits for the page that reaches its time.
        let oldestLoadedTime = store.historyCursors[accountId] == nil ? nil : fills.last?.time
        timedActivities += store.operations.values.compactMap { operation in
            guard operation.accountId == accountId, operation.isFailedOrder,
                  oldestLoadedTime.map({ operation.createdAt >= $0 }) ?? true,
                  let asset = store.asset(id: operation.assetId) else { return nil }
            return (operation.createdAt, PerpsTradeActivity(failedOrder: operation, asset: asset))
        }
        let activities = timedActivities.sorted { $0.time > $1.time }.map(\.activity)
        return .init(positions: positions(store: store, accountId: accountId),
                     balanceWithdrawal: balanceWithdrawal(store: store, accountId: accountId),
                     marketSections: marketSections(market: store.market, preview: previewMarkets),
                     activities: activities, showsOnboarding: showsOnboarding(store: store, accountId: accountId))
    }

    /// Absent while the SDK offers no withdrawal.
    private static func balanceWithdrawal(store: PerpsStore, accountId: String) -> PerpsBalanceWithdrawalRowDisplayData? {
        guard let snapshot = store.snapshots[accountId], let preview = snapshot.balanceWithdrawal else { return nil }
        return .init(token: PerpsFormatting.hyperliquidUsdc, balance: PerpsFormatting.money(preview.balance),
                     canWithdraw: snapshot.tradingAvailability?.isAvailable == true,
                     isStale: store.isSnapshotStale(accountId: accountId))
    }

    /// A balance withdrawal is not a trade: an account that only withdrew remains new to Futures.
    static func showsOnboarding(store: PerpsStore, accountId: String) -> Bool {
        guard let snapshot = store.snapshots[accountId], snapshot.unavailableDexs.isEmpty,
              snapshot.positions.isEmpty, store.hasActivityHistory[accountId] == false,
              store.pendingOperation(accountId: accountId) == nil,
              !store.operations.values.contains(where: {
                  $0.accountId == accountId && !$0.isBalanceWithdrawal && ["completed", "partial"].contains($0.state)
              }) else { return false }
        return true
    }

    /// Previews follow Market's limits for the four columns `MarketSectionCell` renders.
    private static func marketSections(market: ApiPerpsMarketSnapshot?, preview: Bool) -> [MarketSectionDisplayData] {
        (market?.marketSections ?? []).map { section in
            let layout = MarketSection.Layout(section.layout)
            let limits = MarketSection.limits(of: section)
            let limit = preview ? MarketSection.visibleLimit(layout: layout, mobileLimit: limits.mobile,
                                                             desktopLimit: limits.desktop, columnCount: 4) : nil
            let visible = limit.map { Array(section.assets.prefix($0)) } ?? section.assets
            return .init(id: section.id, title: section.title, layout: .init(layout),
                         tokens: visible.map { marketItem($0, chart: layout == .largeHorizontal) },
                         showsSeeAll: section.hasMore || visible.count < section.assets.count)
        }
    }

    private static func marketItem(_ asset: ApiPerpsAsset, chart: Bool) -> MarketItemDisplayData {
        let change = asset.context.percentChange24h
        return .init(id: asset.id, token: PerpsFormatting.token(asset), price: PerpsFormatting.money(asset.context.markPx),
                     change: change.map { formatPercent($0 / 100) } ?? "—", isPositive: (change ?? 0) >= 0,
                     chart: chart ? .sparkline(values: asset.sparkline, tintColor: asset.tintColor) : nil,
                     showsChain: false)
    }
}

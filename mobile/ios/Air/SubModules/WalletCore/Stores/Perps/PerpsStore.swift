import Foundation
import Perception
import WalletContext

@Perceptible @MainActor public final class PerpsStore: WalletCoreData.EventsObserver {
    public static let shared = PerpsStore(
        cacheURL: URL.applicationSupportDirectory.appending(components: "air", "perps-read-cache.json"),
        legacyCacheURL: URL.cachesDirectory.appending(components: "air", "perps-read-cache.json"))
    public private(set) var isSupported = false
    public private(set) var hasResolvedCapabilities = false
    public private(set) var snapshots: [String: ApiPerpsSnapshot] = [:]
    public private(set) var fills: [String: [ApiPerpsFill]] = [:]
    public private(set) var cashFlows: [String: [ApiPerpsCashFlow]] = [:]
    /// Missing means unknown; false requires an account-history response without records or a continuation.
    public private(set) var hasActivityHistory: [String: Bool] = [:]
    public private(set) var errors: [String: String] = [:]
    public private(set) var loading: Set<String> = []
    public private(set) var snapshotLoading: Set<String> = []
    public private(set) var historyLoading: Set<String> = []
    public private(set) var snapshotErrors: [String: String] = [:]
    public private(set) var historyErrors: [String: String] = [:]
    private var snapshotFetchedAt: [String: Date] = [:]
    private var historyFetchedAt: [String: Date] = [:]
    private var charts: [String: [String: PerpsCachedChart]] = [:]
    public private(set) var operations: [String: ApiPerpsOperation] = [:]
    public private(set) var dismissedStatusIDs: Set<String> = []
    public private(set) var historyCursors: [String: String] = [:]
    @PerceptionIgnored private var historyPaging: Set<String> = []
    @PerceptionIgnored private var loadedHistoryPages: Set<String> = []
    @PerceptionIgnored private var assetCursors: [String: String] = [:]
    @PerceptionIgnored private var assetReads: Set<String> = []
    @PerceptionIgnored public let client: PerpsClient
    @PerceptionIgnored private var reads: [String: Task<Void, Never>] = [:]
    @PerceptionIgnored private var marketRead: Task<Void, Never>?
    @PerceptionIgnored private var marketSnapshot: ApiPerpsMarketSnapshot?
    @PerceptionIgnored private var chartReads: [String: Task<Void, Never>] = [:]
    @PerceptionIgnored private var executions: [String: Task<ApiPerpsOperation, Never>] = [:]
    @PerceptionIgnored private var submissionWaiters: [String: CheckedContinuation<ApiPerpsOperation, Never>] = [:]
    @PerceptionIgnored private var deletedAccounts: Set<String> = []
    @PerceptionIgnored private var generations: [String: UUID] = [:]
    @PerceptionIgnored private let cache: PerpsReadCache?
    @PerceptionIgnored private var cachedAccounts: [String: PerpsCachedAccount] = [:]
    @PerceptionIgnored private var cacheGeneration = UUID()
    @PerceptionIgnored private let save: ([ApiPerpsOperation]) -> Void
    @PerceptionIgnored private let saveDismissedStatuses: (Set<String>) -> Void

    public init(client: PerpsClient = .init(), cacheURL: URL? = nil, legacyCacheURL: URL? = nil, load: () -> [ApiPerpsOperation] = {
        guard let data = UserDefaults.standard.data(forKey: "perps.operations.v1") else { return [] }
        return (try? JSONDecoder().decode([ApiPerpsOperation].self, from: data)) ?? []
    }, save: @escaping ([ApiPerpsOperation]) -> Void = {
        UserDefaults.standard.set(try? JSONEncoder().encode($0), forKey: "perps.operations.v1")
    }, loadDismissedStatuses: () -> Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "perps.dismissedStatuses.v1") ?? [])
    }, saveDismissedStatuses: @escaping (Set<String>) -> Void = {
        UserDefaults.standard.set(Array($0), forKey: "perps.dismissedStatuses.v1")
    }) {
        self.client = client
        cache = cacheURL.map { PerpsReadCache(url: $0, legacyURL: legacyCacheURL) }
        self.save = save
        self.saveDismissedStatuses = saveDismissedStatuses
        dismissedStatusIDs = loadDismissedStatuses()
        for var operation in load() {
            if operation.state == "running" { operation.state = "unknown" }
            operations[operation.id] = operation
        }
        WalletCoreData.addImmediately(eventObserver: self)
    }

    public func loadFromCache(accountIds: Set<String>, now: Date = .now) async {
        guard let cache else { return }
        let generation = cacheGeneration
        let accountGenerations = generations
        let accounts = await cache.load()
        guard cacheGeneration == generation else { return }
        for (accountId, entry) in accounts where accountIds.contains(accountId) && !deletedAccounts.contains(accountId) {
            guard generations[accountId] == accountGenerations[accountId] else { continue }
            guard let entry = entry.sanitized(now: now) else { continue }
            if snapshots[accountId] == nil, var snapshot = entry.snapshot,
               snapshot.positions.allSatisfy({ $0.id.hasPrefix(accountId + "/") }) {
                if let marketSnapshot { applyMarket(marketSnapshot, to: &snapshot) }
                snapshots[accountId] = snapshot
                cachedAccounts[accountId, default: .init()].snapshot = snapshot
                cachedAccounts[accountId, default: .init()].snapshotFetchedAt = entry.snapshotFetchedAt
                if snapshot.unavailableDexs.isEmpty { snapshotFetchedAt[accountId] = entry.snapshotFetchedAt }
                if snapshotErrors[accountId] == nil, !snapshot.unavailableDexs.isEmpty {
                    snapshotErrors[accountId] = "PerpsIncompleteData"
                    updateReadError(accountId)
                }
            }
            if fills[accountId] == nil, let history = entry.history {
                fills[accountId] = history.fills
                cashFlows[accountId] = history.cashFlows
                cachedAccounts[accountId, default: .init()].history = history
                cachedAccounts[accountId, default: .init()].historyFetchedAt = entry.historyFetchedAt
                historyFetchedAt[accountId] = entry.historyFetchedAt
            }
            if hasActivityHistory[accountId] == nil, let hasHistory = entry.hasActivityHistory {
                hasActivityHistory[accountId] = hasHistory
                cachedAccounts[accountId, default: .init()].hasActivityHistory = hasHistory
            }
            for (key, chart) in entry.charts ?? [:] where charts[accountId]?[key] == nil {
                charts[accountId, default: [:]][key] = chart
                cachedAccounts[accountId, default: .init()].charts = charts[accountId]
            }
        }
        cache.save(cachedAccounts)
        await cache.flush()
    }

    public func loadCapabilities() async {
        do {
            isSupported = try await client.supported()
            hasResolvedCapabilities = true
        } catch {
            if isSupported { hasResolvedCapabilities = false }
            isSupported = false
        }
    }

    /// Display freshness follows the last complete response, independently of refresh requests.
    public func isSnapshotStale(accountId: String, now: Date = .now) -> Bool {
        !Self.isFresh(snapshotFetchedAt[accountId], now: now, maxAge: 60)
    }

    public func isMarketStale(accountId: String, now: Date = .now) -> Bool {
        let fetchedAt = snapshots[accountId]?.assetsFetchedAt.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
        return !Self.isFresh(fetchedAt, now: now, maxAge: 120)
    }

    public func isHistoryStale(accountId: String, now: Date = .now) -> Bool {
        !Self.isFresh(historyFetchedAt[accountId], now: now, maxAge: 300)
    }

    private static func isFresh(_ fetchedAt: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let fetchedAt, fetchedAt <= now else { return false }
        return now.timeIntervalSince(fetchedAt) < maxAge
    }

    func receiveAssetsUpdate(_ update: ApiUpdate.UpdatePerpsAssets) async {
        guard update.langCode == nil || update.langCode == LocalizationSupport.shared.langCode else { return }
        let generation = cacheGeneration
        if let pending = marketRead { await pending.value }
        guard cacheGeneration == generation, !Task.isCancelled,
              (marketSnapshot?.assetsFetchedAt ?? -1) < update.fetchedAt else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if cacheGeneration == generation { marketRead = nil } }
            do {
                let market = try await client.marketSnapshot()
                guard cacheGeneration == generation, !Task.isCancelled,
                      market.assetsFetchedAt >= update.fetchedAt else { return }
                marketSnapshot = market
                for accountId in snapshots.keys {
                    guard var snapshot = snapshots[accountId] else { continue }
                    applyMarket(market, to: &snapshot)
                    snapshots[accountId] = snapshot
                    cachedAccounts[accountId, default: .init()].snapshot = snapshot
                }
                saveReadCache()
                await cache?.flush()
            } catch { /* Keep the catalogue and its original fetch time. */ }
        }
        marketRead = task
        await task.value
    }

    private func applyMarket(_ market: ApiPerpsMarketSnapshot, to snapshot: inout ApiPerpsSnapshot) {
        guard market.assetsFetchedAt >= (snapshot.assetsFetchedAt ?? 0) else { return }
        let previousAssets = Dictionary(snapshot.assets.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        snapshot.assets = market.assets.map { asset in
            var asset = asset
            asset.description = asset.description ?? previousAssets[asset.id]?.description
            return asset
        }
        let currentIds = Set(snapshot.assets.map(\.id))
        let positionIds = Set(snapshot.positions.map(\.assetId))
        snapshot.assets += previousAssets.values.filter { positionIds.contains($0.id) && !currentIds.contains($0.id) }
        snapshot.marketSections = market.marketSections
        snapshot.limits = market.limits
        snapshot.assetsFetchedAt = market.assetsFetchedAt
    }

    public func chart(accountId: String, assetId: String, period: String) -> [[Double]]? {
        charts[accountId]?[assetId + "/" + period]?.points
    }

    public func isChartRestored(accountId: String, assetId: String, period: String, now: Date = .now) -> Bool {
        !isChartFresh(accountId: accountId, assetId: assetId, period: period, maxAge: 300, now: now)
    }

    public func isChartFresh(accountId: String, assetId: String, period: String, maxAge: TimeInterval, now: Date = .now) -> Bool {
        Self.isFresh(charts[accountId]?[assetId + "/" + period]?.fetchedAt, now: now, maxAge: maxAge)
    }

    public func refreshChart(accountId: String, assetId: String, period: String) async {
        guard !deletedAccounts.contains(accountId) else { return }
        let key = assetId + "/" + period
        let readKey = accountId + "/" + key
        if let pending = chartReads[readKey] { await pending.value; return }
        let generation = generations[accountId] ?? UUID()
        generations[accountId] = generation
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if generations[accountId] == generation { chartReads[readKey] = nil } }
            do {
                let points = try await client.candles(assetId, period)
                guard generations[accountId] == generation, !Task.isCancelled else { return }
                guard points.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && $0 > 0 } }) else {
                    throw PerpsError.invalidResponse
                }
                let entry = PerpsCachedChart(points: PerpsCachedChart.boundedPoints(points), fetchedAt: .now)
                charts[accountId, default: [:]][key] = entry
                charts[accountId] = Dictionary(uniqueKeysWithValues: (charts[accountId] ?? [:])
                    .sorted { $0.value.fetchedAt > $1.value.fetchedAt }
                    .prefix(PerpsCachedAccount.chartLimit).map { ($0.key, $0.value) })
                cachedAccounts[accountId, default: .init()].charts = charts[accountId]
                saveReadCache()
            } catch { /* Keep the last successful chart and its fetch time. */ }
        }
        chartReads[readKey] = task
        await task.value
        await cache?.flush()
    }

    private func updateReadError(_ accountId: String) {
        errors[accountId] = snapshotErrors[accountId] ?? historyErrors[accountId]
    }

    public func refresh(accountId: String, force: Bool = false) async {
        guard !deletedAccounts.contains(accountId) else { return }
        if let pending = reads[accountId] {
            await pending.value
            if force { await refresh(accountId: accountId) }
            return
        }
        let generation = generations[accountId] ?? UUID()
        generations[accountId] = generation
        loading.insert(accountId)
        snapshotLoading.insert(accountId)
        historyLoading.insert(accountId)
        let task = Task { [weak self] in
            guard let self else { return }
            async let snapshot = refreshSnapshot(accountId: accountId, generation: generation)
            async let history = refreshHistory(accountId: accountId, generation: generation)
            let (receiptSnapshot, historySucceeded) = await (snapshot, history)
            guard generations[accountId] == generation, !Task.isCancelled else { return }
            loading.remove(accountId)
            if historySucceeded {
                if let receiptSnapshot { captureReceiptPositions(accountId: accountId, snapshot: receiptSnapshot) }
                await updateReceiptDetails(accountId: accountId, generation: generation)
            }
            guard generations[accountId] == generation else { return }
            loading.remove(accountId)
            reads[accountId] = nil
            await cache?.flush()
        }
        reads[accountId] = task
        await task.value
    }

    private func refreshSnapshot(accountId: String, generation: UUID) async -> ApiPerpsSnapshot? {
        defer { if generations[accountId] == generation { snapshotLoading.remove(accountId) } }
        do {
            var snapshot = try await client.snapshot(accountId)
            guard generations[accountId] == generation, !Task.isCancelled else { return nil }
            let complete = snapshot.unavailableDexs.isEmpty
            if !snapshot.positions.isEmpty { recordActivityHistory(accountId: accountId, hasHistory: true) }
            if complete || snapshots[accountId] == nil {
                if let marketSnapshot { applyMarket(marketSnapshot, to: &snapshot) }
                let descriptions = Dictionary((snapshots[accountId]?.assets ?? []).compactMap { asset in
                    asset.description.map { (asset.id, $0) }
                }, uniquingKeysWith: { _, new in new })
                for index in snapshot.assets.indices where snapshot.assets[index].description == nil {
                    snapshot.assets[index].description = descriptions[snapshot.assets[index].id]
                }
                snapshots[accountId] = snapshot
                cachedAccounts[accountId, default: .init()].snapshot = snapshot
                if complete {
                    let fetchedAt = Date.now
                    snapshotFetchedAt[accountId] = fetchedAt
                    cachedAccounts[accountId, default: .init()].snapshotFetchedAt = fetchedAt
                }
            }
            saveReadCache()
            snapshotErrors[accountId] = complete ? nil : "PerpsIncompleteData"
            updateReadError(accountId)
            return complete ? snapshot : nil
        } catch {
            guard generations[accountId] == generation, !Task.isCancelled else { return nil }
            snapshotErrors[accountId] = "PerpsUnavailable"
            updateReadError(accountId)
            return nil
        }
    }

    private func refreshHistory(accountId: String, generation: UUID) async -> Bool {
        defer { if generations[accountId] == generation { historyLoading.remove(accountId) } }
        do {
            let history = try await client.history(accountId)
            guard generations[accountId] == generation, !Task.isCancelled else { return false }
            mergeHistory(history, accountId: accountId, isLatest: true)
            if !loadedHistoryPages.contains(accountId) { historyCursors[accountId] = history.nextCursor }
            historyErrors[accountId] = nil
            updateReadError(accountId)
            return true
        } catch {
            guard generations[accountId] == generation, !Task.isCancelled else { return false }
            historyErrors[accountId] = "PerpsUnavailable"
            updateReadError(accountId)
            return false
        }
    }

    private func mergeHistory(_ history: ApiPerpsActivityHistory, accountId: String, isLatest: Bool = false) {
        if history.hasActivity == true || !history.fills.isEmpty || !history.cashFlows.isEmpty || history.nextCursor != nil {
            recordActivityHistory(accountId: accountId, hasHistory: true)
        } else if isLatest {
            recordActivityHistory(accountId: accountId, hasHistory: false)
        }
        var seen = Set<String>()
        fills[accountId] = (history.fills + (fills[accountId] ?? []))
            .filter { seen.insert($0.id).inserted }.sorted { $0.time > $1.time }
        cashFlows[accountId] = (history.cashFlows + (cashFlows[accountId] ?? []))
            .filter { $0.kind != .funding && seen.insert($0.id).inserted }.sorted { $0.time > $1.time }
        cachedAccounts[accountId, default: .init()].history = .init(
            fills: Array((fills[accountId] ?? []).prefix(PerpsCachedAccount.historyLimit)),
            cashFlows: Array((cashFlows[accountId] ?? []).prefix(PerpsCachedAccount.historyLimit)))
        if isLatest {
            let fetchedAt = Date.now
            historyFetchedAt[accountId] = fetchedAt
            cachedAccounts[accountId, default: .init()].historyFetchedAt = fetchedAt
        }
        saveReadCache()
    }

    private func recordActivityHistory(accountId: String, hasHistory: Bool) {
        let value = hasActivityHistory[accountId] == true || hasHistory
        hasActivityHistory[accountId] = value
        cachedAccounts[accountId, default: .init()].hasActivityHistory = value
    }

    public func loadMoreHistory(accountId: String) async {
        guard !deletedAccounts.contains(accountId), let cursor = historyCursors[accountId],
              historyPaging.insert(accountId).inserted else { return }
        let generation = generations[accountId] ?? UUID()
        generations[accountId] = generation
        defer { if generations[accountId] == generation { historyPaging.remove(accountId) } }
        do {
            let page = try await client.historyPage(accountId, cursor)
            guard generations[accountId] == generation, !deletedAccounts.contains(accountId),
                  historyCursors[accountId] == cursor else { return }
            mergeHistory(page, accountId: accountId)
            historyCursors[accountId] = page.nextCursor == cursor ? nil : page.nextCursor
            loadedHistoryPages.insert(accountId)
        } catch { /* Keep the cursor so scrolling can retry. */ }
    }

    public func refreshAsset(accountId: String, assetId: String, loadMore: Bool = false) async {
        let key = accountId + "/" + assetId
        guard !deletedAccounts.contains(accountId), !loadMore || assetCursors[key] != nil,
              assetReads.insert(key).inserted else { return }
        let generation = generations[accountId] ?? UUID()
        generations[accountId] = generation
        let cursor = loadMore ? assetCursors[key] : nil
        defer { if generations[accountId] == generation { assetReads.remove(key) } }
        do {
            let detail = try await client.assetDetail(accountId, assetId, cursor)
            guard generations[accountId] == generation, !deletedAccounts.contains(accountId), detail.asset.id == assetId else { return }
            if let index = snapshots[accountId]?.assets.firstIndex(where: { $0.id == assetId }) {
                let old = snapshots[accountId]?.assets[index]
                var asset = detail.asset
                asset.sparkline = asset.sparkline ?? old?.sparkline
                snapshots[accountId]?.assets[index] = asset
                cachedAccounts[accountId, default: .init()].snapshot = snapshots[accountId]
            }
            mergeHistory(detail.history, accountId: accountId)
            assetCursors[key] = detail.history.nextCursor == cursor ? nil : detail.history.nextCursor
        } catch { /* Retain the last readable asset and history. */ }
    }

    public func removeAccount(_ accountId: String) {
        deletedAccounts.insert(accountId)
        generations[accountId] = UUID()
        reads.removeValue(forKey: accountId)?.cancel()
        snapshots.removeValue(forKey: accountId)
        fills.removeValue(forKey: accountId)
        cashFlows.removeValue(forKey: accountId)
        hasActivityHistory.removeValue(forKey: accountId)
        errors.removeValue(forKey: accountId)
        loading.remove(accountId)
        snapshotLoading.remove(accountId)
        historyLoading.remove(accountId)
        snapshotErrors.removeValue(forKey: accountId)
        historyErrors.removeValue(forKey: accountId)
        snapshotFetchedAt.removeValue(forKey: accountId)
        historyFetchedAt.removeValue(forKey: accountId)
        charts.removeValue(forKey: accountId)
        for key in chartReads.keys where key.hasPrefix(accountId + "/") {
            chartReads.removeValue(forKey: key)?.cancel()
        }
        historyCursors.removeValue(forKey: accountId)
        historyPaging.remove(accountId)
        loadedHistoryPages.remove(accountId)
        assetCursors = assetCursors.filter { !$0.key.hasPrefix(accountId + "/") }
        assetReads = assetReads.filter { !$0.hasPrefix(accountId + "/") }
        cachedAccounts.removeValue(forKey: accountId)
        saveReadCache()
    }

    public func clearCache() async {
        resetReadData()
        await cache?.flush()
    }

    private func resetReadData() {
        cacheGeneration = UUID()
        marketRead?.cancel()
        marketRead = nil
        marketSnapshot = nil
        for accountId in generations.keys { generations[accountId] = UUID() }
        for task in reads.values { task.cancel() }
        for task in chartReads.values { task.cancel() }
        reads.removeAll()
        chartReads.removeAll()
        snapshots.removeAll()
        fills.removeAll()
        cashFlows.removeAll()
        hasActivityHistory.removeAll()
        errors.removeAll()
        loading.removeAll()
        snapshotLoading.removeAll()
        historyLoading.removeAll()
        snapshotErrors.removeAll()
        historyErrors.removeAll()
        snapshotFetchedAt.removeAll()
        historyFetchedAt.removeAll()
        charts.removeAll()
        historyCursors.removeAll()
        historyPaging.removeAll()
        loadedHistoryPages.removeAll()
        assetCursors.removeAll()
        assetReads.removeAll()
        cachedAccounts.removeAll()
        saveReadCache()
    }

    private func saveReadCache() {
        let now = Date.now
        cachedAccounts = cachedAccounts.compactMapValues { $0.sanitized(now: now) }
        cache?.save(cachedAccounts)
    }

    public func pendingOperation(accountId: String, assetId: String? = nil, kind: String? = nil) -> ApiPerpsOperation? {
        operations.values.filter { operation in
            guard operation.accountId == accountId, operation.blocksTrading else { return false }
            return !(operation.state == "partial" && operation.orderStatus == "filled" && operation.orderId != nil
                && ["close", "reduce"].contains(operation.kind) && assetId != nil && operation.assetId != assetId
                && (kind == "close" || kind == "reduce"))
        }.sorted { $0.createdAt > $1.createdAt }.first
    }

    public func visibleOperationStatus(accountId: String) -> ApiPerpsOperation? {
        operations.values.filter { $0.accountId == accountId && $0.blocksTrading && !dismissedStatusIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }.first
    }

    /// Dismiss presentation only: an uncertain execution must still block resubmission.
    public func dismissOperationStatus(id: String, accountId: String) {
        guard operations[id]?.accountId == accountId else { return }
        dismissedStatusIDs.insert(id)
        saveDismissedStatuses(dismissedStatusIDs)
    }

    public func acknowledgeUnknownOperation(id: String, accountId: String) async throws {
        guard let operation = operations[id], operation.accountId == accountId,
              operation.state == "unknown", executions[id] == nil else { throw PerpsError.pending }
        let updated = try await client.acknowledge(accountId, operation)
        guard updated.id == id, updated.accountId == accountId, updated.assetId == operation.assetId,
              updated.kind == operation.kind, !updated.blocksTrading else { throw PerpsError.invalidResponse }
        guard executions[id] == nil else { throw PerpsError.pending }
        if operations[id] == operation {
            record(updated)
        } else if operations[id]?.blocksTrading == true {
            throw PerpsError.pending
        }
    }

    /// Returns when the signed operation starts, or fails before submission. The store owns settlement.
    public func execute(quote: ApiPerpsQuote, enclaveToken: EnclaveToken) async throws -> ApiPerpsOperation {
        guard pendingOperation(accountId: quote.accountId, assetId: quote.assetId, kind: quote.kind) == nil else { throw PerpsError.pending }
        guard quote.expiresAt > Int64(Date().timeIntervalSince1970 * 1000) else { throw PerpsError.expired }
        let id = UUID().uuidString
        var initial = ApiPerpsOperation(id: id, accountId: quote.accountId, assetId: quote.assetId,
                                       kind: quote.kind, createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        initial.reviewedQuote = quote
        record(initial)
        let task = Task { [self] in
            let progress = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self else { break }
                    if let value = try? await client.operation(quote.accountId, id), !Task.isCancelled {
                        receiveOperationUpdate(value)
                    }
                }
            }
            defer { progress.cancel(); executions[id] = nil }
            var result = initial
            do {
                result = try await client.execute(quote.accountId, enclaveToken, quote.id, id)
                guard result.id == id, result.accountId == quote.accountId, result.assetId == quote.assetId, result.kind == quote.kind else {
                    throw PerpsError.invalidResponse
                }
            } catch {
                result = operations[id] ?? initial
                let rejected = ["PerpsUnchanged", "PerpsQuoteExpired", "PerpsUnsupportedAccount", "PerpsOperationPending", "PerpsInvalidOperation"]
                    .first { String(describing: error).contains($0) }
                if result.state == "running" {
                    result.state = rejected == nil ? "unknown" : "failed"
                    result.error = rejected ?? "PerpsExecutionUnknown"
                }
            }
            progress.cancel()
            record(result)
            await refresh(accountId: quote.accountId, force: true)
            return result
        }
        executions[id] = task
        return await withCheckedContinuation { submissionWaiters[id] = $0 }
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updatePerpsAssets(let update):
            Task { [weak self] in await self?.receiveAssetsUpdate(update) }
        case .perpsOperationUpdated(let update): receiveOperationUpdate(update.operation)
        case .accountDeleted(let accountId): removeAccount(accountId)
        case .accountChanged(let accountId, let isNew) where isNew:
            if deletedAccounts.remove(accountId) != nil { generations[accountId] = UUID() }
        case .accountsReset:
            deletedAccounts.formUnion(snapshots.keys)
            deletedAccounts.formUnion(reads.keys)
            deletedAccounts.formUnion(operations.values.map(\.accountId))
            resetReadData()
        default: break
        }
    }

    func receiveOperationUpdate(_ operation: ApiPerpsOperation) {
        guard executions[operation.id] != nil, let previous = operations[operation.id],
              previous.accountId == operation.accountId, previous.assetId == operation.assetId,
              previous.kind == operation.kind, previous.state == "running" else { return }
        // A polling response may arrive after a newer pushed stage or terminal update.
        let stages = ["preparing", "deposit", "trade", "withdrawal", "finished"]
        if operation.state == "running",
           (stages.firstIndex(of: operation.stage) ?? 0) < (stages.firstIndex(of: previous.stage) ?? 0) { return }
        record(operation)
    }

    public func reconcile(accountId: String) async {
        for operation in operations.values where operation.accountId == accountId && operation.needsReconciliation {
            guard executions[operation.id] == nil else { continue }
            if let updated = try? await client.reconcile(accountId, operation), updated.id == operation.id,
               updated.accountId == accountId, updated.assetId == operation.assetId,
               executions[operation.id] == nil, operations[operation.id] == operation { record(updated) }
        }
        await refresh(accountId: accountId)
    }

    public func retryWithdrawal(operation: ApiPerpsOperation, enclaveToken: EnclaveToken) async throws -> ApiPerpsOperation {
        guard operations[operation.id]?.state == "partial", executions[operation.id] == nil else { throw PerpsError.pending }
        var initial = operation
        initial.state = "running"
        initial.stage = "preparing"
        record(initial)
        let task = Task { [self] in
            defer { executions[operation.id] = nil }
            var result = initial
            do {
                result = try await client.retryWithdrawal(operation.accountId, enclaveToken, operation.id)
                guard result.id == operation.id, result.accountId == operation.accountId,
                      result.assetId == operation.assetId, result.kind == operation.kind else { throw PerpsError.invalidResponse }
            } catch {
                result = operations[operation.id] ?? initial
                if result.state == "running" {
                    result.state = String(describing: error).contains("PerpsQuoteExpired") ? "partial" : "unknown"
                    result.stage = "withdrawal"
                    result.error = result.state == "partial" ? "PerpsQuoteExpired" : "PerpsExecutionUnknown"
                }
            }
            record(result)
            await refresh(accountId: operation.accountId, force: true)
            return result
        }
        executions[operation.id] = task
        return await withCheckedContinuation { submissionWaiters[operation.id] = $0 }
    }

    private func captureReceiptPositions(accountId: String, snapshot: ApiPerpsSnapshot) {
        guard let history = fills[accountId] else { return }
        for var operation in operations.values where operation.accountId == accountId
            && ["completed", "partial"].contains(operation.state) && operation.receiptPosition == nil {
            guard let quote = operation.reviewedQuote,
                  snapshot.timestamp >= operation.createdAt,
                  let asset = snapshot.assets.first(where: { $0.id == operation.assetId }),
                  !snapshot.unavailableDexs.contains(asset.dex),
                  !operations.values.contains(where: {
                      $0.accountId == accountId && $0.assetId == operation.assetId && $0.createdAt > operation.createdAt
                  }),
                  let position = snapshot.positions.first(where: { $0.assetId == operation.assetId }),
                  position.side == quote.side, position.raw.leverage.value == quote.leverage else { continue }
            if operation.kind != "leverage" {
                guard let fill = history.first(where: { $0.coin == asset.name }),
                      operation.orderId != nil, fill.oid == operation.orderId,
                      (operation.positionSize ?? fill.positionSize) == position.size else { continue }
            }
            operation.receiptPosition = position
            record(operation)
        }
    }

    private func record(_ update: ApiPerpsOperation) {
        var operation = update
        if let previous = operations[operation.id] {
            operation.reviewedQuote = previous.reviewedQuote
            operation.receiptPosition = previous.receiptPosition ?? operation.receiptPosition
            operation.receiptDetails = operation.receiptDetails ?? previous.receiptDetails
        }
        if let previous = operations[operation.id], previous.state != operation.state,
           dismissedStatusIDs.remove(operation.id) != nil {
            saveDismissedStatuses(dismissedStatusIDs)
        }
        operations[operation.id] = operation
        let retained = operations.values.sorted { $0.createdAt > $1.createdAt }
        save(Array(retained.filter(\.needsReconciliation)) + Array(retained.filter { !$0.needsReconciliation }.prefix(100)))
        if operation.state != "running" || operation.stage != "preparing" {
            submissionWaiters.removeValue(forKey: operation.id)?.resume(returning: operation)
        }
    }

    private func updateReceiptDetails(accountId: String, generation: UUID) async {
        for operation in operations.values where operation.accountId == accountId && operation.state == "completed" {
            guard let quote = operation.reviewedQuote else { continue }
            let fill = operation.orderId.flatMap { id in fills[accountId]?.first { $0.oid == id } }
            guard fill != nil || operation.kind == "leverage" || operation.withdrawalAmount != nil else { continue }
            let input = ApiPerpsReceiptInput(quote: quote, operation: operation, position: operation.receiptPosition, fill: fill)
            guard var details = try? await client.receiptDetails(input), generations[accountId] == generation,
                  var current = operations[operation.id], current.state == operation.state,
                  current.receiptDetails != details else { continue }
            details.fees = details.fees ?? current.receiptDetails?.fees
            details.receiveAmount = details.receiveAmount ?? current.receiptDetails?.receiveAmount
            details.remainingCollateral = details.remainingCollateral ?? current.receiptDetails?.remainingCollateral
            current.receiptDetails = details
            record(current)
        }
    }
}

public enum PerpsError: LocalizedError {
    case pending, expired, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .pending: lang("PerpsOperationPending")
        case .expired: lang("PerpsQuoteExpired")
        case .invalidResponse: lang("PerpsExecutionUnknown")
        }
    }
}

@MainActor public enum PerpsAvailability {
    // Read ahead of the capability probe: cached snapshots would otherwise count as support until it answers.
    public static let isEnabled = false

    public static func canRead(_ account: MAccount, store: PerpsStore = .shared) -> Bool {
        guard isEnabled else { return false }
        let supported = store.hasResolvedCapabilities ? store.isSupported : store.snapshots[account.id] != nil
        return supported && account.network == .mainnet && account.byChain["arbitrum"] != nil
    }
    public static func canTrade(_ account: MAccount, store: PerpsStore = .shared) -> Bool {
        store.isSupported && canRead(account, store: store)
            && store.snapshots[account.id]?.tradingAvailability?.isAvailable == true
    }

    public static func tradingUnavailableReason(_ account: MAccount, store: PerpsStore = .shared) -> String? {
        guard !canTrade(account, store: store) else { return nil }
        return lang(store.snapshots[account.id]?.tradingAvailability?.reason ?? "PerpsUnavailable")
    }
}

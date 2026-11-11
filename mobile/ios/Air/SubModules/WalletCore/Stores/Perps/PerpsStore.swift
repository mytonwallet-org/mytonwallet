import Foundation
import Perception
import UIKit
import WalletContext

@Perceptible @MainActor public final class PerpsStore: WalletCoreData.EventsObserver {
    public static let shared = PerpsStore(cacheDirectory: URL.applicationSupportDirectory.appending(components: "air", "perps"))
    /// Assumed until the SDK reports its build capability, so cached data shows at launch.
    public private(set) var isSupported = true
    /// The catalogue shared by all accounts. The SDK pushes `updatePerpsAssets` whenever it reads one.
    public private(set) var market: ApiPerpsMarketSnapshot?
    /// Positions by account. The SDK pushes the active account's positions whenever they change.
    public private(set) var snapshots: [String: ApiPerpsAccountSnapshot] = [:]
    public private(set) var fills: [String: [ApiPerpsFill]] = [:]
    /// Missing means unknown; false requires an account-history response without records or a continuation.
    public private(set) var hasActivityHistory: [String: Bool] = [:]
    public private(set) var loading: Set<String> = []
    public private(set) var snapshotErrors: [String: String] = [:]
    public private(set) var operations: [String: ApiPerpsOperation] = [:]
    public private(set) var dismissedStatusIDs: Set<String> = []
    public private(set) var historyCursors: [String: String] = [:]
    /// Descriptions read with asset details; the catalogue carries them only for featured assets.
    private var descriptions: [String: String] = [:]
    /// Pages read for one market, keyed by account and asset; Wallet and Futures Activity show only account pages.
    private var assetFills: [String: [ApiPerpsFill]] = [:]
    private var historyFetchedAt: [String: Date] = [:]
    private var charts: [String: PerpsCachedChart] = [:]
    /// The active account after the SDK pushed its complete positions. Unchanged positions are not pushed again.
    private var liveAccountId: String?
    @PerceptionIgnored private var assetIndex: (ids: [String: Int], names: [String: Int]) = ([:], [:])
    @PerceptionIgnored private var hasLoadedCapabilities = false
    @PerceptionIgnored private var historyPaging: Set<String> = []
    @PerceptionIgnored private var loadedHistoryPages: Set<String> = []
    @PerceptionIgnored private var assetCursors: [String: String] = [:]
    @PerceptionIgnored private var assetReads: Set<String> = []
    @PerceptionIgnored public let client: PerpsClient
    @PerceptionIgnored private var reads: [String: (task: Task<Void, Never>, includesHistory: Bool)] = [:]
    @PerceptionIgnored private var marketRead: Task<Void, Never>?
    @PerceptionIgnored private var chartReads: [String: Task<Void, Never>] = [:]
    @PerceptionIgnored private var chartsLoad: Task<Void, Never>?
    @PerceptionIgnored private var executions: [String: Task<ApiPerpsOperation, Never>] = [:]
    @PerceptionIgnored private var submissionWaiters: [String: CheckedContinuation<ApiPerpsOperation, Never>] = [:]
    @PerceptionIgnored private var receiptSources: [String: ReceiptSource] = [:]
    @PerceptionIgnored private var watchers: [ObjectIdentifier: Watcher] = [:]
    @PerceptionIgnored private var watchLoops: [String: (interval: Duration, task: Task<Void, Never>)] = [:]
    /// Watched accounts are read only while this holds.
    @PerceptionIgnored var isApplicationActive: @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }
    @PerceptionIgnored private var deletedAccounts: Set<String> = []
    @PerceptionIgnored private var generations: [String: UUID] = [:]
    @PerceptionIgnored let cache: PerpsReadCache?
    /// Changes when caches are cleared, discarding catalogue and chart reads in flight.
    @PerceptionIgnored private var cacheGeneration = UUID()
    /// Changes when caches are cleared or accounts reset, discarding account data still being restored.
    @PerceptionIgnored private var accountsGeneration = UUID()
    @PerceptionIgnored private let currentAccountId: () -> String?
    @PerceptionIgnored private let save: ([ApiPerpsOperation]) -> Void
    @PerceptionIgnored private let saveDismissedStatuses: (Set<String>) -> Void

    public init(client: PerpsClient = .init(), cacheDirectory: URL? = nil,
                currentAccountId: @escaping () -> String? = { AccountStore.accountId },
                load: () -> [ApiPerpsOperation] = PerpsStore.savedOperations, save: @escaping ([ApiPerpsOperation]) -> Void = {
        UserDefaults.standard.set(try? JSONEncoder().encode($0), forKey: "perps.operations.v1")
    }, loadDismissedStatuses: () -> Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "perps.dismissedStatuses.v1") ?? [])
    }, saveDismissedStatuses: @escaping (Set<String>) -> Void = {
        UserDefaults.standard.set(Array($0), forKey: "perps.dismissedStatuses.v1")
    }) {
        self.client = client
        cache = cacheDirectory.map(PerpsReadCache.init(directory:))
        self.currentAccountId = currentAccountId
        self.save = save
        self.saveDismissedStatuses = saveDismissedStatuses
        dismissedStatusIDs = loadDismissedStatuses()
        for var operation in load() {
            if operation.state == "running" { operation.state = "unknown" }
            operations[operation.id] = operation
        }
        WalletCoreData.addImmediately(eventObserver: self)
    }

    nonisolated public static func savedOperations() -> [ApiPerpsOperation] {
        guard let data = UserDefaults.standard.data(forKey: "perps.operations.v1") else { return [] }
        return decodeOperations(data)
    }

    /// Records decode one by one: one this version cannot read must not discard the others,
    /// such as pending trades or withdrawals awaiting recovery.
    nonisolated static func decodeOperations(_ data: Data) -> [ApiPerpsOperation] {
        ((try? JSONDecoder().decode([LossyDecodable<ApiPerpsOperation>].self, from: data)) ?? []).compactMap(\.value)
    }

    /// Restores positions, Activity and the catalogue. Launch awaits it, so Wallet and Futures render cached data
    /// on their first layout. Data that arrived during the read is newer and stays.
    public func loadFromCache(accountIds: Set<String>) async {
        guard let cache else { return }
        let generation = cacheGeneration
        let accountsGeneration = accountsGeneration
        let accountGenerations = generations
        // Both reads are queued ahead of any save made while they run, and the write-backs below keep that data.
        let accountsRead = cache.accounts.load()
        let marketRead = cache.market.load()
        let (accounts, stored) = (await accountsRead.value, await marketRead.value)
        if cacheGeneration == generation, let stored, stored.langCode == LocalizationSupport.shared.langCode {
            let isPushed = market != nil
            if !isPushed { setMarket(stored.market) }
            descriptions.merge(stored.descriptions) { current, _ in current }
            if isPushed { saveMarket() }
        }
        guard self.accountsGeneration == accountsGeneration else { return }
        for (accountId, entry) in accounts ?? [:] where accountIds.contains(accountId) && !deletedAccounts.contains(accountId) {
            guard generations[accountId] == accountGenerations[accountId], let entry = entry.sanitized() else { continue }
            if snapshots[accountId] == nil, let snapshot = entry.snapshot {
                snapshots[accountId] = snapshot
                if snapshotErrors[accountId] == nil, !snapshot.unavailableDexs.isEmpty {
                    snapshotErrors[accountId] = "PerpsIncompleteData"
                }
            }
            if fills[accountId] == nil, let restored = entry.fills {
                fills[accountId] = restored
                historyFetchedAt[accountId] = entry.historyFetchedAt
            }
            if hasActivityHistory[accountId] == nil, let hasHistory = entry.hasActivityHistory {
                hasActivityHistory[accountId] = hasHistory
            }
        }
        // The write-back drops removed accounts and replaces any save made from memory without the restored data.
        saveAccounts()
    }

    public func loadCapabilities() async {
        guard !hasLoadedCapabilities, let supported = try? await client.supported() else { return }
        hasLoadedCapabilities = true
        isSupported = supported
    }

    // MARK: - Market

    /// A catalogue asset, with the description read from its details when the catalogue has none.
    public func asset(id: String) -> ApiPerpsAsset? {
        guard let market, let index = assetIndex.ids[id] else { return nil }
        return withDescription(market.assets[index])
    }

    /// The catalogue asset of a venue coin, as named in positions and fills.
    public func asset(named name: String) -> ApiPerpsAsset? {
        guard let market, let index = assetIndex.names[name] else { return nil }
        return withDescription(market.assets[index])
    }

    private func withDescription(_ asset: ApiPerpsAsset) -> ApiPerpsAsset {
        guard asset.description == nil, let description = descriptions[asset.id] else { return asset }
        var asset = asset
        asset.description = description
        return asset
    }

    /// A catalogue that stops listing a market keeps that asset while an account holds a position in it.
    private func setMarket(_ value: ApiPerpsMarketSnapshot?) {
        var value = value
        if let listed = value?.assets {
            let listedIds = Set(listed.map(\.id))
            let positionIds = Set(snapshots.values.flatMap { $0.positions.map(\.assetId) })
            value?.assets += (market?.assets ?? []).filter { positionIds.contains($0.id) && !listedIds.contains($0.id) }
        }
        let assets = value?.assets ?? []
        assetIndex = (Dictionary(assets.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }),
                      Dictionary(assets.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { first, _ in first }))
        market = value
    }

    public func isMarketStale(now: Date = .now) -> Bool {
        let fetchedAt = market.map { Date(timeIntervalSince1970: Double($0.assetsFetchedAt) / 1_000) }
        return !Self.isFresh(fetchedAt, now: now, maxAge: 120)
    }

    func receiveAssetsUpdate(_ update: ApiUpdate.UpdatePerpsAssets) async {
        guard update.langCode == nil || update.langCode == LocalizationSupport.shared.langCode else { return }
        let generation = cacheGeneration
        if let pending = marketRead { await pending.value }
        guard cacheGeneration == generation, !Task.isCancelled,
              (market?.assetsFetchedAt ?? -1) < update.fetchedAt else { return }
        await readMarket(notOlderThan: update.fetchedAt)
    }

    /// The SDK pushes the catalogue at launch and every minute; this reads it only when none has arrived.
    private func loadMarketIfMissing() async {
        if let pending = marketRead {
            await pending.value
        } else if market == nil {
            await readMarket(notOlderThan: 0)
        }
    }

    private func readMarket(notOlderThan fetchedAt: Int64) async {
        let generation = cacheGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if cacheGeneration == generation { marketRead = nil } }
            do {
                let value = try await client.marketSnapshot()
                guard cacheGeneration == generation, !Task.isCancelled, value.assetsFetchedAt >= fetchedAt,
                      value.assetsFetchedAt >= (market?.assetsFetchedAt ?? 0) else { return }
                setMarket(value)
                saveMarket()
            } catch { /* Keep the catalogue and its original fetch time. */ }
        }
        marketRead = task
        await task.value
        await cache?.market.flush()
    }

    private func saveMarket() {
        cache?.market.save(market.map {
            PerpsCachedMarket(langCode: LocalizationSupport.shared.langCode, market: $0, descriptions: descriptions)
        })
    }

    // MARK: - Charts

    public func chart(assetId: String, period: String) -> [[Double]]? {
        charts[assetId + "/" + period]?.points
    }

    public func isChartRestored(assetId: String, period: String, now: Date = .now) -> Bool {
        !Self.isFresh(charts[assetId + "/" + period]?.fetchedAt, now: now, maxAge: 300)
    }

    public func refreshChart(assetId: String, period: String) async {
        let key = assetId + "/" + period
        if let pending = chartReads[key] { await pending.value; return }
        let generation = cacheGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if cacheGeneration == generation { chartReads[key] = nil } }
            await loadChartsIfNeeded()
            do {
                let points = try await client.candles(assetId, period)
                guard cacheGeneration == generation, !Task.isCancelled else { return }
                guard PerpsCachedChart.isValid(points) else { throw PerpsError.invalidResponse }
                charts[key] = PerpsCachedChart(points: PerpsCachedChart.boundedPoints(points), fetchedAt: .now)
                charts = PerpsCachedChart.bounded(charts)
                cache?.charts.save(charts)
            } catch { /* Keep the last successful chart and its fetch time. */ }
        }
        chartReads[key] = task
        await task.value
        await cache?.charts.flush()
    }

    /// Charts are read from disk when an asset page first asks for one.
    private func loadChartsIfNeeded() async {
        if let chartsLoad { await chartsLoad.value; return }
        guard let cache else { return }
        let generation = cacheGeneration
        let task = Task { [weak self] in
            let stored = await cache.charts.load().value ?? [:]
            guard let self, cacheGeneration == generation else { return }
            for (key, chart) in PerpsCachedChart.bounded(stored) where charts[key] == nil {
                charts[key] = chart
            }
        }
        chartsLoad = task
        await task.value
    }

    // MARK: - Positions and Activity

    /// Positions are fresh while the SDK can read them, and otherwise for a minute after the last complete read.
    public func isSnapshotStale(accountId: String, now: Date = .now) -> Bool {
        guard !isLive(accountId) else { return false }
        guard let snapshot = snapshots[accountId], snapshot.unavailableDexs.isEmpty else { return true }
        return !Self.isFresh(Date(timeIntervalSince1970: Double(snapshot.timestamp) / 1_000), now: now, maxAge: 60)
    }

    public func isHistoryStale(accountId: String, now: Date = .now) -> Bool {
        !Self.isFresh(historyFetchedAt[accountId], now: now, maxAge: 300)
    }

    private static func isFresh(_ fetchedAt: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let fetchedAt, fetchedAt <= now else { return false }
        return now.timeIntervalSince(fetchedAt) < maxAge
    }

    private func isLive(_ accountId: String) -> Bool {
        liveAccountId == accountId && currentAccountId() == accountId
    }

    /// Reads what the SDK does not push: Activity, a missing catalogue, and positions of an account it does not poll.
    /// Wallet reads positions only; Futures also reads Activity and settles receipts.
    public func refresh(accountId: String, includesHistory: Bool = true, force: Bool = false) async {
        guard !deletedAccounts.contains(accountId) else { return }
        if let pending = reads[accountId] {
            await pending.task.value
            if force || (includesHistory && !pending.includesHistory) {
                await refresh(accountId: accountId, includesHistory: includesHistory)
            }
            return
        }
        let generation = generation(for: accountId)
        let readsPositions = !isLive(accountId)
        loading.insert(accountId)
        let task = Task { [weak self] in
            guard let self else { return }
            async let market: Void = loadMarketIfMissing()
            async let positions: Void = readsPositions ? refreshPositions(accountId: accountId, generation: generation) : ()
            async let history = includesHistory ? refreshHistory(accountId: accountId, generation: generation) : false
            let historySucceeded = await history
            _ = await (market, positions)
            guard generations[accountId] == generation, !Task.isCancelled else { return }
            loading.remove(accountId)
            if historySucceeded {
                captureReceiptPositions(accountId: accountId)
                await updateReceiptDetails(accountId: accountId, generation: generation)
            }
            guard generations[accountId] == generation else { return }
            reads[accountId] = nil
            await cache?.accounts.flush()
        }
        reads[accountId] = (task, includesHistory)
        await task.value
    }

    private func refreshPositions(accountId: String, generation: UUID) async {
        do {
            let snapshot = try await client.positions(accountId)
            guard generations[accountId] == generation, !Task.isCancelled else { return }
            applyPositions(snapshot, accountId: accountId, isPush: false)
        } catch {
            guard generations[accountId] == generation, !Task.isCancelled else { return }
            snapshotErrors[accountId] = "PerpsUnavailable"
        }
    }

    /// An incomplete read replaces only an absent portfolio: its totals would understate the account.
    private func applyPositions(_ snapshot: ApiPerpsAccountSnapshot, accountId: String, isPush: Bool) {
        guard !deletedAccounts.contains(accountId) else { return }
        let complete = snapshot.unavailableDexs.isEmpty
        if isPush, accountId == currentAccountId() { liveAccountId = complete ? accountId : nil }
        if !snapshot.positions.isEmpty { recordActivityHistory(accountId: accountId, hasHistory: true) }
        if complete || snapshots[accountId] == nil { snapshots[accountId] = snapshot }
        snapshotErrors[accountId] = complete ? nil : "PerpsIncompleteData"
        saveAccounts()
        if complete, captureReceiptPositions(accountId: accountId) {
            let generation = generation(for: accountId)
            Task { [weak self] in await self?.updateReceiptDetails(accountId: accountId, generation: generation) }
        }
    }

    private func refreshHistory(accountId: String, generation: UUID) async -> Bool {
        guard let history = try? await client.history(accountId),
              generations[accountId] == generation, !Task.isCancelled else { return false }
        mergeHistory(history, accountId: accountId, isLatest: true)
        if !loadedHistoryPages.contains(accountId) { historyCursors[accountId] = history.nextCursor }
        return true
    }

    private func mergeHistory(_ history: ApiPerpsActivityHistory, accountId: String, isLatest: Bool = false) {
        if history.hasActivity || isLatest { recordActivityHistory(accountId: accountId, hasHistory: history.hasActivity) }
        fills[accountId] = Self.merged(history.fills, over: fills[accountId] ?? [])
        if isLatest { historyFetchedAt[accountId] = .now }
        saveAccounts()
    }

    /// Newest first. A trade in `preferred` replaces its copy in `others`.
    private static func merged(_ preferred: [ApiPerpsFill], over others: [ApiPerpsFill]) -> [ApiPerpsFill] {
        var seen = Set<String>()
        return (preferred + others).filter { seen.insert($0.id).inserted }.sorted { $0.time > $1.time }
    }

    private func recordActivityHistory(accountId: String, hasHistory: Bool) {
        hasActivityHistory[accountId] = hasActivityHistory[accountId] == true || hasHistory
    }

    public func loadMoreHistory(accountId: String) async {
        guard !deletedAccounts.contains(accountId), let cursor = historyCursors[accountId],
              historyPaging.insert(accountId).inserted else { return }
        let generation = generation(for: accountId)
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
        let generation = generation(for: accountId)
        let cursor = loadMore ? assetCursors[key] : nil
        let accountReadAtStart = historyFetchedAt[accountId]
        defer { if generations[accountId] == generation { assetReads.remove(key) } }
        do {
            let detail = try await client.assetDetail(accountId, assetId, cursor)
            guard generations[accountId] == generation, !deletedAccounts.contains(accountId), detail.asset.id == assetId else { return }
            if let description = detail.asset.description, descriptions[assetId] != description {
                descriptions[assetId] = description
                saveMarket()
            }
            if detail.history.hasActivity { recordActivityHistory(accountId: accountId, hasHistory: true) }
            assetFills[key] = Self.merged(detail.history.fills, over: assetFills[key] ?? [])
            if historyFetchedAt[accountId] == accountReadAtStart {
                let read = Dictionary(detail.history.fills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                fills[accountId] = fills[accountId]?.map { read[$0.id] ?? $0 }
            }
            assetCursors[key] = detail.history.nextCursor == cursor ? nil : detail.history.nextCursor
            saveAccounts()
        } catch { /* Retain the last readable asset and history. */ }
    }

    /// Account Activity merged with the pages read for this market. The account copy holds a trade's newest read, so it wins.
    public func fills(accountId: String, assetId: String) -> [ApiPerpsFill]? {
        guard let page = assetFills[accountId + "/" + assetId] else { return fills[accountId] }
        return Self.merged(fills[accountId] ?? [], over: page)
    }

    public func fill(accountId: String, id: String) -> ApiPerpsFill? {
        fills[accountId]?.first { $0.id == id } ?? assetFills
            .first { $0.key.hasPrefix(accountId + "/") && $0.value.contains { $0.id == id } }?
            .value.first { $0.id == id }
    }

    private func generation(for accountId: String) -> UUID {
        let generation = generations[accountId] ?? UUID()
        generations[accountId] = generation
        return generation
    }

    // MARK: - Removal

    /// Removes the account's data only; the catalogue and charts are shared.
    public func removeAccount(_ accountId: String) {
        deletedAccounts.insert(accountId)
        forgetAccount(accountId)
        saveAccounts()
    }

    public func clearCache() async {
        resetAccounts()
        cacheGeneration = UUID()
        marketRead?.cancel()
        marketRead = nil
        for task in chartReads.values { task.cancel() }
        chartReads.removeAll()
        setMarket(nil)
        descriptions.removeAll()
        charts.removeAll()
        saveAccounts()
        saveMarket()
        cache?.charts.save(nil)
        await cache?.flush()
    }

    private func forgetAccount(_ accountId: String) {
        generations[accountId] = UUID()
        reads.removeValue(forKey: accountId)?.task.cancel()
        snapshots.removeValue(forKey: accountId)
        fills.removeValue(forKey: accountId)
        assetFills = assetFills.filter { !$0.key.hasPrefix(accountId + "/") }
        hasActivityHistory.removeValue(forKey: accountId)
        loading.remove(accountId)
        snapshotErrors.removeValue(forKey: accountId)
        historyFetchedAt.removeValue(forKey: accountId)
        historyCursors.removeValue(forKey: accountId)
        historyPaging.remove(accountId)
        loadedHistoryPages.remove(accountId)
        assetCursors = assetCursors.filter { !$0.key.hasPrefix(accountId + "/") }
        assetReads = assetReads.filter { !$0.hasPrefix(accountId + "/") }
        if liveAccountId == accountId { liveAccountId = nil }
    }

    /// Discards every account's data, including data still being restored or read.
    private func resetAccounts() {
        accountsGeneration = UUID()
        for accountId in knownAccountIds { forgetAccount(accountId) }
        receiptSources.removeAll()
    }

    private var knownAccountIds: Set<String> {
        Set(generations.keys).union(snapshots.keys).union(fills.keys).union(hasActivityHistory.keys)
            .union(reads.keys).union(operations.values.map(\.accountId))
    }

    private func saveAccounts() {
        guard let cache else { return }
        let accountIds = Set(snapshots.keys).union(fills.keys).union(hasActivityHistory.keys)
        let accounts = Dictionary(uniqueKeysWithValues: accountIds.map { accountId in
            (accountId, PerpsCachedAccount(snapshot: snapshots[accountId],
                                           fills: fills[accountId].map { Array($0.prefix(PerpsCachedAccount.historyLimit)) },
                                           historyFetchedAt: historyFetchedAt[accountId],
                                           hasActivityHistory: hasActivityHistory[accountId]))
        })
        cache.accounts.save(accounts.isEmpty ? nil : accounts)
    }

    // MARK: - Operations

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
    /// Progress arrives through `perpsOperationUpdated`; the SDK pushes the resulting positions.
    public func execute(quote: ApiPerpsQuote, enclaveToken: EnclaveToken) async throws -> ApiPerpsOperation {
        guard pendingOperation(accountId: quote.accountId, assetId: quote.assetId, kind: quote.kind) == nil else { throw PerpsError.pending }
        guard quote.expiresAt > Int64(Date().timeIntervalSince1970 * 1000) else { throw PerpsError.expired }
        var initial = ApiPerpsOperation(id: UUID().uuidString, accountId: quote.accountId, assetId: quote.assetId,
                                       kind: quote.kind, createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        initial.reviewedQuote = quote
        return await track(initial, submit: { [client] in
            try await client.execute(quote.accountId, enclaveToken, quote.id, initial.id)
        }, resolveFailure: Self.resolveSubmissionFailure)
    }

    /// Returns when the signed withdrawal starts, or fails before submission. The store owns settlement.
    public func executeBalanceWithdrawal(quote: ApiPerpsBalanceWithdrawalQuote, enclaveToken: EnclaveToken) async throws -> ApiPerpsOperation {
        guard pendingOperation(accountId: quote.accountId) == nil else { throw PerpsError.pending }
        guard quote.expiresAt > Int64(Date().timeIntervalSince1970 * 1000) else { throw PerpsError.expired }
        var initial = ApiPerpsOperation(id: UUID().uuidString, accountId: quote.accountId, assetId: ApiPerpsOperation.balanceWithdrawalAssetId,
                                       kind: ApiPerpsOperation.balanceWithdrawalKind, createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        initial.withdrawalAmount = quote.amount
        initial.balanceWithdrawal = quote
        return await track(initial, submit: { [client] in
            try await client.executeBalanceWithdrawal(quote.accountId, enclaveToken, quote.id, initial.id)
        }, resolveFailure: Self.resolveSubmissionFailure)
    }

    /// An error the SDK raises before submitting moved no funds. Any other error leaves the outcome unknown.
    private static func resolveSubmissionFailure(_ operation: inout ApiPerpsOperation, error: any Error) {
        let rejected = ["PerpsUnchanged", "PerpsQuoteExpired", "PerpsUnsupportedAccount", "PerpsOperationPending", "PerpsInvalidOperation"]
            .first { String(describing: error).contains($0) }
        operation.state = rejected == nil ? "unknown" : "failed"
        operation.error = rejected ?? "PerpsExecutionUnknown"
    }

    /// Records the operation and settles it through `submit`, returning when it starts or fails before submission.
    /// `resolveFailure` settles an operation still running when `submit` throws.
    private func track(_ initial: ApiPerpsOperation, submit: @escaping () async throws -> ApiPerpsOperation,
                       resolveFailure: @escaping (inout ApiPerpsOperation, _ error: any Error) -> Void) async -> ApiPerpsOperation {
        let id = initial.id
        record(initial)
        let task = Task { [self] in
            defer { executions[id] = nil }
            var result = initial
            do {
                result = try await submit()
                guard result.id == id, result.accountId == initial.accountId, result.assetId == initial.assetId, result.kind == initial.kind else {
                    throw PerpsError.invalidResponse
                }
            } catch {
                result = operations[id] ?? initial
                if result.state == "running" { resolveFailure(&result, error) }
            }
            record(result)
            await refresh(accountId: initial.accountId, force: true)
            return result
        }
        executions[id] = task
        return await withCheckedContinuation { submissionWaiters[id] = $0 }
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updatePerpsPositions(let update):
            applyPositions(update.snapshot, accountId: update.accountId, isPush: true)
        case .updatePerpsPositionsUnavailable(let update):
            if liveAccountId == update.accountId { liveAccountId = nil }
        case .updatePerpsAssets(let update):
            Task { [weak self] in await self?.receiveAssetsUpdate(update) }
        case .perpsOperationUpdated(let update): receiveOperationUpdate(update.operation)
        case .accountDeleted(let accountId): removeAccount(accountId)
        case .accountChanged(let accountId, let isNew):
            // The SDK polls only the active account. Its first push after the switch may precede this event.
            if liveAccountId != accountId { liveAccountId = nil }
            if isNew, deletedAccounts.remove(accountId) != nil { generations[accountId] = UUID() }
        case .accountsReset:
            deletedAccounts.formUnion(knownAccountIds)
            resetAccounts()
            saveAccounts()
        default: break
        }
    }

    private func receiveOperationUpdate(_ operation: ApiPerpsOperation) {
        guard executions[operation.id] != nil, let previous = operations[operation.id],
              previous.accountId == operation.accountId, previous.assetId == operation.assetId,
              previous.kind == operation.kind, previous.state == "running" else { return }
        record(operation)
    }

    /// Copies the SDK's record of each unresolved operation. After an SDK start this restores its lock, and otherwise it
    /// picks up changes no execution reports, such as a withdrawal the SDK found nothing left to send for.
    public func reconcile(accountId: String) async {
        for operation in operations.values where operation.accountId == accountId && operation.needsReconciliation {
            guard executions[operation.id] == nil else { continue }
            if let updated = try? await client.reconcile(accountId, operation), updated.id == operation.id,
               updated.accountId == accountId, updated.assetId == operation.assetId,
               executions[operation.id] == nil, operations[operation.id] == operation { record(updated) }
        }
        await refresh(accountId: accountId)
    }

    /// Reconciles an account at the shortest interval its watchers ask for, while any of them is alive and has not
    /// called `unwatch`. Screens share one loop per account; it starts with a read and skips reads in the background.
    public func watch(accountId: String, every interval: Duration, by owner: AnyObject) {
        watchers[ObjectIdentifier(owner)] = .init(owner: owner, accountId: accountId, interval: interval)
        if let loop = watchLoops[accountId], loop.interval <= interval { return }
        watchLoops[accountId]?.task.cancel()
        watchLoops[accountId] = (interval, Task { [weak self] in await self?.runWatchLoop(accountId: accountId) })
    }

    public func unwatch(by owner: AnyObject) {
        watchers[ObjectIdentifier(owner)] = nil
    }

    private func runWatchLoop(accountId: String) async {
        while !Task.isCancelled {
            watchers = watchers.filter { $0.value.owner != nil }
            guard let interval = watchers.values.filter({ $0.accountId == accountId }).map(\.interval).min() else {
                watchLoops[accountId] = nil
                return
            }
            watchLoops[accountId]?.interval = interval
            if isApplicationActive() { await reconcile(accountId: accountId) }
            try? await Task.sleep(for: interval)
        }
    }

    public func retryWithdrawal(operation: ApiPerpsOperation, enclaveToken: EnclaveToken) async throws -> ApiPerpsOperation {
        guard operations[operation.id]?.state == "partial", executions[operation.id] == nil else { throw PerpsError.pending }
        var initial = operation
        initial.state = "running"
        initial.stage = "preparing"
        return await track(initial, submit: { [client] in
            try await client.retryWithdrawal(operation.accountId, enclaveToken, operation.id)
        }, resolveFailure: { result, error in
            result.state = String(describing: error).contains("PerpsQuoteExpired") ? "partial" : "unknown"
            result.stage = "withdrawal"
            result.error = result.state == "partial" ? "PerpsQuoteExpired" : "PerpsExecutionUnknown"
        })
    }

    /// Records the position an operation settled into once its fill and a later complete positions read agree.
    @discardableResult
    private func captureReceiptPositions(accountId: String) -> Bool {
        guard let history = fills[accountId], let snapshot = snapshots[accountId], snapshot.unavailableDexs.isEmpty else { return false }
        var captured = false
        for var operation in operations.values where operation.accountId == accountId
            && ["completed", "partial"].contains(operation.state) && operation.receiptPosition == nil {
            guard let quote = operation.reviewedQuote,
                  snapshot.timestamp >= operation.createdAt,
                  let asset = asset(id: operation.assetId),
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
            captured = true
        }
        return captured
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

    private struct ReceiptSource: Equatable {
        let fill: ApiPerpsFill?
        let position: ApiPerpsAccountPosition?
    }

    private struct Watcher {
        weak var owner: AnyObject?
        let accountId: String
        let interval: Duration
    }

    /// A completed receipt is recomputed only when its fill or settled position changes.
    private func updateReceiptDetails(accountId: String, generation: UUID) async {
        for operation in operations.values where operation.accountId == accountId && operation.state == "completed" {
            guard let quote = operation.reviewedQuote else { continue }
            let fill = operation.orderId.flatMap { id in fills[accountId]?.first { $0.oid == id } }
            guard fill != nil || operation.kind == "leverage" || operation.withdrawalAmount != nil else { continue }
            let source = ReceiptSource(fill: fill, position: operation.receiptPosition)
            guard receiptSources[operation.id] != source else { continue }
            let input = ApiPerpsReceiptInput(quote: quote, operation: operation, position: operation.receiptPosition, fill: fill)
            guard var details = try? await client.receiptDetails(input), generations[accountId] == generation else { continue }
            receiptSources[operation.id] = source
            guard var current = operations[operation.id], current.state == operation.state,
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
    // Release-only: checked ahead of the capability probe, so neither its default nor a cached snapshot opens Perps.
    public static let isEnabled = false

    public static func canRead(_ account: MAccount, store: PerpsStore = .shared) -> Bool {
        isEnabled && store.isSupported && account.network == .mainnet && account.byChain["arbitrum"] != nil
    }
    public static func canTrade(_ account: MAccount, store: PerpsStore = .shared) -> Bool {
        canRead(account, store: store) && store.snapshots[account.id]?.tradingAvailability?.isAvailable == true
    }

    /// Everything else is available on this build and network, so only a wallet with Arbitrum is missing.
    public static func requiresMultichainAccount(_ account: MAccount, store: PerpsStore = .shared) -> Bool {
        isEnabled && store.isSupported && account.network == .mainnet && account.byChain["arbitrum"] == nil
    }

    public static func tradingUnavailableReason(_ account: MAccount, store: PerpsStore = .shared) -> String? {
        guard !canTrade(account, store: store) else { return nil }
        if requiresMultichainAccount(account, store: store) { return lang("PerpsRequiresMultichainWallet") }
        return lang(store.snapshots[account.id]?.tradingAvailability?.reason ?? "PerpsUnavailable")
    }
}

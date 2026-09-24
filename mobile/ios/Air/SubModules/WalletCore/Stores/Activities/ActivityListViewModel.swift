import UIKit
import WalletContext
import OrderedCollections
import WalletCoreTypes

private let log = Log("ActivityListViewModel")

@MainActor public protocol ActivityListViewModelDelegate: AnyObject, Sendable {
    func activityViewModelChanged()
}

public actor ActivityListViewModel: WalletCoreData.EventsObserver {

    struct LoadRetryPolicy: Equatable, Sendable {
        let delay: Duration

        static let standard = LoadRetryPolicy(delay: .seconds(10))

        func shouldRetry(isEndReached: Bool?) -> Bool {
            return isEndReached != true
        }
    }

    public typealias Section = NativeIdentifier<SectionValue>
    public typealias Row = NativeIdentifier<RowValue>

    public enum SectionValue: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case custom(String)
        case placeholderTransactionsSection
        case transactions(String, Date)
        case emptyPlaceholder
    }
    public enum RowValue: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case custom(String)
        case transaction(String, String)
        case transactionPlaceholder(Int)
        case loadingMore
        case emptyPlaceholder
    }

    public static let placeholderTransactionRows = (0..<100).map(Row.transactionPlaceholder)

    nonisolated public let accountContext: AccountContext
    nonisolated public let accountId: String
    public let token: ApiToken?

    @MainActor public var activitiesById: [String: ApiActivity]?
    @MainActor private var activityIdAliasesSnapshot: [String: String] = [:]
    @MainActor public var idsByDate: OrderedDictionary<Date, [String]>?
    @MainActor public var isEndReached: Bool?
    @MainActor public var isEmpty: Bool?
    @MainActor public var snapshot: NSDiffableDataSourceSnapshot<Section, Row>!

    @MainActor public weak var delegate: ActivityListViewModelDelegate?

    private let activitiesStore: _ActivityStore
    private var activityIdAliases: [String: String] = [:]
    private var snapshotProxy: ActivityListSnapshotProxy
    private var currentIdsByDate: OrderedDictionary<Date, [String]>?
    private var currentIsEndReached: Bool?
    private let loadRetryPolicy = LoadRetryPolicy.standard

    public private(set) var loadMoreTask: Task<Void, Never>?
    private var loadRetryTask: Task<Void, Never>?

    deinit {
        loadMoreTask?.cancel()
        loadRetryTask?.cancel()
    }

    public init(
        accountId: String,
        token: ApiToken?,
        customSectionIDs: [String] = [],
        delegate: any ActivityListViewModelDelegate
    ) async {
        await self.init(accountId: accountId, token: token, customSectionIDs: customSectionIDs,
                        delegate: delegate, activitiesStore: .shared)
    }

    init(
        accountId: String,
        token: ApiToken?,
        customSectionIDs: [String] = [],
        delegate: any ActivityListViewModelDelegate,
        activitiesStore: _ActivityStore
    ) async {
        self.activitiesStore = activitiesStore
        self.accountContext = await AccountContext(accountId: accountId)
        self.accountId = accountId
        self.token = token
        self.snapshotProxy = ActivityListSnapshotProxy(accountId: accountId, customSectionIDs: customSectionIDs)
        await getState(updatedIds: [], replacedIds: [:])
        WalletCoreData.add(eventObserver: self)
        await MainActor.run {
            self.delegate = delegate // set delegate after getState so that it doesn't get notified on the initial load
        }
        if token != nil, currentIdsByDate == nil {
            requestMoreIfNeeded()
        }
    }

    private func getState(updatedIds: [String], replacedIds: [String: String]) async {
        let accountState = await activitiesStore.getAccountState(accountId)

        let activitiesById = accountState.byId
        
        let poisoningCache = await activitiesStore.getPoisoningCache(accountId)

        let sourceIds = if let slug = token?.slug {
            accountState.idsBySlug?[slug]
        } else {
            accountState.idsMain
        }
        let ids = ActivityVisibilityFilter.visibleIDs(
            sourceIds,
            activitiesById: activitiesById,
            accountId: accountId,
            token: token,
            poisoningCache: poisoningCache,
            hideTinyTransfers: AppStorageHelper.hideTinyTransfers
        )

        log.info("[inf] getState activitiesById: \(activitiesById?.count ?? -1)")

        let idsByDate: OrderedDictionary<Date, [String]>?
        let updatedStableIds: [String]
        if let ids {
            let stableIdByCurrent = updateActivityIdAliases(replacedIds: replacedIds, nextIds: ids)
            let grouped = OrderedDictionary(grouping: ids) { id in
                let stableId = stableIdByCurrent[id] ?? id
                let resolvedId = activityIdAliases[stableId] ?? stableId
                if let activity = activitiesById?[resolvedId] {
                    return Calendar.current.startOfDay(for: activity.timestampDate)
                }
                assertionFailure("logic error")
                return Date.distantPast
            }
            idsByDate = OrderedDictionary(uniqueKeysWithValues: zip(grouped.keys, grouped.values.map { group in
                group.map { stableIdByCurrent[$0] ?? $0 }
            }))
            log.info("getState \(token?.slug ?? "main", .public): datesCount: \(grouped.count) idsCount: \(ids.count)")
            var updatedSet = Set(updatedIds.map { stableIdByCurrent[$0] ?? $0 })
            for (_, newId) in replacedIds {
                updatedSet.insert(stableIdByCurrent[newId] ?? newId)
            }
            updatedStableIds = Array(updatedSet)
        } else {
            idsByDate = nil
            updatedStableIds = []
        }

        let storeIsEndReached = if let slug = token?.slug {
            accountState.isHistoryEndReachedBySlug?[slug]
        } else {
            accountState.isMainHistoryEndReached
        }
        let isEndReached = storeIsEndReached

        currentIdsByDate = idsByDate
        currentIsEndReached = isEndReached
        if isEndReached == true {
            loadRetryTask?.cancel()
            loadRetryTask = nil
        }
        snapshotProxy.didUpdateData(idsByDate: idsByDate)
        let snapshot = makeSnapshot(idsByDate: idsByDate,
                                    isEndReached: isEndReached,
                                    updatedIds: updatedStableIds)

        let activityIdAliasesSnapshot = activityIdAliases
        await MainActor.run {
            self.activitiesById = activitiesById
            self.activityIdAliasesSnapshot = activityIdAliasesSnapshot
            self.idsByDate = idsByDate
            self.isEndReached = isEndReached
            self.isEmpty = isEndReached == true && idsByDate?.isEmpty != false
            self.snapshot = snapshot
        }
        await delegate?.activityViewModelChanged()
    }

    private func makeSnapshot(idsByDate: OrderedDictionary<Date, [String]>?,
                              isEndReached: Bool?,
                              updatedIds: [String]) -> NSDiffableDataSourceSnapshot<Section, Row> {
        let start = Date()
        defer { log.info("makeSnapshot: \(Date().timeIntervalSince(start))s")}
        return snapshotProxy.makeSnapshot(idsByDate: idsByDate,
                                          isEndReached: isEndReached,
                                          updatedIds: updatedIds)
    }

    nonisolated public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .activitiesChanged(let accountId, let updatedIds, let replacedIds):
            if accountId == self.accountId {
                await getState(updatedIds: updatedIds, replacedIds: replacedIds)
            }
        case .hideTinyTransfersChanged:
            await getState(updatedIds: [], replacedIds: [:])
        case .hideUnverifiedNftsChanged:
            await getState(updatedIds: [], replacedIds: [:])
        case .nftsChanged(let accountId):
            if accountId == self.accountId {
                await getState(updatedIds: [], replacedIds: [:])
            }
        default:
            break
        }
    }

    public func requestMoreIfNeeded() {
        guard loadMoreTask == nil else { return }
        loadRetryTask?.cancel()
        loadRetryTask = nil
        loadMoreTask = Task {
            let didFail: Bool
            do {
                if let token {
                    try await activitiesStore.fetchTokenActivities(accountId: accountId, limit: 60, token: token, shouldLoadWithBudget: true)
                } else {
                    try await activitiesStore.fetchAllActivities(accountId: accountId, limit: 60, shouldLoadWithBudget: true)
                }
                didFail = false
            } catch {
                log.error("requestMoreIfNeeded: \(error)")
                didFail = !Task.isCancelled
            }
            await getState(updatedIds: [], replacedIds: [:])
            self.loadMoreTask = nil
            if didFail {
                scheduleLoadRetryIfNeeded()
            }
        }
    }

    private func scheduleLoadRetryIfNeeded() {
        guard loadRetryPolicy.shouldRetry(isEndReached: currentIsEndReached) else { return }
        let delay = loadRetryPolicy.delay
        loadRetryTask?.cancel()
        loadRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.performScheduledLoadRetry()
        }
    }

    private func performScheduledLoadRetry() {
        loadRetryTask = nil
        requestMoreIfNeeded()
    }

    public func rowDidBecomeVisible(_ row: Row) async {
        if snapshotProxy.rowDidBecomeVisible(row, isEndReached: currentIsEndReached) {
            requestMoreIfNeeded()
        }
    }

    private func updateActivityIdAliases(replacedIds: [String: String], nextIds: [String]) -> [String: String] {
        if !replacedIds.isEmpty {
            for (oldId, newId) in replacedIds {
                if let stableId = activityIdAliases.first(where: { $0.value == oldId })?.key {
                    activityIdAliases = activityIdAliases.filter { key, value in
                        value != newId || key == stableId
                    }
                    activityIdAliases[stableId] = newId
                } else {
                    activityIdAliases = activityIdAliases.filter { key, value in
                        value != newId || key == oldId
                    }
                    activityIdAliases[oldId] = newId
                }
            }
        }
        if !activityIdAliases.isEmpty {
            let nextIdSet = Set(nextIds)
            activityIdAliases = activityIdAliases.filter { stableId, currentId in
                // A reappearing source is a separate live row; it must own its own identifier.
                nextIdSet.contains(currentId) && !nextIdSet.contains(stableId)
            }
        }
        var stableIdByCurrent: [String: String] = [:]
        for (stableId, currentId) in activityIdAliases {
            stableIdByCurrent[currentId] = stableId
        }
        return stableIdByCurrent
    }

    @MainActor public func activity(forStableId stableId: String) -> ApiActivity? {
        let resolvedId = activityIdAliasesSnapshot[stableId] ?? stableId
        return activitiesById?[resolvedId]
    }
}

public extension NativeIdentifier where Value == ActivityListViewModel.SectionValue {
    static var headerPlaceholder: Self { Self(.headerPlaceholder) }
    static func custom(_ id: String) -> Self { Self(.custom(id)) }
    static var placeholderTransactionsSection: Self { Self(.placeholderTransactionsSection) }
    static func transactions(_ accountId: String, _ date: Date) -> Self { Self(.transactions(accountId, date)) }
    static var emptyPlaceholder: Self { Self(.emptyPlaceholder) }
}

public extension NativeIdentifier where Value == ActivityListViewModel.RowValue {
    static var headerPlaceholder: Self { Self(.headerPlaceholder) }
    static func custom(_ id: String) -> Self { Self(.custom(id)) }
    static func transaction(_ accountId: String, _ id: String) -> Self { Self(.transaction(accountId, id)) }
    static func transactionPlaceholder(_ index: Int) -> Self { Self(.transactionPlaceholder(index)) }
    static var loadingMore: Self { Self(.loadingMore) }
    static var emptyPlaceholder: Self { Self(.emptyPlaceholder) }
}

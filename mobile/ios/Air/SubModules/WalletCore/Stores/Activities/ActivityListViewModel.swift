import UIKit
import WalletContext
import OrderedCollections

private let log = Log("ActivityListViewModel")

@MainActor public protocol ActivityListViewModelDelegate: AnyObject, Sendable {
    func activityViewModelChanged()
}

public actor ActivityListViewModel: WalletCoreData.EventsObserver {

    public enum Section: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case custom(String)
        case placeholderTransactionsSection
        case transactions(String, Date)
        case emptyPlaceholder
    }
    public enum Row: Equatable, Hashable, Sendable {
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

    private var activitiesStore: _ActivityStore = .shared
    private var activityIdAliases: [String: String] = [:]
    private var snapshotProxy: ActivityListSnapshotProxy
    private var currentIdsByDate: OrderedDictionary<Date, [String]>?
    private var currentIsEndReached: Bool?

    public private(set) var loadMoreTask: Task<Void, Never>?

    public init(accountId: String, token: ApiToken?, customSectionIDs: [String] = [], delegate: any ActivityListViewModelDelegate) async {
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

        var ids = if let slug = token?.slug {
            accountState.idsBySlug?[slug]
        } else {
            accountState.idsMain
        }
        let hideTinyTransfers = AppStorageHelper.hideTinyTransfers
        ids = ids?.filter {
            if let activity = activitiesById?[$0] {
                switch activity {
                case .transaction(let transaction):
                    if activity.shouldHide == true {
                        return false
                    }
                    if transaction.isIncoming && poisoningCache.isTransactionWithPoisoning(transaction: transaction) {
                        return false
                    }
                    if hideTinyTransfers {
                        let tokenPriceUsd = TokenStore.tokens[activity.slug]?.priceUsd
                        if self.token != nil && tokenPriceUsd == 0 { // do not hide zero value tokens on token page
                            return true
                        }
                        if !activity.isTinyOrScamTransaction {
                            return true
                        }
                        return false
                    } else {
                        return true
                    }
                case .swap:
                    return true
                }
            } else {
                return false
            }
        }

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

        let isEndReached = if let slug = token?.slug {
            accountState.isHistoryEndReachedBySlug?[slug]
        } else {
            accountState.isMainHistoryEndReached
        }

        currentIdsByDate = idsByDate
        currentIsEndReached = isEndReached
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

    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .activitiesChanged(let accountId, let updatedIds, let replacedIds):
            if accountId == self.accountId {
                await getState(updatedIds: updatedIds, replacedIds: replacedIds)
            }
        case .hideTinyTransfersChanged:
            await getState(updatedIds: [], replacedIds: [:])
        default:
            break
        }
    }

    public func requestMoreIfNeeded() {
        guard loadMoreTask == nil else { return }
        loadMoreTask = Task {
            do {
                if let token {
                    try await activitiesStore.fetchTokenActivities(accountId: accountId, limit: 60, token: token, shouldLoadWithBudget: true)
                } else {
                    try await activitiesStore.fetchAllActivities(accountId: accountId, limit: 60, shouldLoadWithBudget: true)
                }
            } catch {
                log.error("requestMoreIfNeeded: \(error)")
            }
            self.loadMoreTask = nil
        }
    }

    public func rowDidBecomeVisible(_ row: Row) async {
        let actions = snapshotProxy.rowDidBecomeVisible(row, isEndReached: currentIsEndReached)
        if actions.shouldUpdateSnapshot {
            let snapshot = makeSnapshot(idsByDate: currentIdsByDate,
                                        isEndReached: currentIsEndReached,
                                        updatedIds: [])
            await MainActor.run {
                self.snapshot = snapshot
            }
            await delegate?.activityViewModelChanged()
        }
        if actions.shouldRequestRemotePage {
            requestMoreIfNeeded()
        }
    }

    public func scrollDidStop(lastVisibleRow: Row?) async {
        guard snapshotProxy.scrollDidStop(lastVisibleRow: lastVisibleRow) else { return }
        let snapshot = makeSnapshot(idsByDate: currentIdsByDate,
                                    isEndReached: currentIsEndReached,
                                    updatedIds: [])
        await MainActor.run {
            self.snapshot = snapshot
        }
        await delegate?.activityViewModelChanged()
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
            activityIdAliases = activityIdAliases.filter { _, currentId in
                nextIdSet.contains(currentId)
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

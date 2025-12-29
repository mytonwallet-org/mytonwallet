
import UIKit
import WalletContext
import OrderedCollections

private let log = Log("ActivityViewModel")

@MainActor public protocol ActivityViewModelDelegate: AnyObject {
    func activityViewModelChanged()
}

public actor ActivityViewModel: WalletCoreData.EventsObserver {

    public enum Section: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case firstRow
        case transactions(String, Date)
        case emptyPlaceholder
    }
    public enum Row: Equatable, Hashable, Sendable {
        case headerPlaceholder
        case firstRow
        case transaction(String, String)
        case loadingMore
        case emptyPlaceholder
    }

    nonisolated public let accountId: String
    public let token: ApiToken?

    @MainActor public var activitiesById: [String: ApiActivity]?
    @MainActor public var idsByDate: OrderedDictionary<Date, [String]>?
    @MainActor public var isEndReached: Bool?
    @MainActor public var isEmpty: Bool?
    @MainActor public var snapshot: NSDiffableDataSourceSnapshot<Section, Row>!

    public weak var delegate: ActivityViewModelDelegate?

    private var activitiesStore: _ActivityStore = .shared

    public private(set) var loadMoreTask: Task<Void, Never>?

    public init(accountId: String, token: ApiToken?, delegate: any ActivityViewModelDelegate) async {
        self.accountId = accountId
        self.token = token
        await getState(updatedIds: [])
        WalletCoreData.add(eventObserver: self)
        self.delegate = delegate // set delegate after getState so that it doesn't get notified on the initial load
    }

    private func getState(updatedIds: [String]) async {
        let accountState = await activitiesStore.getAccountState(accountId)

        let activitiesById = accountState.byId

        var ids = if let slug = token?.slug {
            accountState.idsBySlug?[slug]
        } else {
            accountState.idsMain
        }
        let hideTinyTransfers = AppStorageHelper.hideTinyTransfers
        let alwaysShownSlugs = AccountStore.assetsAndActivityData[accountId]?.alwaysShownSlugs
        ids = ids?.filter {
            if let activity = activitiesById?[$0] {
                if activity.kind == .swap {
                    return true
                }
                if activity.shouldHide == true {
                    return false
                }
                if !hideTinyTransfers {
                    return true
                }
                if TokenStore.tokens[activity.slug]?.priceUsd == 0 {
                    return true // priceless tokens
                }
                if !activity.isTinyOrScamTransaction {
                    return true
                }
                if alwaysShownSlugs?.contains(activity.slug) == true {
                    return true
                }
            }
            return false
        }

        log.info("[inf] getState activitiesById: \(activitiesById?.count ?? -1)")

        let idsByDate: OrderedDictionary<Date, [String]>?
        if let ids {
            let grouped = OrderedDictionary(grouping: ids) { id in
                if let activity = activitiesById?[id] {
                    return Calendar.current.startOfDay(for: activity.timestampDate)
                }
                assertionFailure("logic error")
                return Date.distantPast
            }
            log.info("getState \(token?.slug ?? "main", .public): datesCount: \(grouped.count) idsCount: \(ids.count)")
            idsByDate = grouped
        } else {
            idsByDate = nil
        }

        let isEndReached = if let slug = token?.slug {
            accountState.isHistoryEndReachedBySlug?[slug]
        } else {
            accountState.isMainHistoryEndReached
        }

        let snapshot = await makeSnapshot(idsByDate: idsByDate,
                                          showFirstRow: token != nil,
                                          isEndReached: isEndReached,
                                          updatedIds: updatedIds)

        await MainActor.run {
            self.activitiesById = activitiesById
            self.idsByDate = idsByDate
            self.isEndReached = isEndReached
            self.isEmpty = isEndReached == true && idsByDate?.isEmpty != false
            self.snapshot = snapshot
        }
        await delegate?.activityViewModelChanged()
    }

    private func makeSnapshot(idsByDate: OrderedDictionary<Date, [String]>?,
                              showFirstRow: Bool,
                              isEndReached: Bool?,
                              updatedIds: [String]) async -> NSDiffableDataSourceSnapshot<Section, Row> {
        let start = Date()
        defer { log.info("makeSnapshot: \(Date().timeIntervalSince(start))s")}
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.headerPlaceholder])
        snapshot.appendItems([.headerPlaceholder])

        if showFirstRow {
            snapshot.appendSections([.firstRow])
            snapshot.appendItems([.firstRow])
        }

        if let idsByDate {
            for (date, ids) in idsByDate {
                snapshot.appendSections([.transactions(accountId, date)])
                snapshot.appendItems(ids.map { Row.transaction(accountId, $0) } )
            }
        }
        if let idsByDate, !idsByDate.isEmpty, isEndReached != true {
            snapshot.appendItems([.loadingMore])
        }
        if let idsByDate, idsByDate.isEmpty {
            snapshot.appendSections([.emptyPlaceholder])
            snapshot.appendItems([.emptyPlaceholder])
        }

        let ids = Set(snapshot.itemIdentifiers.compactMap {
            if case .transaction(_, let id) = $0 {
                return id
            }
            return nil
        })
        let updatedIds = updatedIds.filter { ids.contains($0) }
        snapshot.reconfigureItems(updatedIds.map { Row.transaction(accountId, $0) })

        return snapshot
    }

    nonisolated public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .activitiesChanged(let accountId, let updatedIds, _):
            if accountId == self.accountId {
                await getState(updatedIds: updatedIds)
            }
        case .hideTinyTransfersChanged:
            await getState(updatedIds: [])
        default:
            break
        }
    }

    public func requestMoreIfNeeded() {
        guard loadMoreTask == nil else { return }
        loadMoreTask = Task {
            do {
                if let token {
                    try await activitiesStore.fetchTokenTransactions(accountId: accountId, limit: 60, token: token, shouldLoadWithBudget: true)
                } else {
                    try await activitiesStore.fetchAllTransactions(accountId: accountId, limit: 60, shouldLoadWithBudget: true)
                }
            } catch {
                log.info("requestMoreIfNeeded: \(error)")
            }
            self.loadMoreTask = nil
        }
    }
}

import UIKit
import OrderedCollections

struct ActivityListSnapshotProxy {
    typealias Section = ActivityListViewModel.Section
    typealias Row = ActivityListViewModel.Row

    struct ScrollActions {
        let shouldUpdateSnapshot: Bool
        let shouldRequestRemotePage: Bool
    }

    private let accountId: String
    private let customSectionIDs: [String]
    private let initialVisibleActivitiesCount: Int
    private let visibleGrowthStep: Int
    private let visibleGrowthThreshold: Int
    private let remoteLoadThreshold: Int

    private var visibleActivityCount = 0
    private var loadedActivityIds: [String] = []
    private var loadedIndexByStableId: [String: Int] = [:]

    init(
        accountId: String,
        customSectionIDs: [String],
        initialVisibleActivitiesCount: Int = 10,
        visibleGrowthStep: Int = 25,
        visibleGrowthThreshold: Int = 10,
        remoteLoadThreshold: Int = 20
    ) {
        self.accountId = accountId
        self.customSectionIDs = customSectionIDs
        self.initialVisibleActivitiesCount = initialVisibleActivitiesCount
        self.visibleGrowthStep = visibleGrowthStep
        self.visibleGrowthThreshold = visibleGrowthThreshold
        self.remoteLoadThreshold = remoteLoadThreshold
    }

    mutating func didUpdateData(idsByDate: OrderedDictionary<Date, [String]>?) {
        let previousLoadedCount = loadedActivityIds.count
        let previousVisibleCount = visibleActivityCount
        let wasShowingAllLoadedActivities = previousVisibleCount > 0 && previousVisibleCount == previousLoadedCount
        let nextLoadedIds = idsByDate?.values.flatMap { $0 } ?? []
        loadedActivityIds = nextLoadedIds
        loadedIndexByStableId = Dictionary(uniqueKeysWithValues: nextLoadedIds.enumerated().map { ($1, $0) })

        guard idsByDate != nil else {
            visibleActivityCount = 0
            return
        }

        guard !nextLoadedIds.isEmpty else {
            visibleActivityCount = 0
            return
        }

        if previousVisibleCount == 0 {
            updateVisibleActivityCount(
                min(initialVisibleActivitiesCount, nextLoadedIds.count)
            )
        } else if wasShowingAllLoadedActivities && nextLoadedIds.count > previousLoadedCount {
            updateVisibleActivityCount(
                min(previousVisibleCount + visibleGrowthStep, nextLoadedIds.count)
            )
        } else {
            updateVisibleActivityCount(
                min(previousVisibleCount, nextLoadedIds.count)
            )
        }
    }

    mutating func rowDidBecomeVisible(_ row: Row, isEndReached: Bool?) -> ScrollActions {
        let stableId: String? = switch row {
        case .transaction(_, let stableId):
            stableId
        default:
            nil
        }

        let shouldUpdateSnapshot = shouldGrowVisiblePrefix(for: stableId)
        if shouldUpdateSnapshot {
            updateVisibleActivityCount(
                min(visibleActivityCount + visibleGrowthStep, loadedActivityIds.count)
            )
        }

        return ScrollActions(
            shouldUpdateSnapshot: shouldUpdateSnapshot,
            shouldRequestRemotePage: shouldRequestRemotePage(for: row, stableId: stableId, isEndReached: isEndReached)
        )
    }

    mutating func scrollDidStop(lastVisibleRow: Row?) -> Bool {
        let stableId = stableId(for: lastVisibleRow)
        guard let stableId,
              let lastVisibleIndex = loadedIndexByStableId[stableId]
        else {
            return false
        }

        let targetVisibleCount = min(
            roundedUpToVisibleStep(lastVisibleIndex + 1),
            loadedActivityIds.count
        )
        guard targetVisibleCount < visibleActivityCount else {
            return false
        }

        updateVisibleActivityCount(targetVisibleCount)
        return true
    }

    func makeSnapshot(
        idsByDate: OrderedDictionary<Date, [String]>?,
        isEndReached: Bool?,
        updatedIds: [String]
    ) -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.headerPlaceholder])
        snapshot.appendItems([.headerPlaceholder])

        if !customSectionIDs.isEmpty {
            for customSectionID in customSectionIDs {
                let section = Section.custom(customSectionID)
                snapshot.appendSections([section])
                snapshot.appendItems([.custom(customSectionID)], toSection: section)
            }
        }

        if let idsByDate {
            var remainingActivities = visibleActivityCount
            for (date, ids) in idsByDate {
                guard remainingActivities > 0 else { break }
                let visibleIds = Array(ids.prefix(remainingActivities))
                guard !visibleIds.isEmpty else { continue }
                snapshot.appendSections([.transactions(accountId, date)])
                snapshot.appendItems(visibleIds.map { Row.transaction(accountId, $0) })
                remainingActivities -= visibleIds.count
            }
        } else {
            snapshot.appendSections([.placeholderTransactionsSection])
            snapshot.appendItems(ActivityListViewModel.placeholderTransactionRows)
        }

        if let idsByDate, idsByDate.isEmpty {
            snapshot.appendSections([.emptyPlaceholder])
            snapshot.appendItems([.emptyPlaceholder])
        } else if let idsByDate, !idsByDate.isEmpty, visibleActivityCount == loadedActivityIds.count, isEndReached != true {
            snapshot.appendItems([.loadingMore])
        }

        let visibleIds = Set(snapshot.itemIdentifiers.compactMap { row -> String? in
            if case .transaction(_, let stableId) = row {
                return stableId
            }
            return nil
        })
        let visibleUpdatedIds = updatedIds.filter { visibleIds.contains($0) }
        snapshot.reconfigureItems(visibleUpdatedIds.map { Row.transaction(accountId, $0) })

        return snapshot
    }

    private func shouldGrowVisiblePrefix(for stableId: String?) -> Bool {
        guard visibleActivityCount < loadedActivityIds.count,
              let stableId,
              let index = loadedIndexByStableId[stableId]
        else {
            return false
        }

        return index >= max(visibleActivityCount - visibleGrowthThreshold, 0)
    }

    private func shouldRequestRemotePage(for row: Row, stableId: String?, isEndReached: Bool?) -> Bool {
        guard isEndReached != true else {
            return false
        }

        if case .loadingMore = row {
            return true
        }

        guard let stableId,
              let index = loadedIndexByStableId[stableId]
        else {
            return false
        }

        return index >= max(loadedActivityIds.count - remoteLoadThreshold, 0)
    }

    private func stableId(for row: Row?) -> String? {
        guard let row else { return nil }
        if case .transaction(_, let stableId) = row {
            return stableId
        }
        return nil
    }

    private func roundedUpToVisibleStep(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let rounded = ((count - 1) / visibleGrowthStep + 1) * visibleGrowthStep
        return max(initialVisibleActivitiesCount, rounded)
    }

    private mutating func updateVisibleActivityCount(_ nextCount: Int) {
        visibleActivityCount = nextCount
    }
}

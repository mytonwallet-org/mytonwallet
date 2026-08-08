
import Foundation
import WalletContext
import OrderedCollections

func mergeActivityIdsToMaxTime(_ array1: [String], _ array2: [String], byId: [String: ApiActivity]) -> [String] {
    if array1.isEmpty && array2.isEmpty {
        return []
    } else if array1.isEmpty && !array2.isEmpty {
        return Set(array2) // TODO: workaround for backend bug: normally ids should be unique
            .sorted { idA, idB in
                compareActivityIds(idA, idB, byId: byId)
            }
    } else if array2.isEmpty && !array1.isEmpty {
        return Set(array1) // TODO: workaround for backend bug: normally ids should be unique
            .sorted { idA, idB in
                compareActivityIds(idA, idB, byId: byId)
            }
    }
    
    let timestamp1 = byId[array1.last!]?.timestamp ?? 0
    let timestamp2 = byId[array2.last!]?.timestamp ?? 0
    let fromTimestamp = max(timestamp1, timestamp2)
    
    let filteredIds = Set(array1 + array2)
        .filter { id in
            (byId[id]?.timestamp ?? 0) >= fromTimestamp
        }
        .sorted { idA, idB in
            compareActivityIds(idA, idB, byId: byId)
        }
    return filteredIds
}

func mergeSortedActivityIds(_ ids0: [String], _ ids1: [String], byId: [String: ApiActivity]) -> [String] {
    // Not the best performance, but ok for now
    return Set(ids0 + ids1)
        .sorted { id0, id1 in
            compareActivityIds(id0, id1, byId: byId)
        }
}

func _getNewestActivitiesBySlug(
    byId: [String: ApiActivity],
    idsBySlug: [String: [String]],
    newestActivitiesBySlug: [String: ApiActivity]?,
    tokenSlugs: any Sequence<String>
) -> [String: ApiActivity] {
    var newestActivitiesBySlug = newestActivitiesBySlug ?? [:]
    
    for tokenSlug in tokenSlugs {
        // The `idsBySlug` arrays must be sorted from the newest to the oldest
        let ids = idsBySlug[tokenSlug] ?? [];
        let newestActivityId = ids.first { id in
            getIsIdSuitableForFetchingTimestamp(activity: byId[id])
        }
        if let newestActivityId {
            newestActivitiesBySlug[tokenSlug] = byId[newestActivityId]
        } else {
            newestActivitiesBySlug[tokenSlug] = nil
        }
    }
    
    return newestActivitiesBySlug;
}

func getIsIdSuitableForFetchingTimestamp(activity: ApiActivity?) -> Bool {
    guard let activity else { return false }
    return !getIsIdLocal(activity.id) && !getIsBackendSwapId(activity.id) && activity.isCompleted
}

public func getIsActivityPending(_ activity: ApiActivity) -> Bool {
    if !getIsActivityPendingForUser(activity) {
        return false
    }
    switch activity {
    case .transaction:
        return true
    case .swap(let swap):
        // "Pending" is a blockchain term.
        // CEX activities are never considered pending, because they are originated by the backend instead of the blockchains.
        return !getIsBackendSwapId(swap.id)
    }
}

public func getIsActivityPendingForUser(_ activity: ApiActivity) -> Bool {
    switch activity {
    case .transaction(let tx):
        return tx.status == .pending || tx.status == .pendingTrusted
    case .swap(let swap):
        return swap.status == .pending || swap.status == .pendingTrusted
    }
}

func getIsIdLocal(_ id: String) -> Bool {
    id.hasSuffix(":local")
}

func getIsBackendSwapId(_ id: String) -> Bool {
    id.hasSuffix(":backend-swap")
}

func compareActivityIds(_ idA: String, _ idB: String, byId: [String: ApiActivity]) -> Bool {
    if let activityA = byId[idA], let activityB = byId[idB] {
        return activityA < activityB
    }
    assertionFailure("logic error")
    return idA > idB
}

func preserveActivityStatusProgress(existingActivity: ApiActivity?, incomingActivity: ApiActivity) -> ApiActivity {
    guard let existingActivity,
          existingActivity.kind == incomingActivity.kind,
          activityStatusRank(existingActivity) > activityStatusRank(incomingActivity) else {
        return incomingActivity
    }

    switch (existingActivity, incomingActivity) {
    case (.transaction(let existingTransaction), .transaction(var incomingTransaction)):
        incomingTransaction.status = existingTransaction.status
        return .transaction(incomingTransaction)
    case (.swap(let existingSwap), .swap(var incomingSwap)):
        incomingSwap.status = existingSwap.status
        return .swap(incomingSwap)
    default:
        return incomingActivity
    }
}

private func activityStatusRank(_ activity: ApiActivity) -> Int {
    switch activity {
    case .transaction(let transaction):
        switch transaction.status {
        case .pending:
            return 1
        case .pendingTrusted:
            return 2
        case .confirmed:
            return 3
        case .completed, .failed:
            return 4
        }
    case .swap(let swap):
        switch swap.status {
        case .pending:
            return 1
        case .pendingTrusted:
            return 2
        case .confirmed:
            return 3
        case .completed, .failed, .expired:
            return 4
        }
    }
}

func buildActivityIdsBySlug(_ activities: [ApiActivity]) -> [String: [String]] {
    return activities.reduce(into: [:]) { acc, activity in
        for slug in getActivityTokenSlugs(activity) {
            acc[slug, default: []].append(activity.id)
        }
    }
}

func getActivityTokenSlugs(_ activity: ApiActivity) -> [String] {
    switch activity {
    case .transaction(let tx):
        if tx.nft != nil {
            return [] // We don't want NFT activities to get into any token activity list
        }
        return [tx.slug]
    case .swap(let swap):
        return Array(OrderedSet([swap.fromTokenSlug, swap.toTokenSlug]))
    }
}

func getActivityListTokenSlugs(activityIds: Set<String>, byId: [String: ApiActivity]) -> Set<String> {
    var tokenSlugs = Set<String>()
    
    for id in activityIds {
        if let activity = byId[id] {
            for tokenSlug in getActivityTokenSlugs(activity) {
                tokenSlugs.insert(tokenSlug)
            }
        }
    }
    
    return tokenSlugs
}

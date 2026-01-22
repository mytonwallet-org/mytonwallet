
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
    switch activity {
    case .transaction(let tx):
        tx.status == .pending || tx.status == .pendingTrusted
    case .swap(let swap):
        // "Pending" is a blockchain term.
        // CEX activities are never considered pending, because they are originated by the backend instead of the blockchains.
        !getIsBackendSwapId(swap.id) && (swap.status == .pending || swap.status == .pendingTrusted)
    }
}

/**
 * Sometimes activity ids change. This function finds the new id withing `nextActivities` for each activity in
 * `prevActivities`. Currently only local and pending activity ids change, so it's enough to provide only such
 * activities in `prevActivities`.
 *
 * The ids should be unique within each input array. The returned map has previous activity ids as keys and next
 * activity ids as values. If the map has no value for a previous id, it means that there is no matching next activity.
 * The values may be not unique.
 */
func getActivityIdReplacements(prevActivities: [ApiActivity], nextActivities: [ApiActivity]) -> [String: String] {
    // Each previous activity must fall into either of the groups, otherwise the resulting map will falsely miss previous ids
    var prevLocalActivities: [ApiActivity] = []
    var prevChainActivities: [ApiActivity] = []
    
    for activity in prevActivities {
        if getIsIdLocal(activity.id) {
            prevLocalActivities.append(activity)
        } else {
            prevChainActivities.append(activity)
        }
    }
    
    let localReplacements = getLocalActivityIdReplacements(prevLocalActivities, nextActivities)
    let chainReplacements = getChainActivityIdReplacements(prevChainActivities, nextActivities)
    return localReplacements.merging(chainReplacements, uniquingKeysWith: { $1 })
}

/** Replaces local activity ids. See `getActivityIdReplacements` for more details. */
func getLocalActivityIdReplacements(_ prevLocalActivities: [ApiActivity], _ nextActivities: [ApiActivity]) -> [String: String] {
    if prevLocalActivities.isEmpty {
        return [:]
    }

    var idReplacements: [String: String] = [:]

    let nextActivityIds = Set(nextActivities.map(\.id))
    let nextChainActivities = nextActivities.filter { !getIsIdLocal($0.id) }
    
    for localActivity in prevLocalActivities {
        let prevId = localActivity.id
        
        // Try a direct id match
        if nextActivityIds.contains(prevId) {
            idReplacements[prevId] = prevId
            continue
        }
        
        // Otherwise, try to find a match by a heuristic
        let chainActivity = nextChainActivities.first { chainActivity in
            return doesLocalActivityMatch(localActivity: localActivity, chainActivity: chainActivity)
        }
        if let chainActivity {
            idReplacements[prevId] = chainActivity.id
        }
        
        // Otherwise, there is no match
    }
    
    return idReplacements
}

/** Replaces chain (i.e. not local) activity ids. See `getActivityIdReplacements` for more details. */
func getChainActivityIdReplacements(_ prevActivities: [ApiActivity], _ nextActivities: [ApiActivity]) -> [String: String] {
    if prevActivities.isEmpty {
        return [:]
    }

    var idReplacements: [String: String] = [:]
    
    let nextActivityIds = Set(nextActivities.map(\.id))
    var nextActivitiesByMessageHash = Dictionary(grouping: nextActivities, by: \.externalMsgHashNorm);
    
    for activity in prevActivities {
        let prevId = activity.id
        let externalMsgHashNormNorm = activity.externalMsgHashNorm
        
        // Try a direct id match
        if nextActivityIds.contains(prevId) {
            idReplacements[prevId] = prevId
            continue
        }
        
        // Otherwise, match by the message hash
        if let externalMsgHashNormNorm {
            if let nextSubActivities = nextActivitiesByMessageHash[externalMsgHashNormNorm], !nextSubActivities.isEmpty {
                idReplacements[prevId] = nextSubActivities[0].id
                
                // Leaving 1 activity in each group to ensure there is a match for the further prev activities with the same hash
                if nextSubActivities.count > 1 {
                    nextActivitiesByMessageHash[externalMsgHashNormNorm] = Array(nextSubActivities.dropFirst())
                }
            }
        }
        
        // Otherwise, there is no match
    }
    
    return idReplacements;
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

/** Decides whether the local activity matches the activity from the blockchain */
public func doesLocalActivityMatch(localActivity: ApiActivity, chainActivity: ApiActivity) -> Bool {
    
    if localActivity.extra?.withW5Gasless == true {
        if let localActivity = localActivity.transaction, let chainActivity = chainActivity.transaction {
            return !chainActivity.isIncoming && localActivity.normalizedAddress == chainActivity.normalizedAddress
            && localActivity.amount == chainActivity.amount
            && localActivity.slug == chainActivity.slug
        } else if let localActivity = localActivity.swap, let chainActivity = chainActivity.swap {
            return localActivity.from == chainActivity.from
            && localActivity.to == chainActivity.to
            && localActivity.fromAmount == chainActivity.fromAmount
        }
    }
    
    if let localActivityexternalMsgHashNorm = localActivity.externalMsgHashNorm {
        return localActivityexternalMsgHashNorm == chainActivity.externalMsgHashNorm && chainActivity.shouldHide != true
    }
    
    return localActivity.parsedTxId.hash == chainActivity.parsedTxId.hash
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
        return [swap.from, swap.to]
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

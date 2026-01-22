
import GRDB
import Foundation
import WalletContext
import OrderedCollections

private let log = Log("ActivityStore")
private let TX_AGE_TO_PLAY_SOUND = 60.0 // 1 min

public let ActivityStore = _ActivityStore.shared

public actor _ActivityStore: WalletCoreData.EventsObserver {
    
    public static let shared = _ActivityStore()
    
    // MARK: Data
    
    struct AccountState: Equatable, Hashable, Codable, FetchableRecord, PersistableRecord {
        var accountId: String
        var byId: [String: ApiActivity]?
        /**
         * The array values are sorted by the activity type (newest to oldest).
         * Undefined means that the activities haven't been loaded, [] means that there are no activities.
         */
        var idsMain: [String]?
        /** The record values follow the same rules as `idsMain` */
        var idsBySlug: [String: [String]]?
        var newestActivitiesBySlug: [String: ApiActivity]?
        var isMainHistoryEndReached: Bool?
        var isHistoryEndReachedBySlug: [String: Bool]?
        var localActivityIds: [String]?
        /** By chain. Doesn't include the local activities */
        var pendingActivityIds: [String: [String]]?
        /**
         * May be false when the actual activities are actually loaded (when the app has been loaded from the cache).
         * The initial activities should be considered loaded if `idsMain` is not undefined.
         */
        var isInitialLoadedByChain: [String: Bool]?

        static var databaseTableName: String = "account_activities"
    }
    
    private var byAccountId: [String: AccountState] = [:]
    
    private func withAccountState<T>(_ accountId: String, updates: (inout AccountState) -> T) -> T {
        defer { save(accountId: accountId) }
        return updates(&byAccountId[accountId, default: .init(accountId: accountId)])
    }
    
    func getAccountState(_ accountId: String) -> AccountState {
        byAccountId[accountId, default: .init(accountId: accountId)]
    }
    
    private var poisoningCacheById: [String: PoisoningCache] = [:]
    
    func getPoisoningCache(_ accountId: String) -> PoisoningCache {
        poisoningCacheById[accountId, default: PoisoningCache()]
    }
    
    private var _db: (any DatabaseWriter)?
    private var db: any DatabaseWriter {
        get throws {
            try _db.orThrow("database not ready")
        }
    }
    
    private var accountIdsObserver: Task<Void, Never>?
    
    private var notifiedIds: Set<String> = []
    
    private var lastApplicationWillEnterForeground: Date
    private var timeSinceLastApplicationWillEnterForeground: Double { Date.now.timeIntervalSince(lastApplicationWillEnterForeground)}
    
    // MARK: - Event handling
    
    private init() {
        // event observer will be added after cache is loaded
        lastApplicationWillEnterForeground = .now
    }
    
    nonisolated public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }
    
    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .initialActivities(let update):
            handleInitialActivities(update: update)
        case .newActivities(let update):
            handleNewActivities(update: update)
        case .newLocalActivity(let update):
            handleNewLocalActivities(update: update)
        default:
            break
        }
    }
    
    private func handleInitialActivities(update: ApiUpdate.InitialActivities) {
        log.info("handleInitialActivities \(update.accountId, .public) mainIds=\(update.mainActivities.count)")
        addInitialActivities(accountId: update.accountId, mainActivities: update.mainActivities, bySlug: update.bySlug)
        let allActivities = update.mainActivities + update.bySlug.values.flatMap { $0 }
        updatePoisoningCache(accountId: update.accountId, activities: allActivities)
        if let chain = update.chain {
            setIsInitialActivitiesLoadedTrue(accountId: update.accountId, chain: chain);
        }
        WalletCoreData.notify(event: .activitiesChanged(accountId: update.accountId, updatedIds: [], replacedIds: [:]))
        log.info("handleInitialActivities \(update.accountId, .public) [done] mainIds=\(update.mainActivities.count)")
    }
    
    private func handleNewActivities(update: ApiUpdate.NewActivities) {
        log.info("handleNewActivities \(update.accountId, .public) sinceForeground=\(timeSinceLastApplicationWillEnterForeground) mainIds=\(getAccountState(update.accountId).idsMain?.count ?? -1) inUpdate=\(update.activities.count)")
        
        let accountId = update.accountId
        let newConfirmedActivities = update.activities
        let pendingActivities = filterPendingActivities(accountId: accountId, pendingActivities: update.pendingActivities)
        let allNewActivities = (pendingActivities ?? []) + newConfirmedActivities
        
        var prevActivities = selectLocalActivitiesSlow(accountId: accountId) ?? []
        if let chain = update.chain {
            prevActivities += selectPendingActivitiesSlow(accountId: accountId, chain: chain) ?? []
        }
        
        let replacedIds = getActivityIdReplacements(
            prevActivities: prevActivities,
            nextActivities: allNewActivities
        )
        let adjustedPendingActivities = adjustPendingActivitiesWithTrustedStatus(
            pendingActivities: pendingActivities,
            replacedIds: replacedIds,
            prevActivities: prevActivities
        )
        
        // A good TON address for testing: UQD5mxRgCuRNLxKxeOjG6r14iSroLF5FtomPnet-sgP5xI-e
        removeActivities(accountId: accountId, deleteIds: Array(replacedIds.keys))
        if let chain = update.chain,  let pendingActivities = adjustedPendingActivities {
            if let oldIds = getAccountState(accountId).pendingActivityIds?[chain.rawValue] {
                removeActivities(accountId: accountId, deleteIds: oldIds)
            }
            addNewActivities(accountId: accountId, newActivities: pendingActivities, chain: chain)
        }
        
        addNewActivities(accountId: accountId, newActivities: newConfirmedActivities, chain: nil)
        updatePoisoningCache(accountId: accountId, activities: newConfirmedActivities)
        
        notifyAboutNewActivities(accountId: accountId, newActivities: allNewActivities)
        
        // TODO: Copy from web app: processCardMintingActivity
        // NFT polling is executed at long intervals, so it is more likely that a user will see a new transaction
        // rather than receiving a card in the collection. Therefore, when a new activity occurs,
        // we check for a card from the MyTonWallet collection and apply it.
        //        global = processCardMintingActivity(global, accountId, incomingActivities);
        
        if let chain = update.chain {
            setIsInitialActivitiesLoadedTrue(accountId: accountId, chain: chain);
        }
        WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: unique((adjustedPendingActivities ?? []).map(\.id) + newConfirmedActivities.map(\.id)), replacedIds: replacedIds))
        log.info("handleNewActivities \(accountId, .public) [done] mainIds=\(getAccountState(accountId).idsMain?.count ?? -1) inUpdate=\(update.activities.count)")
    }
    
    private func handleNewLocalActivities(update: ApiUpdate.NewLocalActivities) {
        log.info("newLocalActivity \(update.accountId, .public)")
        let activities = hideOutdatedLocalActivities(accountId: update.accountId, localActivities: update.activities)
        let maxDepth = activities.count + 20
        let chainActivities = selectRecentNonLocalActivitiesSlow(accountId: update.accountId, count: maxDepth) ?? []
        let replacedIds = getActivityIdReplacements(prevActivities: activities, nextActivities: chainActivities)
        let updatedPendingIds = updatePendingActivitiesToTrustedByReplacements(accountId: update.accountId, localActivities: activities, replacedIds: replacedIds)
        addNewActivities(accountId: update.accountId, newActivities: activities, chain: nil)
        WalletCoreData.notify(event: .activitiesChanged(accountId: update.accountId, updatedIds: unique(activities.map(\.id) + updatedPendingIds), replacedIds: [:]))
    }

    // MARK: - Fetch methods
    
    func fetchAllActivities(accountId: String, limit: Int, shouldLoadWithBudget: Bool) async throws {
        
        var toTimestamp = selectLastMainTxTimestamp(accountId: accountId)
        var fetchedActivities: [ApiActivity] = []
        
        while true {
            let result = try await Api.fetchPastActivities(accountId: accountId, limit: limit, tokenSlug: nil, toTimestamp: toTimestamp)
            if result.isEmpty {
                updateActivitiesIsHistoryEndReached(accountId: accountId, slug: nil, isReached: true)
                break
            }
            let poisoningCache = getPoisoningCache(accountId)
            updatePoisoningCache(accountId: accountId, activities: result)
            let hideTinyTransfers = AppStorageHelper.hideTinyTransfers
            let filteredResult = result.filter {
                guard case .transaction(let transaction) = $0 else { return true }
                if hideTinyTransfers && $0.isTinyOrScamTransaction {
                    return false
                }
                return !poisoningCache.isTransactionWithPoisoning(transaction: transaction)
            }
            fetchedActivities.append(contentsOf: result)
            if filteredResult.count >= 1 && fetchedActivities.count >= limit {
                break
            }
            toTimestamp = result.last!.timestamp
        }
        
        fetchedActivities.sort(by: <)
        
        let accountState = getAccountState(accountId)
        var byId = accountState.byId ?? [:]
        var newIds: [String] = []
        for activity in fetchedActivities {
            // TODO: remove temporary workaround
            if activity.type == .callContract && byId[activity.id] != nil {
                continue
            }
            byId[activity.id] = activity
            newIds.append(activity.id)
        }
        
        var idsMain = Array(OrderedSet(
            (accountState.idsMain ?? []) + newIds
        ))
        idsMain.sort {
            compareActivityIds($0, $1, byId: byId)
        }
        
        withAccountState(accountId) {
            $0.byId = byId
            $0.idsMain = idsMain
        }
        
        log.info("[inf] got new ids: \(newIds.count)")
        WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: [], replacedIds: [:]))
        
        if shouldLoadWithBudget {
            await Task.yield()
            try await fetchAllActivities(accountId: accountId, limit: limit, shouldLoadWithBudget: false)
        }
    }
    
    func fetchTokenActivities(accountId: String, limit: Int, token: ApiToken, shouldLoadWithBudget: Bool) async throws {
        var accountState = getAccountState(accountId)
        var idsBySlug = accountState.idsBySlug ?? [:]
        var byId = accountState.byId ?? [:]
        
        var fetchedActivities: [ApiActivity] = []
        var tokenIds = idsBySlug[token.slug] ?? []
        var toTimestamp = tokenIds
            .last(where: { getIsIdSuitableForFetchingTimestamp(activity: byId[$0]) })
            .flatMap { id in byId[id]?.timestamp }
        
        while true {
            let result = try await Api.fetchPastActivities(accountId: accountId, limit: limit, tokenSlug: token.slug, toTimestamp: toTimestamp)
            if result.isEmpty {
                updateActivitiesIsHistoryEndReached(accountId: accountId, slug: token.slug, isReached: true)
                break
            }
            let poisoningCache = getPoisoningCache(accountId)
            updatePoisoningCache(accountId: accountId, activities: result)
            let hideTinyTransfers = AppStorageHelper.hideTinyTransfers
            let filteredResult = result.filter {
                guard case .transaction(let transaction) = $0 else { return true }
                if hideTinyTransfers && $0.isTinyOrScamTransaction {
                    return false
                }
                return !poisoningCache.isTransactionWithPoisoning(transaction: transaction)
            }
            fetchedActivities.append(contentsOf: result)
            if filteredResult.count >= 1 && fetchedActivities.count >= limit {
                break
            }
            toTimestamp = result.last!.timestamp
        }
        
        fetchedActivities.sort(by: <)
        
        accountState = getAccountState(accountId)
        byId = getAccountState(accountId).byId ?? [:]
        var newIds: [String] = []
        for activity in fetchedActivities {
            // TODO: remove temporary workaround
            if activity.type == .callContract && byId[activity.id] != nil {
                continue
            }
            byId[activity.id] = activity
            newIds.append(activity.id)
        }
        
        idsBySlug = accountState.idsBySlug ?? [:]
        
        tokenIds = Array(OrderedSet(
            tokenIds + newIds
        ))
        tokenIds.sort {
            compareActivityIds($0, $1, byId: byId)
        }
        idsBySlug = accountState.idsBySlug ?? [:]
        idsBySlug[token.slug] = tokenIds
        
        withAccountState(accountId) {
            $0.byId = byId
            $0.idsBySlug = idsBySlug
        }
        
        log.info("[inf] got new ids \(token.slug): \(newIds.count)")
        WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: [], replacedIds: [:]))
        
        if shouldLoadWithBudget {
            await Task.yield()
            try await fetchTokenActivities(accountId: accountId, limit: limit, token: token, shouldLoadWithBudget: false)
        }
    }
    
    // MARK: - Poisoning cache
    
    func updatePoisoningCache(accountId: String, activities: some Collection<ApiActivity>) {
        var cache = self.poisoningCacheById[accountId, default: PoisoningCache()]
        cache.update(activities: activities)
        self.poisoningCacheById[accountId] = cache
    }

    public func isTransactionWithPoisoning(accountId: String, transaction: ApiTransactionActivity) -> Bool {
        let cache = poisoningCacheById[accountId, default: PoisoningCache()]
        return cache.isTransactionWithPoisoning(transaction: transaction)
    }
    
    // MARK: - Activity details
    
    public func getActivity(accountId: String, activityId: String) -> ApiActivity? {
        getAccountState(accountId).byId?[activityId]
    }
    
    public func fetchActivityDetails(accountId: String, activity: ApiActivity) async throws -> ApiActivity {
        let activity = try await Api.fetchActivityDetails(accountId: accountId, activity: activity)
        withAccountState(accountId) {
            var byId = $0.byId ?? [:]
            // TODO: remove temporary workaround
            if activity.type == .callContract && byId[activity.id] != nil {
                return
            }
            byId[activity.id] = activity
            $0.byId = byId
        }
        WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: [activity.id], replacedIds: [:]))
        return activity
    }
    
    // MARK: - Persistence
    
    func use(db: any DatabaseWriter) {
        self._db = db
        do {
            let accountStates = try db.read { db in
                try AccountState.fetchAll(db)
            }
            updateFromDb(accountStates: accountStates)
            
            let observation = ValueObservation.tracking { db in
                try String.fetchAll(db, sql: "SELECT accountId FROM account_activities")
            }
            accountIdsObserver = Task { [weak self] in
                do {
                    for try await accountIds in observation.values(in: db) {
                        await self?.updateFromDb(accountIds: accountIds)
                    }
                } catch {
                    log.error("accountIdsObserver: \(error, .public)")
                }
            }
        } catch {
            log.error("accountStates intial load: \(error, .public)")
        }
        WalletCoreData.add(eventObserver: self)
    }
    
    private func updateFromDb(accountStates: [AccountState]) {
        log.info("updateFromDb accounts=\(accountStates.count)")
        let newByAccountId = accountStates.dictionaryByKey(\.accountId)
        let oldByAccountId = self.byAccountId
        self.byAccountId = newByAccountId
        for (accountId, newAccountState) in newByAccountId {
            if oldByAccountId[accountId] != newAccountState {
                if let activities = newAccountState.byId?.values {
                    updatePoisoningCache(accountId: accountId, activities: activities)
                }
                WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: [], replacedIds: [:]))
            }
        }
    }
    
    private func updateFromDb(accountIds: [String]) {
        let deletedKeys = Set(byAccountId.keys).subtracting(accountIds)
        for deletedKey in deletedKeys {
            byAccountId[deletedKey] = nil
            poisoningCacheById[deletedKey] = nil
        }
    }
    
    func getNewestActivityTimestamps(accountId: String) -> [String: Int64]? {
        getAccountState(accountId).newestActivitiesBySlug?.mapValues(\.timestamp)
    }
    
    private func save(accountId: String) {
        do {
            let accountState = getAccountState(accountId)
            try db.write { db in
                try accountState.upsert(db)
            }
        } catch {
            log.error("save error: \(error, .public)")
        }
    }
    
    func clean() {
        byAccountId = [:]
        poisoningCacheById = [:]
        do {
            _ = try db.write { db in
                try AccountState.deleteAll(db)
            }
        } catch {
            log.error("clean failed: \(error)")
        }
    }
    
    public func debugOnly_clean() {
        clean()
    }
    
    // MARK: - Impl
    
    /**
     Used for the initial activities insertion into `global`.
     Token activity IDs will just be replaced.
     */
    private func addInitialActivities(accountId: String, mainActivities: [ApiActivity], bySlug: [String: [ApiActivity]]) {
        
        let currentState = getAccountState(accountId)
        
        var byId = currentState.byId ?? [:]
        let allActivities = mainActivities + bySlug.values.flatMap { $0 }
        for activity in allActivities {
            // TODO: remove temporary workaround
            if activity.type == .callContract && byId[activity.id] != nil {
                continue
            }
            byId[activity.id] = activity
        }
        
        // Activities from different blockchains arrive separately, which causes the order to be disrupted
        let idsMain = mergeActivityIdsToMaxTime(mainActivities.map(\.id), currentState.idsMain ?? [], byId: byId)
        
        var idsBySlug = currentState.idsBySlug ?? [:]
        let newIdsBySlug = bySlug.mapValues { $0.map(\.id) }
        for (slug, ids) in newIdsBySlug {
            idsBySlug[slug] = ids
        }
        
        let newestActivitiesBySlug = _getNewestActivitiesBySlug(byId: byId, idsBySlug: idsBySlug, newestActivitiesBySlug: currentState.newestActivitiesBySlug, tokenSlugs: newIdsBySlug.keys)
        
        withAccountState(accountId) {
            $0.byId = byId
            $0.idsMain = idsMain
            $0.idsBySlug = idsBySlug
            $0.newestActivitiesBySlug = newestActivitiesBySlug
        }
    }
    
    /**
     * Should be used to add only newly created activities. Otherwise, there can occur gaps in the history, because the
     * given activities are added to all the matching token histories.
     */
    /// `chain` is necessary when adding pending activities
    private func addNewActivities(accountId: String, newActivities: [ApiActivity], chain: ApiChain?) {
        if newActivities.isEmpty {
            return
        }
        
        let currentState = getAccountState(accountId)
        
        var byId = currentState.byId ?? [:]
        for activity in newActivities {
            if let existingActivity = byId[activity.id],
               isNonPendingActivity(existingActivity),
               getIsActivityPending(activity) {
                log.error("activity status regression id=\(activity.id, .public) oldStatus=\(activityStatusString(existingActivity), .public) newStatus=\(activityStatusString(activity), .public) oldHash=\(activityHash(existingActivity), .public) newHash=\(activityHash(activity), .public)")
            }
            // TODO: remove temporary workaround
            if activity.type == .callContract && byId[activity.id] != nil {
                continue
            }
            byId[activity.id] = activity
        }
        
        // Activities from different blockchains arrive separately, which causes the order to be disrupted
        let idsMain = mergeSortedActivityIds(newActivities.map(\.id), currentState.idsMain ?? [], byId: byId)
        
        var idsBySlug = currentState.idsBySlug ?? [:]
        let newIdsBySlug = buildActivityIdsBySlug(newActivities)
        for (slug, newIds) in newIdsBySlug {
            let mergedIds = mergeSortedActivityIds(newIds, currentState.idsBySlug?[slug] ?? [], byId: byId)
            idsBySlug[slug] = mergedIds
        }
        
        let newestActivitiesBySlug = _getNewestActivitiesBySlug(byId: byId, idsBySlug: idsBySlug, newestActivitiesBySlug: currentState.newestActivitiesBySlug, tokenSlugs: newIdsBySlug.keys)
        
        let oldLocalIds = currentState.localActivityIds ?? []
        let newLocalIds = newActivities.filter { getIsIdLocal($0.id) }.map(\.id)
        let localActivityIds = Array(Set(oldLocalIds + newLocalIds))
        
        var pendingIds: [String: [String]] = currentState.pendingActivityIds ?? [:]
        if let chain {
            let oldPendingIds = currentState.pendingActivityIds?[chain.rawValue] ?? []
            let newPendingIds = newActivities.filter { getIsActivityPending($0) && !getIsIdLocal($0.id) }.map(\.id)
            let pendingIdsForChain = Array(Set(oldPendingIds + newPendingIds))
            pendingIds[chain.rawValue] = pendingIdsForChain
        }
        
        withAccountState(accountId) {
            $0.byId = byId
            $0.idsMain = idsMain
            $0.idsBySlug = idsBySlug
            $0.newestActivitiesBySlug = newestActivitiesBySlug
            $0.localActivityIds = localActivityIds
            if chain != nil {
                $0.pendingActivityIds = pendingIds
            }
        }
    }
    
    private func setIsInitialActivitiesLoadedTrue(accountId: String, chain: ApiChain) {
        withAccountState(accountId) {
            var isInitialLoadedByChain = $0.isInitialLoadedByChain ?? [:]
            isInitialLoadedByChain[chain.rawValue] = true
            $0.isInitialLoadedByChain = isInitialLoadedByChain
        }
    }
    
    private func selectLocalActivitiesSlow(accountId: String) -> [ApiActivity]? {
        if let state = byAccountId[accountId], let localIds = state.localActivityIds, let byId = state.byId {
            return localIds.compactMap { byId[$0] }
        }
        return nil
    }
    
    private func selectPendingActivitiesSlow(accountId: String, chain: ApiChain) -> [ApiActivity]? {
        if let state = byAccountId[accountId], let pendingIds = state.pendingActivityIds?[chain.rawValue], let byId = state.byId {
            return pendingIds.compactMap { byId[$0] }
        }
        return nil
    }
    
    private func selectRecentNonLocalActivitiesSlow(accountId: String, count: Int) -> [ApiActivity]? {
        guard let state = byAccountId[accountId], let mainIds = state.idsMain, let byId = state.byId else {
            return nil
        }
        var result: [ApiActivity] = []
        for id in mainIds {
            if result.count >= count {
                break
            }
            if getIsIdLocal(id) {
                continue
            }
            if let activity = byId[id] {
                result.append(activity)
            }
        }
        return result
    }

    
    private func removeActivities(accountId: String, deleteIds: [String]) {
        let currentState = getAccountState(accountId)
        let deleteIds = Set(deleteIds)
        guard !deleteIds.isEmpty else { return }
        
        let affectedTokenSlugs = getActivityListTokenSlugs(activityIds: deleteIds, byId: currentState.byId ?? [:])
        
        var idsBySlug = currentState.idsBySlug ?? [:]
        for tokenSlug in affectedTokenSlugs {
            if let idsForSlug = idsBySlug[tokenSlug] {
                idsBySlug[tokenSlug] = idsForSlug.filter { !deleteIds.contains($0) }
            }
        }
        
        let newestActivitiesBySlug = _getNewestActivitiesBySlug(byId: currentState.byId ?? [:], idsBySlug: idsBySlug, newestActivitiesBySlug: currentState.newestActivitiesBySlug, tokenSlugs: affectedTokenSlugs)
        
        let idsMain = currentState.idsMain?.filter { !deleteIds.contains($0) }
        
        let byId = currentState.byId?.filter { id, _ in !deleteIds.contains(id) }
        
        let localActivityIds = currentState.localActivityIds?.filter { !deleteIds.contains($0) }
        
        let pendingActivityIds = currentState.pendingActivityIds?.mapValues { oldPendingIds in
            oldPendingIds.filter { !deleteIds.contains($0) }
        }
        
        withAccountState(accountId) {
            $0.byId = byId
            $0.idsMain = idsMain
            $0.idsBySlug = idsBySlug
            $0.newestActivitiesBySlug = newestActivitiesBySlug
            $0.localActivityIds = localActivityIds
            $0.pendingActivityIds = pendingActivityIds
        }
    }

    private func filterPendingActivities(accountId: String, pendingActivities: [ApiActivity]?) -> [ApiActivity]? {
        guard let pendingActivities else { return nil }
        if pendingActivities.isEmpty {
            return pendingActivities
        }
        let byId = getAccountState(accountId).byId ?? [:]
        if byId.isEmpty {
            return pendingActivities
        }
        var nonPendingIds = Set<String>()
        var nonPendingHashes = Set<String>()
        for (id, activity) in byId {
            guard isNonPendingActivity(activity) else { continue }
            nonPendingIds.insert(id)
            let hash = activity.externalMsgHashNorm ?? activity.parsedTxId.hash
            nonPendingHashes.insert(hash)
        }
        return pendingActivities.filter { activity in
            if activity.isConfirmedOrCompleted {
                return true
            }
            if nonPendingIds.contains(activity.id) {
                log.error("pending activity filtered due to non-pending id match id=\(activity.id, .public) status=\(activityStatusString(activity), .public) hash=\(activityHash(activity), .public)")
                return false
            }
            let hash = activity.externalMsgHashNorm ?? activity.parsedTxId.hash
            if nonPendingHashes.contains(hash) {
                log.error("pending activity filtered due to non-pending hash match id=\(activity.id, .public) status=\(activityStatusString(activity), .public) hash=\(activityHash(activity), .public)")
                return false
            }
            return true
        }
    }

    private func isNonPendingActivity(_ activity: ApiActivity) -> Bool {
        return !activity.isLocal && !getIsActivityPending(activity)
    }

    private func activityHash(_ activity: ApiActivity) -> String {
        return activity.externalMsgHashNorm ?? activity.parsedTxId.hash
    }

    private func activityStatusString(_ activity: ApiActivity) -> String {
        switch activity {
        case .transaction(let transaction):
            return transaction.status.rawValue
        case .swap(let swap):
            return swap.status.rawValue
        }
    }

    private func updatePendingActivitiesToTrustedByReplacements(accountId: String, localActivities: [ApiActivity], replacedIds: [String: String]) -> [String] {
        guard !localActivities.isEmpty, !replacedIds.isEmpty else { return [] }
        var byId = getAccountState(accountId).byId ?? [:]
        var updatedIds: [String] = []
        for localActivity in localActivities {
            guard localActivity.isPendingTrusted,
                  let chainActivityId = replacedIds[localActivity.id],
                  let chainActivity = byId[chainActivityId],
                  let updatedActivity = makePendingTrustedActivity(chainActivity) else { continue }
            byId[chainActivityId] = updatedActivity
            updatedIds.append(chainActivityId)
        }
        if !updatedIds.isEmpty {
            withAccountState(accountId) {
                $0.byId = byId
            }
        }
        return updatedIds
    }

    private func adjustPendingActivitiesWithTrustedStatus(
        pendingActivities: [ApiActivity]?,
        replacedIds: [String: String],
        prevActivities: [ApiActivity]
    ) -> [ApiActivity]? {
        guard let pendingActivities else { return nil }
        if pendingActivities.isEmpty || replacedIds.isEmpty || prevActivities.isEmpty {
            return pendingActivities
        }
        var reversedReplacedIds: [String: String] = [:]
        for (oldId, newId) in replacedIds {
            reversedReplacedIds[newId] = oldId
        }
        let prevById = prevActivities.dictionaryByKey(\.id)
        return pendingActivities.map { activity in
            guard let oldId = reversedReplacedIds[activity.id],
                  let oldActivity = prevById[oldId],
                  oldActivity.isPendingTrusted,
                  let updatedActivity = makePendingTrustedActivity(activity) else { return activity }
            return updatedActivity
        }
    }

    private func makePendingTrustedActivity(_ activity: ApiActivity) -> ApiActivity? {
        var activity = activity
        switch activity {
        case .transaction(var transaction):
            guard transaction.status == .pending else { return nil }
            transaction.status = .pendingTrusted
            activity = .transaction(transaction)
        case .swap(var swap):
            guard swap.status == .pending else { return nil }
            swap.status = .pendingTrusted
            activity = .swap(swap)
        }
        return activity
    }
    
    private func hideOutdatedLocalActivities(accountId: String, localActivities: [ApiActivity]) -> [ApiActivity] {
        let maxDepth = localActivities.count + 20
        let chainActivities = selectRecentNonLocalActivitiesSlow(accountId: accountId, count: maxDepth) ?? []

        return localActivities.map { localActivity in
            var localActivity = localActivity
            
            if localActivity.shouldHide != true {
                for chainActivity in chainActivities {
                    if doesLocalActivityMatch(localActivity: localActivity, chainActivity: chainActivity) {
                        localActivity.shouldHide = true
                        break
                    }
                }
            }
            
            return localActivity
        }
    }
    
    private func selectLastMainTxTimestamp(accountId: String) -> Int64? {
        let activities = getAccountState(accountId)
        let txId = activities.idsMain?.last { id in
            getIsIdSuitableForFetchingTimestamp(activity: activities.byId?[id])
        }
        if let txId {
            return activities.byId?[txId]?.timestamp
        }
        return nil
    }
    
    private func updateActivitiesIsHistoryEndReached(accountId: String, slug: String?, isReached: Bool) {
        withAccountState(accountId) {
            if let slug {
                var isHistoryEndReachedBySlug = $0.isHistoryEndReachedBySlug ?? [:]
                isHistoryEndReachedBySlug[slug] = isReached
                $0.isHistoryEndReachedBySlug = isHistoryEndReachedBySlug
            } else {
                $0.isMainHistoryEndReached = isReached
            }
        }
    }
    
    private func notifyAboutNewActivities(accountId: String, newActivities: [ApiActivity]) {
        for activity in newActivities {
            if !activity.isConfirmedOrCompleted {
                continue
            }
            switch activity {
            case .transaction(let tx):
                if tx.isIncoming,
                   Date.now.timeIntervalSince(activity.timestampDate) < TX_AGE_TO_PLAY_SOUND,
                   !(AppStorageHelper.hideTinyTransfers && activity.isTinyOrScamTransaction),
                   !getPoisoningCache(accountId).isTransactionWithPoisoning(transaction: tx),
                   AppStorageHelper.sounds,
                   WalletContextManager.delegate?.isAppUnlocked == true,
                   !notifiedIds.contains(activity.id)
                {
                    log.info("notifying about tx: \(activity.id, .public)")
                    AudioHelpers.play(sound: .incomingTransaction)
                    break
                }
            case .swap:
                break
            }
            notifiedIds.insert(activity.id)
        }
    }
}

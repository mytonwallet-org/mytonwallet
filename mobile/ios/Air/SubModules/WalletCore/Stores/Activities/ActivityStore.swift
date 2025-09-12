
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
            await handleNewLocalActivities(update: update)
//        case .applicationWillEnterForeground:
//            await handleApplicationWillEnterForeground()
        default:
            break
        }
    }
    
    private func handleInitialActivities(update: ApiUpdate.InitialActivities) {
        log.info("handleInitialActivities \(update.accountId, .public) mainIds=\(update.mainActivities.count)")
        addInitialActivities(accountId: update.accountId, mainActivities: update.mainActivities, bySlug: update.bySlug);
        if let chain = update.chain {
            setIsInitialActivitiesLoadedTrue(accountId: update.accountId, chain: chain);
        }
        WalletCoreData.notify(event: .activitiesChanged(accountId: update.accountId, updatedIds: [], replacedIds: [:]))
        log.info("handleInitialActivities \(update.accountId, .public) [done] mainIds=\(update.mainActivities.count)")
    }
    
    private func handleNewActivities(update: ApiUpdate.NewActivities, forceReload: Bool = false) {
        log.info("handleNewActivities \(update.accountId, .public) sinceForeground=\(timeSinceLastApplicationWillEnterForeground) forceReload=\(forceReload) mainIds=\(getAccountState(update.accountId).idsMain?.count ?? -1) inUpdate=\(update.activities.count)")
        
        let accountId = update.accountId
        let newConfirmedActivities = update.activities
        let pendingActivities = update.pendingActivities
        
        var prevActivities = selectLocalActivitiesSlow(accountId: accountId) ?? []
        if let chain = update.chain {
            prevActivities += selectPendingActivitiesSlow(accountId: accountId, chain: chain) ?? []
        }
        
        let replacedIds = getActivityIdReplacements(
            prevActivities: prevActivities,
            nextActivities: newConfirmedActivities + (pendingActivities ?? [])
        )
        
        // A good TON address for testing: UQD5mxRgCuRNLxKxeOjG6r14iSroLF5FtomPnet-sgP5xI-e
        removeActivities(accountId: update.accountId, deleteIds: Array(replacedIds.keys))
        if let chain = update.chain,  let pendingActivities {
            if let oldIds = getAccountState(update.accountId).pendingActivityIds?[chain.rawValue] {
                removeActivities(accountId: accountId, deleteIds: oldIds)
            }
            addNewActivities(accountId: accountId, newActivities: pendingActivities, chain: chain)
        }
        
        addNewActivities(accountId: update.accountId, newActivities: newConfirmedActivities, chain: nil)
        
        // TODO: Update open ActivityVC if activity has changed
        notifyAboutNewActivities(newActivities: newConfirmedActivities)
        
        // TODO: Copy from web app: processCardMintingActivity
        // NFT polling is executed at long intervals, so it is more likely that a user will see a new transaction
        // rather than receiving a card in the collection. Therefore, when a new activity occurs,
        // we check for a card from the MyTonWallet collection and apply it.
        //        global = processCardMintingActivity(global, accountId, incomingActivities);
        
        if let chain = update.chain {
            setIsInitialActivitiesLoadedTrue(accountId: update.accountId, chain: chain);
        }
        WalletCoreData.notify(event: .activitiesChanged(accountId: update.accountId, updatedIds: unique((pendingActivities ?? []).map(\.id) + newConfirmedActivities.map(\.id)), replacedIds: replacedIds))
        log.info("handleNewActivities \(update.accountId, .public) [done] mainIds=\(getAccountState(update.accountId).idsMain?.count ?? -1) inUpdate=\(update.activities.count)")
    }
    
    private func handleNewLocalActivities(update: ApiUpdate.NewLocalActivities) {
        log.info("newLocalActivity \(update.accountId, .public)")
        let activities = hideOutdatedLocalActivities(accountId: update.accountId, localActivities: update.activities)
        addNewActivities(accountId: update.accountId, newActivities: activities, chain: nil)
        WalletCoreData.notify(event: .activitiesChanged(accountId: update.accountId, updatedIds: unique(activities.map(\.id)), replacedIds: [:]))
    }

    private func handleApplicationWillEnterForeground() async {
        self.lastApplicationWillEnterForeground = .now
        log.info("handleApplicationWillEnterForeground \(lastApplicationWillEnterForeground, .public)")
        do {
            try await AccountStore.reactivateCurrentAccount()
            await forceReload(dryRun: false)
            try await Task.sleep(for: .seconds(0.5))
            try await AccountStore.reactivateCurrentAccount()
        } catch {
            log.error("handleApplicationWillEnterForeground: \(error, .public)")
        }
    }
    
    // MARK: - Fetch methods
    
    func fetchAllTransactions(accountId: String, limit: Int, shouldLoadWithBudget: Bool) async throws {
        
        var toTimestamp = selectLastMainTxTimestamp(accountId: accountId)
        var fetchedActivities: [ApiActivity] = []
        
        while true {
            let result = try await Api.fetchPastActivities(accountId: accountId, limit: limit, tokenSlug: nil, toTimestamp: toTimestamp)
            if result.isEmpty {
                updateActivitiesIsHistoryEndReached(accountId: accountId, slug: nil, isReached: true)
                break
            }
            var filteredResult = result
            if AppStorageHelper.hideTinyTransfers {
                filteredResult = filteredResult.filter {
                    !$0.isTinyOrScamTransaction
                }
            }
            fetchedActivities.append(contentsOf: result)
            if filteredResult.count >= limit || fetchedActivities.count >= limit {
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
            try await fetchAllTransactions(accountId: accountId, limit: limit, shouldLoadWithBudget: false)
        }
    }
    
    func fetchTokenTransactions(accountId: String, limit: Int, token: ApiToken, shouldLoadWithBudget: Bool) async throws {
        var accountState = getAccountState(accountId)
        var idsBySlug = accountState.idsBySlug ?? [:]
        var byId = accountState.byId ?? [:]
        
        var fetchedActivities: [ApiActivity] = []
        var tokenIds = idsBySlug[token.slug] ?? []
        var toTimestamp = tokenIds
            .last(where: { getIsIdSuitableForFetchingTimestamp($0) && byId[$0] != nil })
            .flatMap { id in byId[id]?.timestamp }
        
        while true {
            let result = try await Api.fetchPastActivities(accountId: accountId, limit: limit, tokenSlug: token.slug, toTimestamp: toTimestamp)
            if result.isEmpty {
                updateActivitiesIsHistoryEndReached(accountId: accountId, slug: token.slug, isReached: true)
                break
            }
            var filteredResult = result
            if AppStorageHelper.hideTinyTransfers {
                filteredResult = filteredResult.filter {
                    !$0.isTinyOrScamTransaction
                }
            }
            fetchedActivities.append(contentsOf: result)
            if filteredResult.count >= limit || fetchedActivities.count >= limit {
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
            try await fetchTokenTransactions(accountId: accountId, limit: limit, token: token, shouldLoadWithBudget: false)
        }
    }
    
    @available(*, deprecated, message: "shouldn't be needed")
    private func forceReload(dryRun: Bool) async {
        do {
            if let accountId = AccountStore.accountId {
                log.info("forceReload sinceForeground=\(timeSinceLastApplicationWillEnterForeground) ")
                let result = try await Api.fetchPastActivities(accountId: accountId, limit: 60, tokenSlug: nil, toTimestamp: nil)
                if !dryRun {
                    handleNewActivities(update: .init(accountId: accountId, chain: nil, activities: result, pendingActivities: nil), forceReload: true)
                }
                log.info("forceReload [done] sinceForeground=\(timeSinceLastApplicationWillEnterForeground)")
            }
        } catch {
            log.error("forceReload: \(error)")
        }
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
                WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: [], replacedIds: [:]))
            }
        }
    }
    
    private func updateFromDb(accountIds: [String]) {
        let deletedKeys = Set(byAccountId.keys).subtracting(accountIds)
        for deletedKey in deletedKeys {
            byAccountId[deletedKey] = nil
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
        do {
            _ = try db.write { db in
                try AccountState.deleteAll(db)
            }
        } catch {
            log.error("clean failed: \(error)")
        }
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
            if let chain {
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
        if let state = byAccountId[accountId], let mainIds = state.idsMain?.prefix(count), let byId = state.byId {
            return mainIds.compactMap { byId[$0] }
        }
        return nil
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
    
    private func selectAccountTxTokenSlugs(accountId: String, chain: ApiChain) -> [String]? {
        if let idsBySlug = getAccountState(accountId).idsBySlug {
            return idsBySlug.keys.filter { $0.hasPrefix(chain.rawValue)}
        }
        return nil
    }
    
    private func selectLastMainTxTimestamp(accountId: String) -> Int64? {
        let activities = getAccountState(accountId)
        let txId = activities.idsMain?.last(where: { getIsIdSuitableForFetchingTimestamp($0) })
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
    
    private func notifyAboutNewActivities(newActivities: [ApiActivity]) {
        for activity in newActivities {
            if case .transaction(let tx) = activity,
                tx.isIncoming,
                Date.now.timeIntervalSince(activity.timestampDate) < TX_AGE_TO_PLAY_SOUND,
               !(AppStorageHelper.hideTinyTransfers && activity.isTinyOrScamTransaction),
               // TODO: !getIsTransactionWithPoisoning(activity)
               AppStorageHelper.sounds,
               WalletContextManager.delegate?.isAppUnlocked == true,
               !notifiedIds.contains(activity.id) {
                log.info("notifying about tx: \(activity, .public)")
                AudioHelpers.play(sound: .incomingTransaction)
                break
            }
        }
        notifiedIds = notifiedIds.union(newActivities.map(\.id))
    }
}


import GRDB
import Foundation
import WalletContext
import OrderedCollections
import WalletCoreTypes

private let log = Log("ActivityStore")
private let TX_AGE_TO_PLAY_SOUND = 60.0 // 1 min
private let CEX_SWAP_REFRESH_INTERVAL = 3.0
private let CEX_SWAP_REFRESH_INTERVAL_NOT_FOCUSED = 15.0
private let CEX_SWAP_REFRESH_CONTEXT_LIMIT = 250

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

        static let databaseTableName: String = "account_activities"
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
    private var pendingCexSwapRefreshTask: Task<Void, Never>?
    private var isAppFocused: Bool = true
    private var queuedEvents: [WalletCoreData.Event] = []
    private var isProcessingEvents = false
    
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
            await enqueueEvent(event)
        }
    }

    private func enqueueEvent(_ event: WalletCoreData.Event) async {
        queuedEvents.append(event)
        guard !isProcessingEvents else { return }

        isProcessingEvents = true
        while !queuedEvents.isEmpty {
            let event = queuedEvents.removeFirst()
            await handleEvent(event)
        }
        isProcessingEvents = false
    }
    
    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .initialActivities(let update):
            handleInitialActivities(update: update)
        case .newActivities(let update):
            await handleNewActivities(update: update)
        case .newLocalActivity(let update):
            await handleNewLocalActivities(update: update)
        case .accountChanged:
            await refreshPendingCexSwapsForCurrentAccount()
            updatePendingCexSwapRefreshTask()
        case .applicationWillEnterForeground:
            lastApplicationWillEnterForeground = .now
            isAppFocused = true
            await refreshPendingCexSwapsForCurrentAccount()
            updatePendingCexSwapRefreshTask()
        case .applicationDidEnterBackground:
            isAppFocused = false
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
        updatePendingCexSwapRefreshTask()
        log.info("handleInitialActivities \(update.accountId, .public) [done] mainIds=\(update.mainActivities.count)")
    }
    
    private func handleNewActivities(update: ApiUpdate.NewActivities) async {
        log.info("handleNewActivities \(update.accountId, .public) sinceForeground=\(timeSinceLastApplicationWillEnterForeground) mainIds=\(getAccountState(update.accountId).idsMain?.count ?? -1) inUpdate=\(update.activities.count)")
        
        let accountId = update.accountId
        let pendingActivities = update.pendingActivities
        
        var prevActivities = selectLocalActivitiesSlow(accountId: accountId) ?? []
        if let chain = update.chain {
            prevActivities += selectPendingActivitiesSlow(accountId: accountId, chain: chain) ?? []
        }
        
        let reconciliation = await reconcileActivityUpdateOnSdk(
            accountId: accountId,
            previousActivities: prevActivities,
            confirmedActivities: update.activities,
            pendingActivities: pendingActivities,
            contextActivities: selectCexSwapRefreshContextActivities(
                accountId: accountId,
                pendingCexSwaps: pendingCexSwapActivities(accountId: accountId),
                priorityActivities: update.activities
            )
        )

        // Reconciliation identity is SDK-owned. If the bridge is unavailable, apply the raw update without inferring
        // replacements or hiding/removing activities in native code.
        let replacedIds = reconciliation?.patch.replacedIds ?? [:]
        let adjustedPendingActivities = reconciliation?.pendingActivities ?? pendingActivities
        let newConfirmedActivities = reconciliation?.confirmedActivities ?? update.activities

        var updatedIds: [String]
        if let patch = reconciliation?.patch {
            updatedIds = []
            if let chain = update.chain, let oldIds = getAccountState(accountId).pendingActivityIds?[chain.rawValue] {
                removeActivities(accountId: accountId, deleteIds: oldIds)
                updatedIds.append(contentsOf: oldIds)
            }
            updatedIds.append(contentsOf: applyActivitiesPatch(accountId: accountId, patch: patch, visibleChain: update.chain))
        } else {
            if let chain = update.chain,  let pendingActivities = adjustedPendingActivities {
                if let oldIds = getAccountState(accountId).pendingActivityIds?[chain.rawValue] {
                    removeActivities(accountId: accountId, deleteIds: oldIds)
                }
                addNewActivities(accountId: accountId, newActivities: pendingActivities, chain: chain)
            }
            addNewActivities(accountId: accountId, newActivities: newConfirmedActivities, chain: nil)
            updatedIds = unique((adjustedPendingActivities ?? []).map(\.id) + newConfirmedActivities.map(\.id))
        }

        let visibleUpserts = (reconciliation?.patch.upsert ?? ((adjustedPendingActivities ?? []) + newConfirmedActivities)).filter {
            $0.shouldHide != true
        }
        updatePoisoningCache(accountId: accountId, activities: visibleUpserts)
        applyNftsFromActivities(accountId: accountId, activities: visibleUpserts)
        
        if let chain = update.chain {
            setIsInitialActivitiesLoadedTrue(accountId: accountId, chain: chain);
        }
        notifyAboutNewActivities(accountId: accountId, newActivities: visibleUpserts)
        WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: unique(updatedIds), replacedIds: replacedIds))
        updatePendingCexSwapRefreshTask()
        log.info("handleNewActivities \(accountId, .public) [done] mainIds=\(getAccountState(accountId).idsMain?.count ?? -1) inUpdate=\(update.activities.count)")
    }
    
    private func handleNewLocalActivities(update: ApiUpdate.NewLocalActivities) async {
        log.info("newLocalActivity \(update.accountId, .public)")
        let maxDepth = update.activities.count + 20
        let chainActivities = selectRecentNonLocalActivitiesSlow(accountId: update.accountId, count: maxDepth) ?? []
        let reconciliation = await reconcileActivityUpdateOnSdk(
            accountId: update.accountId,
            previousActivities: update.activities,
            confirmedActivities: chainActivities,
            pendingActivities: nil
        )
        // Fail closed when SDK reconciliation is unavailable: keep local and chain rows separate until a later patch.
        let replacedIds = reconciliation?.patch.replacedIds ?? [:]
        var updatedIds = update.activities.map(\.id)
        addNewActivities(accountId: update.accountId, newActivities: update.activities, chain: nil)
        if let patch = reconciliation?.patch {
            updatedIds.append(contentsOf: applyActivitiesPatch(
                accountId: update.accountId,
                patch: patch,
                visibleChain: nil
            ))
        }
        WalletCoreData.notify(event: .activitiesChanged(
            accountId: update.accountId,
            updatedIds: unique(updatedIds),
            replacedIds: replacedIds
        ))
    }

    private func reconcileActivityUpdateOnSdk(
        accountId: String,
        previousActivities: [ApiActivity],
        confirmedActivities: [ApiActivity],
        pendingActivities: [ApiActivity]?,
        contextActivities: [ApiActivity]? = nil
    ) async -> ApiReconcileActivityUpdateResult? {
        do {
            return try await Api.reconcileActivityUpdate(
                accountId: accountId,
                previousActivities: previousActivities,
                confirmedActivities: confirmedActivities,
                pendingActivities: pendingActivities,
                contextActivities: contextActivities
            )
        } catch {
            log.error("reconcileActivityUpdate failed accountId=\(accountId, .public) error=\(error, .public)")
            return nil
        }
    }

    // MARK: - Fetch methods
    
    func fetchAllActivities(accountId: String, limit: Int, shouldLoadWithBudget: Bool) async throws {
        
        var toTimestamp = selectLastMainTxTimestamp(accountId: accountId)
        var fetchedActivities: [ApiActivity] = []
        
        var hasMore = true
        while hasMore {
            let result = try await Api.fetchPastActivities(accountId: accountId, limit: limit, tokenSlug: nil, toTimestamp: toTimestamp)
            let activities = result.activities
            let apiHasMore = result.hasMore
            if activities.isEmpty {
                updateActivitiesIsHistoryEndReached(accountId: accountId, slug: nil, isReached: true)
                break
            }
            let poisoningCache = getPoisoningCache(accountId)
            updatePoisoningCache(accountId: accountId, activities: activities)
            let hideTinyTransfers = AppStorageHelper.hideTinyTransfers
            let filteredResult = activities.filter {
                if $0.shouldHide == true { return false }
                guard case .transaction(let transaction) = $0 else { return true }
                if shouldHideBecauseOfNft(accountId: accountId, transaction: transaction) {
                    return false
                }
                if hideTinyTransfers && $0.isTinyOrScamTransaction {
                    return false
                }
                return !poisoningCache.isTransactionWithPoisoning(transaction: transaction)
            }
            fetchedActivities.append(contentsOf: activities)
            hasMore = apiHasMore
                && (
                    filteredResult.count < limit
                    && fetchedActivities.count < limit
                )
            toTimestamp = activities.last!.timestamp
        }
        
        fetchedActivities.sort(by: <)
        
        let accountState = getAccountState(accountId)
        var byId = accountState.byId ?? [:]
        var newIds: [String] = []
        for activity in fetchedActivities {
            if upsertActivity(activity, in: &byId) {
                newIds.append(activity.id)
            }

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
        updatePendingCexSwapRefreshTask()
        
        if shouldLoadWithBudget {
            await Task.yield()
            try await fetchAllActivities(accountId: accountId, limit: limit, shouldLoadWithBudget: false)
        }
    }
    
    func fetchTokenActivities(accountId: String, limit: Int, token: ApiToken, shouldLoadWithBudget: Bool) async throws {
        var accountState = getAccountState(accountId)
        var byId = accountState.byId ?? [:]
        
        var fetchedActivities: [ApiActivity] = []
        var tokenIds = accountState.idsBySlug?[token.slug] ?? []
        var toTimestamp = tokenIds
            .last(where: { getIsIdSuitableForFetchingTimestamp(activity: byId[$0]) })
            .flatMap { id in byId[id]?.timestamp }
        
        var hasMore = true
        while hasMore {
            let result = try await Api.fetchPastActivities(accountId: accountId, limit: limit, tokenSlug: token.slug, toTimestamp: toTimestamp)
            let activities = result.activities
            let apiHasMore = result.hasMore
            if activities.isEmpty {
                updateActivitiesIsHistoryEndReached(accountId: accountId, slug: token.slug, isReached: true)
                break
            }
            let poisoningCache = getPoisoningCache(accountId)
            updatePoisoningCache(accountId: accountId, activities: activities)
            let hideTinyTransfers = AppStorageHelper.hideTinyTransfers
            let filteredResult = activities.filter {
                if $0.shouldHide == true { return false }
                guard case .transaction(let transaction) = $0 else { return true }
                if shouldHideBecauseOfNft(accountId: accountId, transaction: transaction) {
                    return false
                }
                if hideTinyTransfers && $0.isTinyOrScamTransaction {
                    return false
                }
                return !poisoningCache.isTransactionWithPoisoning(transaction: transaction)
            }
            fetchedActivities.append(contentsOf: activities)
            hasMore = apiHasMore
                && (
                    filteredResult.count < limit
                    && fetchedActivities.count < limit
                )
            toTimestamp = activities.last!.timestamp
        }
        
        fetchedActivities.sort(by: <)
        
        accountState = getAccountState(accountId)
        byId = accountState.byId ?? [:]
        var newIds: [String] = []
        for activity in fetchedActivities {
            if upsertActivity(activity, in: &byId) {
                newIds.append(activity.id)
            }

        }
        
        tokenIds = mergeSortedActivityIds(newIds, accountState.idsBySlug?[token.slug] ?? [], byId: byId)
        var idsBySlug = accountState.idsBySlug ?? [:]
        idsBySlug[token.slug] = tokenIds
        
        withAccountState(accountId) {
            $0.byId = byId
            $0.idsBySlug = idsBySlug
        }
        
        log.info("[inf] got new ids \(token.slug): \(newIds.count)")
        updatePendingCexSwapRefreshTask()
        
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

    private func shouldSkipCallContractReplacement(existingActivity: ApiActivity?, newActivity: ApiActivity) -> Bool {
        guard newActivity.type == .callContract else {
            return false
        }
        guard let existingActivity else {
            return true
        }
        return existingActivity.type != .callContract
    }

    private func upsertActivity(_ activity: ApiActivity, in byId: inout [String: ApiActivity]) -> Bool {
        let existingActivity = byId[activity.id]
        if shouldSkipCallContractReplacement(existingActivity: existingActivity, newActivity: activity) {
            return false
        }
        byId[activity.id] = preserveActivityStatusProgress(existingActivity: existingActivity, incomingActivity: activity)
        return true
    }
    
    public func fetchActivityDetails(accountId: String, activity: ApiActivity) async throws -> ApiActivity {
        let fetchedActivity = try await Api.fetchActivityDetails(accountId: accountId, activity: activity)
        var didUpdate = false
        var resultActivity = fetchedActivity
        withAccountState(accountId) {
            var byId = $0.byId ?? [:]
            let existingActivity = byId[fetchedActivity.id]
            if shouldSkipCallContractReplacement(existingActivity: existingActivity, newActivity: fetchedActivity) {
                resultActivity = existingActivity ?? activity
                return
            }
            _ = upsertActivity(fetchedActivity, in: &byId)
            $0.byId = byId
            didUpdate = true
        }
        if didUpdate {
            WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: [fetchedActivity.id], replacedIds: [:]))
        }
        return resultActivity
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
        updatePendingCexSwapRefreshTask()
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
        pendingCexSwapRefreshTask?.cancel()
        pendingCexSwapRefreshTask = nil
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
            _ = upsertActivity(activity, in: &byId)
        }
        
        // Activities from different blockchains arrive separately, which causes the order to be disrupted
        let idsMain = mergeActivityIdsToMaxTime(
            mainActivities.compactMap { byId[$0.id] == nil ? nil : $0.id },
            currentState.idsMain ?? [],
            byId: byId
        )
        
        var idsBySlug = currentState.idsBySlug ?? [:]
        let newIdsBySlug = bySlug.mapValues { activities in
            activities.compactMap { byId[$0.id] == nil ? nil : $0.id }
        }
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
        var storedNewActivities: [ApiActivity] = []
        for activity in newActivities {
            if let existingActivity = byId[activity.id],
               isNonPendingActivity(existingActivity),
               getIsActivityPending(activity) {
                log.error("activity status regression id=\(activity.id, .public) oldStatus=\(activityStatusString(existingActivity), .public) newStatus=\(activityStatusString(activity), .public) oldHash=\(activityHash(existingActivity), .public) newHash=\(activityHash(activity), .public)")
            }
            if upsertActivity(activity, in: &byId) {
                storedNewActivities.append(activity)
            }

        }
        
        withAccountState(accountId) { state in
            state.byId = byId
            indexStoredActivities(storedNewActivities, chain: chain, in: &state)
        }
    }

    /** Updates presentation indexes for activities that are already stored exactly in byId. */
    private func indexStoredActivities(_ activities: [ApiActivity], chain: ApiChain?, in state: inout AccountState) {
        if activities.isEmpty {
            return
        }

        let byId = state.byId ?? [:]
        let newIds = activities.map(\.id)

        // Activities from different blockchains arrive separately, which causes the order to be disrupted
        let idsMain = mergeSortedActivityIds(newIds, state.idsMain ?? [], byId: byId)

        var idsBySlug = state.idsBySlug ?? [:]
        let newIdsBySlug = buildActivityIdsBySlug(activities)
        for (slug, newIds) in newIdsBySlug {
            idsBySlug[slug] = mergeSortedActivityIds(newIds, state.idsBySlug?[slug] ?? [], byId: byId)
        }

        let newestActivitiesBySlug = _getNewestActivitiesBySlug(
            byId: byId,
            idsBySlug: idsBySlug,
            newestActivitiesBySlug: state.newestActivitiesBySlug,
            tokenSlugs: newIdsBySlug.keys
        )

        let oldLocalIds = state.localActivityIds ?? []
        let newLocalIds = activities.filter { getIsIdLocal($0.id) }.map(\.id)
        let localActivityIds = Array(Set(oldLocalIds + newLocalIds))

        var pendingIds: [String: [String]] = state.pendingActivityIds ?? [:]
        if let chain {
            let oldPendingIds = state.pendingActivityIds?[chain.rawValue] ?? []
            let newPendingIds = activities.filter { getIsActivityPending($0) && !getIsIdLocal($0.id) }.map(\.id)
            pendingIds[chain.rawValue] = Array(Set(oldPendingIds + newPendingIds))
        }

        state.idsMain = idsMain
        state.idsBySlug = idsBySlug
        state.newestActivitiesBySlug = newestActivitiesBySlug
        state.localActivityIds = localActivityIds
        if chain != nil {
            state.pendingActivityIds = pendingIds
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

    private func updatePendingCexSwapRefreshTask() {
        guard hasCurrentAccountPendingCexSwaps() else {
            pendingCexSwapRefreshTask?.cancel()
            pendingCexSwapRefreshTask = nil
            return
        }

        guard pendingCexSwapRefreshTask == nil else {
            return
        }

        pendingCexSwapRefreshTask = Task { [weak self] in
            await self?.pendingCexSwapRefreshLoop()
        }
    }

    private func pendingCexSwapRefreshLoop() async {
        defer {
            pendingCexSwapRefreshTask = nil
            updatePendingCexSwapRefreshTask()
        }

        while !Task.isCancelled {
            await refreshPendingCexSwapsForCurrentAccount()

            guard hasCurrentAccountPendingCexSwaps() else {
                return
            }

            let interval = isAppFocused ? CEX_SWAP_REFRESH_INTERVAL : CEX_SWAP_REFRESH_INTERVAL_NOT_FOCUSED
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
        }
    }

    private func refreshPendingCexSwapsForCurrentAccount() async {
        guard let accountId = AccountStore.accountId else {
            return
        }
        await refreshPendingCexSwaps(accountId: accountId)
    }

    private func refreshPendingCexSwaps(accountId: String) async {
        let pendingCexSwaps = pendingCexSwapActivities(accountId: accountId)
        let items = unique(pendingCexSwaps.map { $0.parsedTxId.hash })
            .map { ApiFetchSwapItem(id: $0, chain: .ton) }
        guard !items.isEmpty else {
            return
        }

        do {
            let existingActivities = selectCexSwapRefreshContextActivities(
                accountId: accountId,
                pendingCexSwaps: pendingCexSwaps
            )
            let result = try await Api.fetchSwaps(accountId: accountId, items: items, existingActivities: existingActivities)
            let updatedIds = unique(applyFetchedCexSwaps(accountId: accountId, result: result))
            if !updatedIds.isEmpty {
                WalletCoreData.notify(event: .activitiesChanged(accountId: accountId, updatedIds: updatedIds, replacedIds: [:]))
            }
        } catch {
            log.error("refreshPendingCexSwaps: \(error, .public)")
        }
    }

    private func selectCexSwapRefreshContextActivities(
        accountId: String,
        pendingCexSwaps: [ApiActivity],
        priorityActivities: [ApiActivity] = []
    ) -> [ApiActivity] {
        let state = getAccountState(accountId)
        var byId = state.byId ?? [:]

        var ids = OrderedSet<String>()
        func append(_ activity: ApiActivity?) {
            guard let activity, ids.count < CEX_SWAP_REFRESH_CONTEXT_LIMIT else {
                return
            }
            byId[activity.id] = activity
            ids.append(activity.id)
        }
        func appendId(_ id: String) {
            append(byId[id])
        }

        // Keep active CEX/local/pending state ahead of an incoming bulk slice; it drives the SDK's forced refresh and
        // identity-only projection. CEX-owned source rows are selected from byId rather than presentation indexes so a
        // hidden source can be unhidden by a later SDK patch. Main/token-history rows provide older context afterwards.
        for activity in pendingCexSwaps {
            append(activity)
        }
        for activity in byId.values where activity.extra?.reconciliation?.reason == "cex-swap" {
            append(activity)
        }
        for id in state.localActivityIds ?? [] {
            appendId(id)
        }
        if let pendingActivityIds = state.pendingActivityIds {
            for pendingIds in pendingActivityIds.values {
                for id in pendingIds {
                    appendId(id)
                }
            }
        }
        for activity in priorityActivities {
            append(activity)
        }
        for id in state.idsMain ?? [] {
            appendId(id)
        }
        if let idsBySlug = state.idsBySlug {
            for tokenIds in idsBySlug.values {
                for id in tokenIds {
                    appendId(id)
                }
            }
        }

        return ids.compactMap { byId[$0] }
    }

    private func hasCurrentAccountPendingCexSwaps() -> Bool {
        guard let accountId = AccountStore.accountId else {
            return false
        }
        return !pendingCexSwapIds(accountId: accountId).isEmpty
    }

    private func pendingCexSwapIds(accountId: String) -> [String] {
        unique(pendingCexSwapActivities(accountId: accountId).map { $0.parsedTxId.hash })
    }

    private func pendingCexSwapActivities(accountId: String) -> [ApiActivity] {
        let byId = getAccountState(accountId).byId ?? [:]
        return byId.values.filter { activity in
            guard case .swap(let swap) = activity,
                  swap.cex != nil,
                  getIsActivityPendingForUser(activity)
            else {
                return false
            }
            return true
        }
    }

    private func applyFetchedCexSwaps(accountId: String, result: ApiFetchSwapsResult) -> [String] {
        guard let patch = result.patch else {
            log.error("fetchSwaps returned no SDK reconciliation patch")
            return []
        }

        return applyActivitiesPatch(accountId: accountId, patch: patch, visibleChain: nil)
    }

    @discardableResult
    private func applyActivitiesPatch(accountId: String, patch: ApiActivitiesPatch, visibleChain: ApiChain?) -> [String] {
        var updatedIds: [String] = []
        let hiddenUpsertIds = patch.upsert.filter { $0.shouldHide == true }.map(\.id)

        if !hiddenUpsertIds.isEmpty {
            updatedIds.append(contentsOf: removeActivityIdsFromIndexes(
                accountId: accountId,
                activityIds: hiddenUpsertIds
            ))
        }

        if !patch.removeIds.isEmpty {
            removeActivities(accountId: accountId, deleteIds: patch.removeIds)
            updatedIds.append(contentsOf: patch.removeIds)
        }

        let visibleUpserts = patch.upsert.filter { $0.shouldHide != true }
        if !patch.upsert.isEmpty {
            withAccountState(accountId) { state in
                var byId = state.byId ?? [:]
                for activity in patch.upsert {
                    // SDK patch upserts are authoritative. Status progression, reconciliation metadata merging and
                    // callContract decisions have already happened before the patch was emitted.
                    if byId[activity.id] != activity {
                        updatedIds.append(activity.id)
                    }
                    byId[activity.id] = activity
                }
                state.byId = byId
                indexStoredActivities(visibleUpserts, chain: visibleChain, in: &state)
            }
        }

        if !visibleUpserts.isEmpty {
            updatedIds.append(contentsOf: visibleUpserts.map(\.id))
        }

        return unique(updatedIds)
    }

    /**
     * Removes activities from presentation, local and pending indexes without deleting their stored `byId` rows.
     * Hidden SDK upserts are restored verbatim in `byId` by `applyActivitiesPatch`.
     */
    @discardableResult
    private func removeActivityIdsFromIndexes(accountId: String, activityIds: [String]) -> [String] {
        let currentState = getAccountState(accountId)
        let activityIds = Set(activityIds)
        guard !activityIds.isEmpty else { return [] }

        var indexedIds = Set(currentState.idsMain ?? [])
        for ids in (currentState.idsBySlug ?? [:]).values {
            indexedIds.formUnion(ids)
        }
        indexedIds.formUnion(currentState.localActivityIds ?? [])
        for ids in (currentState.pendingActivityIds ?? [:]).values {
            indexedIds.formUnion(ids)
        }
        let removedIndexedIds = activityIds.filter { indexedIds.contains($0) }
        let affectedTokenSlugs = getActivityListTokenSlugs(
            activityIds: activityIds,
            byId: currentState.byId ?? [:]
        )

        var idsBySlug = currentState.idsBySlug ?? [:]
        for tokenSlug in affectedTokenSlugs {
            if let idsForSlug = idsBySlug[tokenSlug] {
                idsBySlug[tokenSlug] = idsForSlug.filter { !activityIds.contains($0) }
            }
        }

        let newestActivitiesBySlug = _getNewestActivitiesBySlug(
            byId: currentState.byId ?? [:],
            idsBySlug: idsBySlug,
            newestActivitiesBySlug: currentState.newestActivitiesBySlug,
            tokenSlugs: affectedTokenSlugs
        )

        withAccountState(accountId) {
            $0.idsMain = currentState.idsMain?.filter { !activityIds.contains($0) }
            $0.idsBySlug = idsBySlug
            $0.newestActivitiesBySlug = newestActivitiesBySlug
            $0.localActivityIds = currentState.localActivityIds?.filter { !activityIds.contains($0) }
            $0.pendingActivityIds = currentState.pendingActivityIds?.mapValues { ids in
                ids.filter { !activityIds.contains($0) }
            }
        }

        return Array(removedIndexedIds)
    }

    private func removeActivities(accountId: String, deleteIds: [String]) {
        let currentState = getAccountState(accountId)
        let deleteIds = Set(deleteIds)
        guard !deleteIds.isEmpty else { return }

        removeActivityIdsFromIndexes(accountId: accountId, activityIds: Array(deleteIds))
        let byId = currentState.byId?.filter { id, _ in !deleteIds.contains(id) }

        withAccountState(accountId) {
            $0.byId = byId
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
        var shouldPlayChime = false
        for activity in newActivities {
            if !activity.isConfirmedOrCompleted {
                continue
            }
            switch activity {
            case .transaction(let tx):
                if tx.isIncoming,
                   Date.now.timeIntervalSince(activity.timestampDate) < TX_AGE_TO_PLAY_SOUND,
                   !(AppStorageHelper.hideTinyTransfers && activity.isTinyOrScamTransaction),
                   !shouldHideBecauseOfNft(accountId: accountId, transaction: tx),
                   !getPoisoningCache(accountId).isTransactionWithPoisoning(transaction: tx),
                   AppStorageHelper.sounds,
                   !notifiedIds.contains(activity.id)
                {
                    log.info("notifying about tx: \(activity.id, .public)")
                    shouldPlayChime = true
                    break
                }
            case .swap:
                break
            }
            notifiedIds.insert(activity.id)
        }
        if shouldPlayChime {
            Task {
                let isAppUnlocked = await WalletContextManager.delegate?.isAppUnlocked == true
                if isAppUnlocked {
                    await AudioHelpers.play(sound: .incomingTransaction)
                }
            }
        }
    }

    private func shouldHideBecauseOfNft(accountId: String, activity: ApiActivity) -> Bool {
        guard case .transaction(let transaction) = activity else {
            return false
        }
        return shouldHideBecauseOfNft(accountId: accountId, transaction: transaction)
    }

    private func shouldHideBecauseOfNft(accountId: String, transaction: ApiTransactionActivity) -> Bool {
        NftStore.shouldHideTransaction(accountId: accountId, transaction: transaction)
    }

    private func applyNftsFromActivities(accountId: String, activities: some Collection<ApiActivity>) {
        for activity in activities {
            guard activity.isConfirmedOrCompleted,
                  !activity.isLocal,
                  case .transaction(let transaction) = activity,
                  let nft = transaction.nft
            else {
                continue
            }
            let isNftIncoming = if transaction.type == .nftTrade {
                !transaction.isIncoming
            } else {
                transaction.isIncoming
            }
            guard isNftIncoming else {
                continue
            }
            NftStore.applyIncomingMtwCard(accountId: accountId, nft: nft)
            // Buying an NFT is an explicit intent to own it, so it stays visible even if its collection
            // is untrusted
            if transaction.type == .nftTrade {
                NftStore.applyPurchasedNft(accountId: accountId, nft: nft)
            }
        }
    }
}

import Foundation

public enum UniversalSearchRefreshDisposition: String, Hashable, Sendable {
    case applied
    case superseded
}

public struct UniversalSearchSourceFailure: Hashable, Sendable {
    public let sourceID: SearchSourceID
    public let description: String

    public init(sourceID: SearchSourceID, description: String) {
        self.sourceID = sourceID
        self.description = description
    }
}

public struct UniversalSearchRefreshResult: Hashable, Sendable {
    public let disposition: UniversalSearchRefreshDisposition
    public let corpusRevision: UInt64
    public let refreshedSourceIDs: [SearchSourceID]
    public let failures: [UniversalSearchSourceFailure]

    public init(
        disposition: UniversalSearchRefreshDisposition,
        corpusRevision: UInt64,
        refreshedSourceIDs: [SearchSourceID],
        failures: [UniversalSearchSourceFailure]
    ) {
        self.disposition = disposition
        self.corpusRevision = corpusRevision
        self.refreshedSourceIDs = refreshedSourceIDs
        self.failures = failures
    }
}

public struct UniversalSearchRefreshProgress: Hashable, Sendable {
    public let sourceID: SearchSourceID
    public let corpusRevision: UInt64
    public let sourceDocumentCount: Int
    public let corpusDocumentCount: Int
    public let sourceElapsedMilliseconds: Double
    public let indexElapsedMilliseconds: Double

    public init(
        sourceID: SearchSourceID,
        corpusRevision: UInt64,
        sourceDocumentCount: Int = 0,
        corpusDocumentCount: Int = 0,
        sourceElapsedMilliseconds: Double = 0,
        indexElapsedMilliseconds: Double = 0
    ) {
        self.sourceID = sourceID
        self.corpusRevision = corpusRevision
        self.sourceDocumentCount = sourceDocumentCount
        self.corpusDocumentCount = corpusDocumentCount
        self.sourceElapsedMilliseconds = sourceElapsedMilliseconds
        self.indexElapsedMilliseconds = indexElapsedMilliseconds
    }
}

public struct UniversalSearchResultSnapshot: Hashable, Sendable {
    public let query: UniversalSearchQuery
    public let hits: [UniversalSearchHit]
    public let totalHitCount: Int
    public let corpusRevision: UInt64
    public let corpusDocumentCount: Int
    public let rankingPolicyVersion: String
    public let generatedAt: Date
    public let engineElapsedMilliseconds: Double

    public init(
        query: UniversalSearchQuery,
        hits: [UniversalSearchHit],
        totalHitCount: Int,
        corpusRevision: UInt64,
        corpusDocumentCount: Int = 0,
        rankingPolicyVersion: String,
        generatedAt: Date,
        engineElapsedMilliseconds: Double = 0
    ) {
        self.query = query
        self.hits = hits
        self.totalHitCount = totalHitCount
        self.corpusRevision = corpusRevision
        self.corpusDocumentCount = corpusDocumentCount
        self.rankingPolicyVersion = rankingPolicyVersion
        self.generatedAt = generatedAt
        self.engineElapsedMilliseconds = engineElapsedMilliseconds
    }
}

/// Owns source refreshes and publishes immutable, revisioned search results.
///
/// Sources refresh concurrently, and a successful source replaces its complete previous snapshot
/// while a failed source keeps its last usable one. Snapshots are cached per scope — the slice of
/// the context each source declares it depends on — so a context change never discards data: the
/// corpus a context sees is assembled from the slots matching that context, account-scoped data
/// from other accounts is simply never assembled into it, and returning to a recently used
/// context reuses its cached snapshots and index.
public actor UniversalSearchCoordinator {
    private struct SlotKey: Hashable {
        let sourceID: SearchSourceID
        let scopeKey: String
    }

    private struct IndexCacheEntry {
        var index: UniversalSearchIndex
        /// The slot stamps the index was assembled from; unchanged stamps mean the corpus this
        /// context sees is byte-identical, so the cached index is served without any assembly
        var fingerprint: [SlotKey: UInt64]
        var indexedAt: Date
        var validThrough: Date?
        var lastUsedAt: Date
    }

    private let sources: [any UniversalSearchSource]
    private let engine: UniversalSearchEngine
    private let browseEngine: UniversalSearchBrowseEngine
    private let indexStore: (any UniversalSearchIndexStore)?
    private let persistedSourceIDs: Set<SearchSourceID>
    private let scopingBySourceID: [SearchSourceID: UniversalSearchSourceScoping]

    /// Sources whose snapshots depend on the current account — the only ones an account switch
    /// can invalidate
    public nonisolated let accountScopedSourceIDs: Set<SearchSourceID>

    private var context: UniversalSearchContext?
    private var snapshotsBySlot: [SlotKey: UniversalSearchSourceSnapshot] = [:]
    private var stampsBySlot: [SlotKey: UInt64] = [:]
    private var slotStampCounter: UInt64 = 0
    private var hydratedScopeKeys: Set<String> = []
    private var indexCache: [UniversalSearchContext: IndexCacheEntry] = [:]
    private var corpusRevision: UInt64 = 0
    private var refreshGeneration: UInt64 = 0
    private var persistenceMutationGeneration: UInt64 = 0
    private var isPersistentIndexSynchronized = false
    private var cachedCandidateIndex: CachedCandidateIndex?

    private static let maxCachedIndexes = 4
    /// Snapshots a source may keep cached for scopes beyond the one currently in use
    private static let maxScopesPerSource = 4

    public init(
        sources: [any UniversalSearchSource],
        engine: UniversalSearchEngine = .init(),
        browseEngine: UniversalSearchBrowseEngine = .init(),
        indexStore: (any UniversalSearchIndexStore)? = nil,
        persistedSourceIDs: Set<SearchSourceID>? = nil
    ) {
        self.sources = sources
        self.engine = engine
        self.browseEngine = browseEngine
        self.indexStore = indexStore
        self.persistedSourceIDs = if indexStore == nil {
            []
        } else {
            persistedSourceIDs ?? Set(sources.map(\.sourceID))
        }
        self.scopingBySourceID = Dictionary(
            sources.map { ($0.sourceID, $0.scoping) },
            uniquingKeysWith: { first, _ in first }
        )
        self.accountScopedSourceIDs = Set(
            sources.filter { $0.scoping == .account }.map(\.sourceID)
        )
    }

    public func refresh(
        context newContext: UniversalSearchContext,
        sourceIDs requestedSourceIDs: Set<SearchSourceID>? = nil,
        onUpdate: (@Sendable (UniversalSearchRefreshProgress) async -> Void)? = nil
    ) async throws -> UniversalSearchRefreshResult {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        let contextChanged = context != newContext
        context = newContext
        if contextChanged {
            isPersistentIndexSynchronized = false

            let missingScopeKeys = activeScopeKeys(for: newContext).subtracting(hydratedScopeKeys)
            if let indexStore, !missingScopeKeys.isEmpty {
                hydratedScopeKeys.formUnion(missingScopeKeys)
                let hydrationStartedAt = CFAbsoluteTimeGetCurrent()
                do {
                    let snapshots = try await indexStore.snapshots(forScopeKeys: missingScopeKeys)
                        .filter { persistedSourceIDs.contains($0.sourceID) }
                    guard generation == refreshGeneration, context == newContext else {
                        return UniversalSearchRefreshResult(
                            disposition: .superseded,
                            corpusRevision: corpusRevision,
                            refreshedSourceIDs: [],
                            failures: []
                        )
                    }
                    var hydratedSnapshots: [UniversalSearchSourceSnapshot] = []
                    for snapshot in snapshots {
                        let key = slotKey(sourceID: snapshot.sourceID, context: newContext)
                        // In-memory slots (possibly filled while in another context sharing this
                        // scope) are fresher than their persisted rows
                        if snapshotsBySlot[key] == nil {
                            setSlot(key: key, snapshot: snapshot)
                            hydratedSnapshots.append(snapshot)
                        }
                    }
                    isPersistentIndexSynchronized = true

                    if !hydratedSnapshots.isEmpty {
                        let corpusDocumentCount = activeDocumentCount(for: newContext)
                        let hydrationElapsed = Self.elapsedMilliseconds(since: hydrationStartedAt)
                        for snapshot in hydratedSnapshots {
                            await onUpdate?(UniversalSearchRefreshProgress(
                                sourceID: snapshot.sourceID,
                                corpusRevision: corpusRevision,
                                sourceDocumentCount: snapshot.documents.count,
                                corpusDocumentCount: corpusDocumentCount,
                                sourceElapsedMilliseconds: hydrationElapsed
                            ))
                        }
                    }
                } catch {
                    isPersistentIndexSynchronized = false
                }
            } else if indexStore != nil {
                isPersistentIndexSynchronized = true
            }
        }

        let sourcesToRefresh = if let requestedSourceIDs {
            sources.filter { requestedSourceIDs.contains($0.sourceID) }
        } else {
            sources
        }

        var refreshedSourceIDs: [SearchSourceID] = []
        var failures: [UniversalSearchSourceFailure] = []
        let wasSuperseded = try await withThrowingTaskGroup(
            of: SourceRefreshOutcome.self,
            returning: Bool.self
        ) { group in
            for source in sourcesToRefresh {
                group.addTask {
                    let startedAt = CFAbsoluteTimeGetCurrent()
                    do {
                        let snapshot = try await source.snapshot(for: newContext)
                        try Task.checkCancellation()
                        guard snapshot.sourceID == source.sourceID else {
                            return .failure(.init(
                                sourceID: source.sourceID,
                                description: "Source returned snapshot for \(snapshot.sourceID)"
                            ))
                        }
                        return .success(
                            snapshot,
                            elapsedMilliseconds: Self.elapsedMilliseconds(since: startedAt)
                        )
                    } catch is CancellationError {
                        return .cancelled(source.sourceID)
                    } catch {
                        return .failure(.init(
                            sourceID: source.sourceID,
                            description: String(describing: error)
                        ))
                    }
                }
            }

            for try await outcome in group {
                try Task.checkCancellation()
                guard generation == refreshGeneration, context == newContext else {
                    group.cancelAll()
                    return true
                }

                switch outcome {
                case .success(let snapshot, let elapsedMilliseconds):
                    let previous = storeSnapshot(snapshot, context: newContext)
                    if !Self.persistableContentEquals(previous, snapshot) {
                        await persistReplacementIfNeeded(snapshot, context: newContext)
                    }
                    guard generation == refreshGeneration, context == newContext else {
                        group.cancelAll()
                        return true
                    }
                    refreshedSourceIDs.append(snapshot.sourceID)
                    await onUpdate?(UniversalSearchRefreshProgress(
                        sourceID: snapshot.sourceID,
                        corpusRevision: corpusRevision,
                        sourceDocumentCount: snapshot.documents.count,
                        corpusDocumentCount: activeDocumentCount(for: newContext),
                        sourceElapsedMilliseconds: elapsedMilliseconds
                    ))
                case .failure(let failure):
                    failures.append(failure)
                case .cancelled:
                    throw CancellationError()
                }
            }
            return false
        }

        try Task.checkCancellation()

        guard !wasSuperseded,
              generation == refreshGeneration,
              context == newContext else {
            return UniversalSearchRefreshResult(
                disposition: .superseded,
                corpusRevision: corpusRevision,
                refreshedSourceIDs: [],
                failures: []
            )
        }

        // One index build per refresh pass keeps the first search after it instant
        _ = index(for: newContext, at: Date())

        return UniversalSearchRefreshResult(
            disposition: .applied,
            corpusRevision: corpusRevision,
            refreshedSourceIDs: refreshedSourceIDs.sorted(),
            failures: failures.sorted { $0.sourceID < $1.sourceID }
        )
    }

    public func search(
        _ text: String,
        limit: Int? = nil,
        now: Date = Date()
    ) async -> UniversalSearchResultSnapshot {
        let query = UniversalSearchQuery(text)
        let baseIndex = context.map { index(for: $0, at: now) } ?? UniversalSearchIndex()
        let searchIndex = await candidateIndex(for: query, baseIndex: baseIndex)
        let engineStartedAt = CFAbsoluteTimeGetCurrent()
        var allHits = Task.isCancelled ? [] : engine.search(query, in: searchIndex, now: now)
        if allHits.isEmpty, searchIndex.documents.count != baseIndex.documents.count {
            allHits = engine.search(query, in: baseIndex, now: now)
        }
        let engineElapsedMilliseconds = Self.elapsedMilliseconds(since: engineStartedAt)
        let hits = if let limit {
            Array(allHits.prefix(max(0, limit)))
        } else {
            allHits
        }
        return UniversalSearchResultSnapshot(
            query: query,
            hits: hits,
            totalHitCount: allHits.count,
            corpusRevision: corpusRevision,
            corpusDocumentCount: baseIndex.documents.count,
            rankingPolicyVersion: engine.policy.version,
            generatedAt: now,
            engineElapsedMilliseconds: engineElapsedMilliseconds
        )
    }

    public func browse(now: Date = Date()) -> UniversalSearchBrowseSnapshot {
        let baseIndex = context.map { index(for: $0, at: now) } ?? UniversalSearchIndex()
        return browseEngine.snapshot(
            in: baseIndex.documents,
            corpusRevision: corpusRevision,
            now: now
        )
    }

    public func replace(_ snapshot: UniversalSearchSourceSnapshot) async {
        guard let context else { return }
        let previous = storeSnapshot(snapshot, context: context)
        if !Self.persistableContentEquals(previous, snapshot) {
            await persistReplacementIfNeeded(snapshot, context: context)
        }
    }

    @discardableResult
    public func replace(
        _ snapshot: UniversalSearchSourceSnapshot,
        ifContext expectedContext: UniversalSearchContext
    ) async -> Bool {
        guard context == expectedContext else { return false }
        await replace(snapshot)
        return true
    }

    public func remove(sourceID: SearchSourceID) async {
        guard let context else { return }
        let key = slotKey(sourceID: sourceID, context: context)
        guard snapshotsBySlot[key] != nil else { return }
        clearSlot(key: key)
        corpusRevision &+= 1
        await persistRemovalIfNeeded(sourceID: sourceID, context: context)
    }

    public func remove(sourceID: SearchSourceID, ifRevision revision: String?) async {
        guard let context,
              snapshotsBySlot[slotKey(sourceID: sourceID, context: context)]?.revision == revision
        else { return }
        await remove(sourceID: sourceID)
    }

    /// Drops an entity from every cached snapshot of every scope, query snapshots included, e.g. after the entity is
    /// deleted. Returns whether any snapshot contained it.
    @discardableResult
    public func removeDocument(id: SearchEntityID) async -> Bool {
        guard let context else { return false }
        var replacements: [(scopeKey: String, snapshot: UniversalSearchSourceSnapshot)] = []
        for (key, snapshot) in snapshotsBySlot where snapshot.documents.contains(where: { $0.id == id }) {
            let replacement = UniversalSearchSourceSnapshot(
                sourceID: snapshot.sourceID,
                authority: snapshot.authority,
                revision: snapshot.revision,
                generatedAt: snapshot.generatedAt,
                expiresAt: snapshot.expiresAt,
                staleUntil: snapshot.staleUntil,
                documents: snapshot.documents.filter { $0.id != id },
                signalContributions: snapshot.signalContributions
            )
            setSlot(key: key, snapshot: replacement)
            replacements.append((scopeKey: key.scopeKey, snapshot: replacement))
        }
        guard !replacements.isEmpty else { return false }
        for replacement in replacements {
            await persistReplacementIfNeeded(
                replacement.snapshot,
                scopeKey: replacement.scopeKey,
                context: context
            )
        }
        return true
    }

    /// Drops cached snapshots scoped to the account, e.g. after the account is deleted
    public func removeAccountScopedSlots(scopeID: String) {
        removeSlots(where: { $0.hasSuffix("|scope=\(scopeID)") })
        indexCache = indexCache.filter { $0.key.scopeID != scopeID }
        hydratedScopeKeys = hydratedScopeKeys.filter { !$0.hasSuffix("|scope=\(scopeID)") }
    }

    public func removeAllAccountScopedSlots() {
        removeSlots(where: { $0.contains("|scope=") })
        indexCache.removeAll()
        hydratedScopeKeys = hydratedScopeKeys.filter { !$0.contains("|scope=") }
    }

    public func currentContext() -> UniversalSearchContext? {
        context
    }

    // MARK: - Scoped snapshot slots

    private func scopeKey(sourceID: SearchSourceID, context: UniversalSearchContext) -> String {
        (scopingBySourceID[sourceID] ?? .account).scopeKey(for: context)
    }

    private func slotKey(sourceID: SearchSourceID, context: UniversalSearchContext) -> SlotKey {
        SlotKey(sourceID: sourceID, scopeKey: scopeKey(sourceID: sourceID, context: context))
    }

    @discardableResult
    private func storeSnapshot(
        _ snapshot: UniversalSearchSourceSnapshot,
        context: UniversalSearchContext
    ) -> UniversalSearchSourceSnapshot? {
        let key = slotKey(sourceID: snapshot.sourceID, context: context)
        let previous = snapshotsBySlot[key]
        setSlot(key: key, snapshot: snapshot)
        evictExcessScopes(sourceID: snapshot.sourceID, keeping: key.scopeKey)
        return previous
    }

    private func setSlot(key: SlotKey, snapshot: UniversalSearchSourceSnapshot) {
        let previous = snapshotsBySlot[key]
        snapshotsBySlot[key] = snapshot
        // A refresh that produced identical content must not invalidate index fingerprints
        if !Self.strictContentEquals(previous, snapshot) {
            slotStampCounter &+= 1
            stampsBySlot[key] = slotStampCounter
            corpusRevision &+= 1
        }
    }

    /// Whether two snapshots are identical in everything the corpus can observe — only
    /// `generatedAt` may differ
    private static func strictContentEquals(
        _ previous: UniversalSearchSourceSnapshot?,
        _ snapshot: UniversalSearchSourceSnapshot
    ) -> Bool {
        guard let previous else { return false }
        return previous.documents == snapshot.documents
            && previous.signalContributions == snapshot.signalContributions
            && previous.authority == snapshot.authority
            && previous.revision == snapshot.revision
            && previous.expiresAt == snapshot.expiresAt
            && previous.staleUntil == snapshot.staleUntil
    }

    private func clearSlot(key: SlotKey) {
        snapshotsBySlot[key] = nil
        stampsBySlot[key] = nil
    }

    /// Whether two snapshots project to the same persisted state. The store keeps searchable text,
    /// exact identifiers, and trait-derived retrieval priority — volatile signal values (balances,
    /// prices, interaction counters) change constantly and must not force a persistence rewrite
    private static func persistableContentEquals(
        _ previous: UniversalSearchSourceSnapshot?,
        _ snapshot: UniversalSearchSourceSnapshot
    ) -> Bool {
        guard let previous else { return false }
        return previous.authority == snapshot.authority
            && previous.revision == snapshot.revision
            && previous.expiresAt == snapshot.expiresAt
            && previous.staleUntil == snapshot.staleUntil
            && previous.documents.count == snapshot.documents.count
            && previous.signalContributions == snapshot.signalContributions
            && zip(previous.documents, snapshot.documents).allSatisfy { lhs, rhs in
                lhs.id == rhs.id
                    && lhs.kind == rhs.kind
                    && lhs.fields == rhs.fields
                    && lhs.matchRequirement == rhs.matchRequirement
                    && lhs.attributes == rhs.attributes
                    && lhs.signals.traits == rhs.signals.traits
            }
    }

    private func activeScopeKeys(for context: UniversalSearchContext) -> Set<String> {
        Set(
            [UniversalSearchSourceScoping.global, .network, .account]
                .map { $0.scopeKey(for: context) }
        )
    }

    private func evictExcessScopes(sourceID: SearchSourceID, keeping scopeKey: String) {
        let keys = snapshotsBySlot.keys.filter { $0.sourceID == sourceID }
        let excess = keys.count - Self.maxScopesPerSource
        guard excess > 0 else { return }
        let evictable = keys
            .filter { $0.scopeKey != scopeKey }
            .sorted {
                (snapshotsBySlot[$0]?.generatedAt ?? .distantPast)
                    < (snapshotsBySlot[$1]?.generatedAt ?? .distantPast)
            }
            .prefix(excess)
        for key in evictable {
            clearSlot(key: key)
        }
    }

    private func removeSlots(where scopeKeyMatches: (String) -> Bool) {
        let keys = snapshotsBySlot.keys.filter { scopeKeyMatches($0.scopeKey) }
        guard !keys.isEmpty else { return }
        for key in keys {
            clearSlot(key: key)
        }
        corpusRevision &+= 1
    }

    private func activeSnapshots(for context: UniversalSearchContext) -> [UniversalSearchSourceSnapshot] {
        let sourceIDs = Set(snapshotsBySlot.keys.map(\.sourceID))
        return sourceIDs.compactMap { sourceID in
            snapshotsBySlot[slotKey(sourceID: sourceID, context: context)]
        }
    }

    private func activeCorpus(for context: UniversalSearchContext) -> UniversalSearchCorpus {
        UniversalSearchCorpus(snapshots: activeSnapshots(for: context))
    }

    private func activeDocumentCount(for context: UniversalSearchContext) -> Int {
        activeSnapshots(for: context).reduce(0) { $0 + $1.documents.count }
    }

    // MARK: - Per-context index cache

    private func index(for context: UniversalSearchContext, at date: Date) -> UniversalSearchIndex {
        let fingerprint = activeFingerprint(for: context)
        if var entry = indexCache[context],
           entry.fingerprint == fingerprint,
           date >= entry.indexedAt,
           entry.validThrough.map({ date <= $0 }) ?? true {
            entry.lastUsedAt = date
            indexCache[context] = entry
            return entry.index
        }

        let corpus = activeCorpus(for: context)
        let documents = corpus.documents(at: date)
        let index: UniversalSearchIndex
        if let previous = indexCache[context], previous.index.documents == documents {
            index = previous.index
        } else {
            // Reuse normalization from this context's previous index, or from the most recently
            // used one — across accounts most documents share identical searchable fields
            let donor = indexCache[context]?.index
                ?? indexCache.values.max(by: { $0.lastUsedAt < $1.lastUsedAt })?.index
            index = UniversalSearchIndex(documents: documents, reusing: donor)
        }
        indexCache[context] = IndexCacheEntry(
            index: index,
            fingerprint: fingerprint,
            indexedAt: date,
            validThrough: corpus.nextUsabilityBoundary(after: date),
            lastUsedAt: date
        )
        evictIndexCacheIfNeeded(keeping: context)
        return index
    }

    private func activeFingerprint(for context: UniversalSearchContext) -> [SlotKey: UInt64] {
        var fingerprint: [SlotKey: UInt64] = [:]
        for sourceID in Set(snapshotsBySlot.keys.map(\.sourceID)) {
            let key = slotKey(sourceID: sourceID, context: context)
            if let stamp = stampsBySlot[key] {
                fingerprint[key] = stamp
            }
        }
        return fingerprint
    }

    private func evictIndexCacheIfNeeded(keeping context: UniversalSearchContext) {
        let excess = indexCache.count - Self.maxCachedIndexes
        guard excess > 0 else { return }
        let evictable = indexCache
            .filter { $0.key != context }
            .sorted { $0.value.lastUsedAt < $1.value.lastUsedAt }
            .prefix(excess)
        for (key, _) in evictable {
            indexCache[key] = nil
        }
    }

    // MARK: - Persistent candidate index

    private func candidateIndex(
        for query: UniversalSearchQuery,
        baseIndex: UniversalSearchIndex
    ) async -> UniversalSearchIndex {
        guard !query.isEmpty,
              let indexStore,
              let context,
              isPersistentIndexSynchronized else {
            return baseIndex
        }

        if let cachedCandidateIndex,
           cachedCandidateIndex.query == query,
           cachedCandidateIndex.context == context,
           cachedCandidateIndex.corpusRevision == corpusRevision {
            return cachedCandidateIndex.index
        }

        let expectedContext = context
        let expectedRevision = corpusRevision
        do {
            let storedIDs = try await indexStore.candidateEntityIDs(
                for: query,
                scopeKeys: activeScopeKeys(for: expectedContext),
                limit: 512
            )
            guard expectedContext == self.context,
                  expectedRevision == corpusRevision,
                  isPersistentIndexSynchronized else {
                return baseIndex
            }

            var candidateIDs = Set(storedIDs)
            candidateIDs.formUnion(
                baseIndex.candidateEntries(for: query).map { $0.document.id }
            )
            let candidateIndex = if candidateIDs.count < baseIndex.documents.count {
                UniversalSearchIndex(
                    documents: baseIndex.documents.filter { candidateIDs.contains($0.id) },
                    reusing: baseIndex
                )
            } else {
                baseIndex
            }
            cachedCandidateIndex = CachedCandidateIndex(
                query: query,
                context: expectedContext,
                corpusRevision: corpusRevision,
                index: candidateIndex
            )
            return candidateIndex
        } catch {
            isPersistentIndexSynchronized = false
            return baseIndex
        }
    }

    private func persistReplacementIfNeeded(
        _ snapshot: UniversalSearchSourceSnapshot,
        context: UniversalSearchContext
    ) async {
        await persistReplacementIfNeeded(
            snapshot,
            scopeKey: scopeKey(sourceID: snapshot.sourceID, context: context),
            context: context
        )
    }

    private func persistReplacementIfNeeded(
        _ snapshot: UniversalSearchSourceSnapshot,
        scopeKey: String,
        context: UniversalSearchContext
    ) async {
        guard persistedSourceIDs.contains(snapshot.sourceID), let indexStore else { return }
        persistenceMutationGeneration &+= 1
        let generation = persistenceMutationGeneration
        isPersistentIndexSynchronized = false
        do {
            try await indexStore.replace(snapshot, scopeKey: scopeKey)
            if generation == persistenceMutationGeneration, self.context == context {
                isPersistentIndexSynchronized = true
            }
        } catch {
            if generation == persistenceMutationGeneration, self.context == context {
                isPersistentIndexSynchronized = false
            }
        }
    }

    private func persistRemovalIfNeeded(
        sourceID: SearchSourceID,
        context: UniversalSearchContext
    ) async {
        guard persistedSourceIDs.contains(sourceID), let indexStore else { return }
        persistenceMutationGeneration &+= 1
        let generation = persistenceMutationGeneration
        isPersistentIndexSynchronized = false
        do {
            try await indexStore.removeSnapshot(
                sourceID: sourceID,
                scopeKey: scopeKey(sourceID: sourceID, context: context)
            )
            if generation == persistenceMutationGeneration, self.context == context {
                isPersistentIndexSynchronized = true
            }
        } catch {
            if generation == persistenceMutationGeneration, self.context == context {
                isPersistentIndexSynchronized = false
            }
        }
    }

    private static func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
    }
}

private struct CachedCandidateIndex {
    let query: UniversalSearchQuery
    let context: UniversalSearchContext
    let corpusRevision: UInt64
    let index: UniversalSearchIndex
}

private enum SourceRefreshOutcome: Sendable, Comparable {
    case success(UniversalSearchSourceSnapshot, elapsedMilliseconds: Double)
    case failure(UniversalSearchSourceFailure)
    case cancelled(SearchSourceID)

    private var sourceID: SearchSourceID {
        switch self {
        case .success(let snapshot, _): snapshot.sourceID
        case .failure(let failure): failure.sourceID
        case .cancelled(let sourceID): sourceID
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceID < rhs.sourceID
    }
}

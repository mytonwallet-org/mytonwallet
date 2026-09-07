import Foundation
import Testing
import UniversalSearchCore

@Suite("Universal Search coordinator")
struct UniversalSearchCoordinatorTests {
    private let context = UniversalSearchContext(
        scopeID: "account-a",
        network: "mainnet",
        localeIdentifier: "en"
    )

    @Test
    func `refreshes independent sources and reports partial failure`() async throws {
        let successful = StubSource(id: "tokens") { context in
            snapshot(
                sourceID: "tokens",
                context: context,
                documents: [document(id: "token:gram", title: "Gram")]
            )
        }
        let failed = StubSource(id: "apps") { _ in
            throw TestError.unavailable
        }
        let coordinator = UniversalSearchCoordinator(sources: [failed, successful])

        let refresh = try await coordinator.refresh(context: context)
        let results = await coordinator.search("gram")

        #expect(refresh.disposition == .applied)
        #expect(refresh.refreshedSourceIDs == [SearchSourceID("tokens")])
        #expect(refresh.failures.map(\.sourceID) == [SearchSourceID("apps")])
        #expect(results.hits.map(\.id) == [SearchEntityID("token:gram")])
    }

    @Test
    func `failed refresh keeps last successful snapshot in same context`() async throws {
        let loader = SequencedLoader(outcomes: [
            .success([document(id: "token:gram", title: "Gram")]),
            .failure,
        ])
        let source = StubSource(id: "tokens") { context in
            let documents = try await loader.next()
            return snapshot(sourceID: "tokens", context: context, documents: documents)
        }
        let coordinator = UniversalSearchCoordinator(sources: [source])

        _ = try await coordinator.refresh(context: context)
        let failedRefresh = try await coordinator.refresh(context: context)
        let results = await coordinator.search("gram")

        #expect(failedRefresh.failures.count == 1)
        #expect(results.hits.map(\.id) == [SearchEntityID("token:gram")])
    }

    @Test
    func `hydrates persisted snapshots before a provider refresh fails`() async throws {
        let cachedSnapshot = snapshot(
            sourceID: "tokens",
            context: context,
            documents: [document(id: "token:cached", title: "Cached Token")]
        )
        let store = StubIndexStore(snapshots: [cachedSnapshot])
        let source = StubSource(id: "tokens") { _ in
            throw TestError.unavailable
        }
        let coordinator = UniversalSearchCoordinator(
            sources: [source],
            indexStore: store
        )

        let refresh = try await coordinator.refresh(context: context)
        let results = await coordinator.search("cached")

        #expect(refresh.failures.map(\.sourceID) == [SearchSourceID("tokens")])
        #expect(results.hits.map(\.id) == [SearchEntityID("token:cached")])
    }

    @Test
    func `changing context clears old account data even when refresh fails`() async throws {
        let source = StubSource(id: "tokens") { context in
            guard context.scopeID == "account-a" else { throw TestError.unavailable }
            return snapshot(
                sourceID: "tokens",
                context: context,
                documents: [document(id: "token:private", title: "Private")]
            )
        }
        let coordinator = UniversalSearchCoordinator(sources: [source])
        _ = try await coordinator.refresh(context: context)

        let otherContext = UniversalSearchContext(
            scopeID: "account-b",
            network: "mainnet",
            localeIdentifier: "en"
        )
        _ = try await coordinator.refresh(context: otherContext)
        let results = await coordinator.search("private")
        let currentContext = await coordinator.currentContext()

        #expect(results.hits.isEmpty)
        #expect(currentContext == otherContext)
    }

    @Test
    func `shared snapshots survive an account switch without re-snapshotting`() async throws {
        let sharedCalls = CallCounter()
        let shared = StubSource(id: "history", scoping: .global) { context in
            await sharedCalls.increment()
            return snapshot(
                sourceID: "history",
                context: context,
                documents: [document(id: "site:example", title: "Example")]
            )
        }
        let account = StubSource(id: "tokens") { context in
            snapshot(
                sourceID: "tokens",
                context: context,
                documents: [document(id: "token:\(context.scopeID ?? "")", title: "Token")]
            )
        }
        let coordinator = UniversalSearchCoordinator(sources: [shared, account])
        _ = try await coordinator.refresh(context: context)

        let otherContext = UniversalSearchContext(
            scopeID: "account-b",
            network: "mainnet",
            localeIdentifier: "en"
        )
        _ = try await coordinator.refresh(
            context: otherContext,
            sourceIDs: coordinator.accountScopedSourceIDs
        )
        let results = await coordinator.search("example")

        #expect(coordinator.accountScopedSourceIDs == [SearchSourceID("tokens")])
        #expect(await sharedCalls.count == 1)
        #expect(results.hits.map(\.id) == [SearchEntityID("site:example")])
    }

    @Test
    func `returning to an account serves its cached snapshots without any source work`() async throws {
        let calls = CallCounter()
        let account = StubSource(id: "tokens") { context in
            await calls.increment()
            let title = context.scopeID == "account-a" ? "Alpha" : "Bravo"
            return snapshot(
                sourceID: "tokens",
                context: context,
                documents: [document(id: "token:\(context.scopeID ?? "")", title: title)]
            )
        }
        let coordinator = UniversalSearchCoordinator(sources: [account])
        let contextB = UniversalSearchContext(
            scopeID: "account-b",
            network: "mainnet",
            localeIdentifier: "en"
        )
        _ = try await coordinator.refresh(context: context)
        _ = try await coordinator.refresh(context: contextB, sourceIDs: coordinator.accountScopedSourceIDs)

        // Returning without requesting any source must serve account-a from its cached slot
        _ = try await coordinator.refresh(context: context, sourceIDs: [])
        let results = await coordinator.search("alpha")
        let leaked = await coordinator.search("bravo")

        #expect(await calls.count == 2)
        #expect(results.hits.map(\.id) == [SearchEntityID("token:account-a")])
        #expect(leaked.hits.isEmpty)
    }

    @Test
    func `newer refresh supersedes an older in-flight refresh`() async throws {
        let source = StubSource(id: "tokens") { context in
            if context.scopeID == "slow" {
                try await Task.sleep(for: .milliseconds(100))
            }
            let title = context.scopeID == "slow" ? "Old" : "New"
            return snapshot(
                sourceID: "tokens",
                context: context,
                documents: [document(id: "token:value", title: title)]
            )
        }
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let slowContext = UniversalSearchContext(
            scopeID: "slow",
            network: nil,
            localeIdentifier: "en"
        )
        let fastContext = UniversalSearchContext(
            scopeID: "fast",
            network: nil,
            localeIdentifier: "en"
        )

        let olderRefresh = Task {
            try await coordinator.refresh(context: slowContext)
        }
        try await Task.sleep(for: .milliseconds(10))
        let newerResult = try await coordinator.refresh(context: fastContext)
        let olderResult = try await olderRefresh.value
        let newResults = await coordinator.search("new")
        let oldResults = await coordinator.search("old")

        #expect(newerResult.disposition == .applied)
        #expect(olderResult.disposition == .superseded)
        #expect(newResults.hits.count == 1)
        #expect(oldResults.hits.isEmpty)
    }

    @Test
    func `returns immutable limited results with total count and revision`() async throws {
        let source = StubSource(id: "tokens") { context in
            snapshot(
                sourceID: "tokens",
                context: context,
                documents: [
                    document(id: "token:a", title: "Gram"),
                    document(id: "token:b", title: "Gram"),
                ]
            )
        }
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let refresh = try await coordinator.refresh(context: context)

        let results = await coordinator.search("gram", limit: 1)

        #expect(results.hits.count == 1)
        #expect(results.totalHitCount == 2)
        #expect(results.corpusRevision == refresh.corpusRevision)
        #expect(results.corpusDocumentCount == 2)
    }

    @Test
    func `publishes a fast source without waiting for slower sources`() async throws {
        let fast = StubSource(id: "fast") { context in
            snapshot(
                sourceID: "fast",
                context: context,
                documents: [document(id: "token:fast", title: "Fast")]
            )
        }
        let slow = StubSource(id: "slow") { context in
            try await Task.sleep(for: .milliseconds(200))
            return snapshot(
                sourceID: "slow",
                context: context,
                documents: [document(id: "token:slow", title: "Slow")]
            )
        }
        let recorder = ProgressRecorder()
        let coordinator = UniversalSearchCoordinator(sources: [slow, fast])

        let refresh = Task {
            try await coordinator.refresh(context: context) { progress in
                await recorder.record(progress)
            }
        }
        let firstProgress = await recorder.firstProgress()
        let partialResults = await coordinator.search("fast")

        #expect(firstProgress.sourceID == SearchSourceID("fast"))
        #expect(firstProgress.sourceDocumentCount == 1)
        #expect(firstProgress.corpusDocumentCount == 1)
        #expect(partialResults.hits.map(\.id) == [SearchEntityID("token:fast")])
        _ = try await refresh.value
    }

    @Test
    func `targeted refresh only reloads requested sources in the same context`() async throws {
        let calls = SourceCallRecorder()
        let tokens = StubSource(id: "tokens") { context in
            await calls.record("tokens")
            return snapshot(sourceID: "tokens", context: context, documents: [])
        }
        let apps = StubSource(id: "apps") { context in
            await calls.record("apps")
            return snapshot(sourceID: "apps", context: context, documents: [])
        }
        let coordinator = UniversalSearchCoordinator(sources: [tokens, apps])

        _ = try await coordinator.refresh(context: context)
        _ = try await coordinator.refresh(
            context: context,
            sourceIDs: [SearchSourceID("tokens")]
        )

        #expect(await calls.count(for: "tokens") == 2)
        #expect(await calls.count(for: "apps") == 1)
    }

    @Test
    func `query snapshot replacement is gated by context and revision`() async throws {
        let source = StubSource(id: "tokens") { context in
            snapshot(sourceID: "tokens", context: context, documents: [])
        }
        let coordinator = UniversalSearchCoordinator(sources: [source])
        _ = try await coordinator.refresh(context: context)
        let querySourceID = SearchSourceID("query")
        let first = UniversalSearchSourceSnapshot(
            sourceID: querySourceID,
            revision: "first",
            generatedAt: Date(timeIntervalSince1970: 1),
            documents: [document(id: "token:first", title: "First")]
        )
        let second = UniversalSearchSourceSnapshot(
            sourceID: querySourceID,
            revision: "second",
            generatedAt: Date(timeIntervalSince1970: 2),
            documents: [document(id: "token:second", title: "Second")]
        )
        let otherContext = UniversalSearchContext(
            scopeID: "account-b",
            network: "mainnet",
            localeIdentifier: "en"
        )

        #expect(await coordinator.replace(first, ifContext: context))
        #expect(await coordinator.replace(second, ifContext: otherContext) == false)
        await coordinator.replace(second, ifContext: context)
        await coordinator.remove(sourceID: querySourceID, ifRevision: "first")
        let retained = await coordinator.search("second")
        await coordinator.remove(sourceID: querySourceID, ifRevision: "second")
        let removed = await coordinator.search("second")

        #expect(retained.hits.map(\.id) == [SearchEntityID("token:second")])
        #expect(removed.hits.isEmpty)
    }
}

private actor ProgressRecorder {
    private var progress: UniversalSearchRefreshProgress?
    private var continuation: CheckedContinuation<UniversalSearchRefreshProgress, Never>?

    func record(_ progress: UniversalSearchRefreshProgress) {
        guard self.progress == nil else { return }
        self.progress = progress
        continuation?.resume(returning: progress)
        continuation = nil
    }

    func firstProgress() async -> UniversalSearchRefreshProgress {
        if let progress { return progress }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private actor SourceCallRecorder {
    private var counts: [String: Int] = [:]

    func record(_ sourceID: String) {
        counts[sourceID, default: 0] += 1
    }

    func count(for sourceID: String) -> Int {
        counts[sourceID, default: 0]
    }
}

private actor StubIndexStore: UniversalSearchIndexStore {
    private var storedSnapshots: [UniversalSearchSourceSnapshot]

    init(snapshots: [UniversalSearchSourceSnapshot]) {
        self.storedSnapshots = snapshots
    }

    func snapshots(
        forScopeKeys scopeKeys: Set<String>
    ) -> [UniversalSearchSourceSnapshot] {
        storedSnapshots
    }

    func replace(
        _ snapshot: UniversalSearchSourceSnapshot,
        scopeKey: String
    ) {
        storedSnapshots.removeAll { $0.sourceID == snapshot.sourceID }
        storedSnapshots.append(snapshot)
    }

    func removeSnapshot(
        sourceID: SearchSourceID,
        scopeKey: String
    ) {
        storedSnapshots.removeAll { $0.sourceID == sourceID }
    }

    func candidateEntityIDs(
        for query: UniversalSearchQuery,
        scopeKeys: Set<String>,
        limit: Int
    ) -> [SearchEntityID] {
        Array(storedSnapshots.flatMap(\.documents).map(\.id).prefix(limit))
    }
}

private struct StubSource: UniversalSearchSource {
    typealias Operation = @Sendable (UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot

    let sourceID: SearchSourceID
    let scoping: UniversalSearchSourceScoping
    let operation: Operation

    init(
        id: String,
        scoping: UniversalSearchSourceScoping = .account,
        operation: @escaping Operation
    ) {
        self.sourceID = SearchSourceID(id)
        self.scoping = scoping
        self.operation = operation
    }

    func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        try await operation(context)
    }
}

private actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private actor SequencedLoader {
    enum Outcome: Sendable {
        case success([SearchDocument])
        case failure
    }

    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func next() throws -> [SearchDocument] {
        guard !outcomes.isEmpty else { throw TestError.unavailable }
        switch outcomes.removeFirst() {
        case .success(let documents): return documents
        case .failure: throw TestError.unavailable
        }
    }
}

private enum TestError: Error {
    case unavailable
}

private func snapshot(
    sourceID: String,
    context: UniversalSearchContext,
    documents: [SearchDocument]
) -> UniversalSearchSourceSnapshot {
    UniversalSearchSourceSnapshot(
        sourceID: SearchSourceID(sourceID),
        revision: context.scopeID,
        generatedAt: Date(timeIntervalSince1970: 1),
        documents: documents
    )
}

private func document(id: String, title: String) -> SearchDocument {
    SearchDocument(
        id: SearchEntityID(id),
        kind: .token,
        fields: [.init(title, kind: .title)]
    )
}

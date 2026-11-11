import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCore
@testable import UniversalSearchFeature

@Suite("Universal Search index service", .serialized)
@MainActor
struct UniversalSearchIndexServiceTests {
    @Test
    func `replacing an immediate refresh does not starve indexing`() async throws {
        let source = RecordingSource()
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        service.start()
        defer { service.stop() }

        // Once maxPostpone is reached, multiple events can replace zero-delay tasks
        // before any of them gets its first turn on MainActor.
        service.setWalletReady(true)
        service.walletCore(event: .tokensChanged)
        service.walletCore(event: .tokensChanged)

        try await waitUntil { await coordinator.search("token").hits.count == 1 }
        let result = await coordinator.search("token")
        #expect(result.hits.map(\.id.rawValue) == ["token:account-a"])
        #expect(await source.contexts == [context("account-a")])
    }

    @Test
    func `stop and restart discard queued refreshes`() async throws {
        let source = RecordingSource()
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let selection = Selection()
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context(selection.accountID) },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        service.start()
        service.setWalletReady(true)
        service.stop()
        selection.accountID = "account-b"
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }

        try await waitUntil { await coordinator.search("token").hits.count == 1 }
        #expect(await source.contexts == [context("account-b")])
        #expect(await coordinator.search("token").hits.map(\.id.rawValue) == ["token:account-b"])
    }

    @Test
    func `wallet restart during a refresh keeps pending work for the latest account`() async throws {
        let source = RecordingSource(holdsFirstSnapshot: true)
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let selection = Selection()
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context(selection.accountID) },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil { await source.isHoldingSnapshot }

        service.setWalletReady(false)
        selection.accountID = "account-b"
        service.setWalletReady(true)
        service.walletCore(event: .tokensChanged)
        await source.releaseSnapshot()

        try await waitUntil {
            await coordinator.search("token").hits.map(\.id.rawValue) == ["token:account-b"]
        }
        #expect(await source.contexts == [context("account-a"), context("account-b")])
    }

    @Test
    func `invalidations during a refresh coalesce into one follow up`() async throws {
        let source = RecordingSource(holdsFirstSnapshot: true)
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .milliseconds(10))
        )
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil { await source.isHoldingSnapshot }

        for _ in 0..<10 {
            service.walletCore(event: .tokensChanged)
        }
        await source.releaseSnapshot()
        try await waitUntil { await source.contexts.count == 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await source.contexts == [context("account-a"), context("account-a")])
    }

    @Test
    func `a deleted Agent chat leaves the results of an open query at once`() async throws {
        let queryText = "знако"
        let deletedItem = ApiAgentV2ThreadListItem(thread: try makeThread(id: "deleted", title: "Знакомство с TON"))
        let keptItem = ApiAgentV2ThreadListItem(thread: try makeThread(id: "kept", title: "Знакомые адреса"))
        let loader = MutableThreadLoader(items: [deletedItem, keptItem])
        let coordinator = UniversalSearchCoordinator(sources: [
            UniversalSearchAgentConversationSource(loader: { query in await loader.load(query: query) }),
        ])
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        let recorder = UpdateRecorder()
        service.add(observer: recorder)
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil { await coordinator.browse().recentDocuments.count == 2 }

        // An open search session keeps the server's matches for its query as a query snapshot
        let querySource = UniversalSearchAgentConversationQuerySource(
            loader: { query in await loader.load(query: query) },
            debounce: .zero
        )
        let query = UniversalSearchQuery(queryText)
        for try await snapshot in querySource.snapshots(for: query, context: context("account-a")) {
            await coordinator.replace(snapshot)
        }
        let openQueryHits = await coordinator.search(queryText).hits.map(\.id.rawValue)
        #expect(Set(openQueryHits) == ["agent-chat:deleted", "agent-chat:kept"])

        await loader.setItems([keptItem])
        service.walletCore(event: .agentThreadDeleted(threadId: "deleted"))

        let deletedID = SearchEntityID("agent-chat:deleted")
        try await waitUntil { recorder.removedIDs == [deletedID] }
        #expect(await coordinator.search(queryText).hits.map(\.id.rawValue) == ["agent-chat:kept"])
        #expect(await coordinator.browse().recentDocuments.map(\.id) == [SearchEntityID("agent-chat:kept")])

        await coordinator.remove(sourceID: querySource.sourceID)
        for try await snapshot in querySource.snapshots(for: query, context: context("account-a")) {
            await coordinator.replace(snapshot)
        }
        #expect(await coordinator.search(queryText).hits.map(\.id.rawValue) == ["agent-chat:kept"])
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition(), "Search refresh did not make progress")
    }
}

@MainActor
private final class Selection {
    var accountID = "account-a"
}

private func context(_ accountID: String) -> UniversalSearchContext {
    UniversalSearchContext(scopeID: accountID, network: "mainnet", localeIdentifier: "en")
}

private func makeThread(id: String, title: String) throws -> ApiAgentV2ThreadSummary {
    let value: [String: Any] = [
        "id": id,
        "revision": 1,
        "createdAt": "2026-10-18T09:00:00Z",
        "updatedAt": "2026-10-18T10:00:00Z",
        "lastActivityAt": "2026-10-18T10:00:00Z",
        "messageCount": 2,
        "title": title,
        "hasCustomTitle": true,
    ]
    return try JSONDecoder().decode(
        ApiAgentV2ThreadSummary.self,
        from: JSONSerialization.data(withJSONObject: value)
    )
}

@MainActor
private final class UpdateRecorder: UniversalSearchIndexServiceObserver {
    private(set) var removedIDs: [SearchEntityID] = []

    func universalSearchIndexService(
        _: UniversalSearchIndexService,
        didUpdate update: UniversalSearchIndexUpdate
    ) {
        if case .documentRemoved(let id) = update.kind {
            removedIDs.append(id)
        }
    }
}

private actor MutableThreadLoader {
    private var items: [ApiAgentV2ThreadListItem]

    init(items: [ApiAgentV2ThreadListItem]) {
        self.items = items
    }

    func setItems(_ items: [ApiAgentV2ThreadListItem]) {
        self.items = items
    }

    func load(query _: String?) -> [ApiAgentV2ThreadListItem] {
        items
    }
}

private actor RecordingSource: UniversalSearchSource {
    nonisolated let sourceID = WalletCoreTokenSearchSource.id
    private(set) var contexts: [UniversalSearchContext] = []
    private let holdsFirstSnapshot: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var isHoldingSnapshot: Bool { continuation != nil }

    init(holdsFirstSnapshot: Bool = false) {
        self.holdsFirstSnapshot = holdsFirstSnapshot
    }

    func releaseSnapshot() {
        continuation?.resume()
        continuation = nil
    }

    func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        contexts.append(context)
        if holdsFirstSnapshot, contexts.count == 1 {
            await withCheckedContinuation { continuation = $0 }
        }
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            generatedAt: Date(),
            documents: [SearchDocument(
                id: SearchEntityID("token:\(context.scopeID ?? "")"),
                kind: .token,
                fields: [SearchField("Token", kind: .title)]
            )]
        )
    }
}

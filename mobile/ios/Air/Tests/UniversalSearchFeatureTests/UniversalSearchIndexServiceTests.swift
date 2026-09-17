import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
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

import Perception
import Testing
@testable import WalletCore

@Suite("Draft Engine")
@MainActor
struct DraftEngineTests {
    @Test
    func `successful load produces an exact current snapshot`() async throws {
        let harness = Harness()

        harness.source.value = 1
        harness.startEngine()

        #expect(harness.engine.request == 1)
        #expect(harness.engine.isLoading)
        #expect(harness.engine.current == nil)
        #expect(harness.engine.displayed == nil)
        await harness.probe.waitUntilRequested(1)

        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }

        let current = try #require(harness.engine.current)
        #expect(current.request == 1)
        #expect(current.draft == "one")
        #expect(harness.engine.displayed == "one")
        #expect(!harness.engine.isLoading)
        #expect(!harness.engine.isRefreshing)
        #expect(harness.engine.failure == nil)
    }

    @Test
    func `superseded load cannot publish a stale draft`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)

        harness.source.value = 2

        #expect(harness.engine.current == nil)
        #expect(harness.engine.isLoading)

        try await harness.probe.succeed(request: 1, draft: "stale")
        await harness.probe.waitUntilRequested(2)

        #expect(harness.engine.current == nil)
        #expect(harness.engine.isLoading)

        try await harness.probe.succeed(request: 2, draft: "current")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.current?.request == 2)
        #expect(harness.engine.current?.draft == "current")
    }

    @Test
    func `request changes reload while unrelated state changes do not`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }

        harness.source.value = 1
        harness.source.noise += 1
        await settle()

        #expect(await harness.probe.requestCount(for: 1) == 1)
        #expect(harness.engine.current?.draft == "one")
    }

    @Test
    func `refresh keeps the current draft visible while revalidating`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "first")
        await waitUntil { harness.engine.current != nil }

        harness.engine.refresh()
        await harness.probe.waitUntilRequested(1, count: 2)

        #expect(harness.engine.current?.draft == "first")
        #expect(harness.engine.displayed == "first")
        #expect(harness.engine.isRefreshing)
        #expect(!harness.engine.isLoading)

        try await harness.probe.succeed(request: 1, draft: "refreshed")
        await waitUntil { harness.engine.current?.draft == "refreshed" }

        #expect(!harness.engine.isRefreshing)
    }

    @Test
    func `refresh failure keeps the current draft and exposes the failure`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }

        harness.engine.refresh()
        await harness.probe.waitUntilRequested(1, count: 2)
        try await harness.probe.fail(request: 1, error: TestError.expected)
        await waitUntil { harness.engine.failure != nil }

        #expect(harness.engine.current?.draft == "one")
        #expect(harness.engine.displayed == "one")
        #expect(!harness.engine.canRetry)
        #expect(!harness.engine.isLoading)
    }

    @Test
    func `failed request offers retry until it recovers`() async throws {
        let harness = Harness()
        var failedRequests: [Int] = []
        harness.source.value = 4
        harness.startEngine()
        harness.engine.onFailure = { request, _ in
            failedRequests.append(request)
        }
        await harness.probe.waitUntilRequested(4)
        try await harness.probe.fail(request: 4, error: TestError.expected)
        await waitUntil { harness.engine.failure != nil }

        #expect(harness.engine.canRetry)
        #expect(harness.engine.failure is TestError)
        #expect(harness.engine.current == nil)
        #expect(!harness.engine.isLoading)
        #expect(failedRequests == [4])

        harness.engine.retry()

        #expect(harness.engine.failure == nil)
        #expect(harness.engine.isLoading)
        await harness.probe.waitUntilRequested(4, count: 2)

        try await harness.probe.succeed(request: 4, draft: "recovered")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.current?.draft == "recovered")
        #expect(failedRequests == [4])
    }

    @Test
    func `failure is dropped when the request moves on`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.fail(request: 1, error: TestError.expected)
        await waitUntil { harness.engine.failure != nil }

        harness.source.value = 2

        #expect(harness.engine.failure == nil)
        #expect(harness.engine.isLoading)
    }

    @Test
    func `uncancelled cancellation error is exposed as a failure`() async throws {
        let harness = Harness()
        harness.source.value = 5
        harness.startEngine()
        await harness.probe.waitUntilRequested(5)
        try await harness.probe.fail(request: 5, error: CancellationError())
        await waitUntil { harness.engine.failure != nil }

        #expect(harness.engine.canRetry)
        #expect(harness.engine.failure is CancellationError)
    }

    @Test
    func `displayed falls back to the last draft in the same scope`() async throws {
        let harness = Harness(sameScope: { $0 / 10 == $1 / 10 })
        harness.source.value = 11
        harness.startEngine()
        await harness.probe.waitUntilRequested(11)
        try await harness.probe.succeed(request: 11, draft: "a")
        await waitUntil { harness.engine.current != nil }

        harness.source.value = 12

        #expect(harness.engine.current == nil)
        #expect(harness.engine.displayed == "a")

        await harness.probe.waitUntilRequested(12)
        try await harness.probe.succeed(request: 12, draft: "b")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.displayed == "b")

        harness.source.value = 25

        #expect(harness.engine.displayed == nil)
    }

    @Test
    func `loader receives the previous draft from the same scope`() async throws {
        let harness = Harness(sameScope: { $0 / 10 == $1 / 10 })
        harness.source.value = 11
        harness.startEngine()
        await harness.probe.waitUntilRequested(11)
        try await harness.probe.succeed(request: 11, draft: "a")
        await waitUntil { harness.engine.current != nil }

        harness.source.value = 12
        await harness.probe.waitUntilRequested(12)
        try await harness.probe.succeed(request: 12, draft: "b")
        await waitUntil { harness.engine.current != nil }

        harness.source.value = 25
        await harness.probe.waitUntilRequested(25)

        #expect(await harness.probe.previous(for: 11) == [nil])
        #expect(await harness.probe.previous(for: 12) == ["a"])
        #expect(await harness.probe.previous(for: 25) == [nil])
    }

    @Test
    func `debounce policy delays typed transitions and skips picks`() async throws {
        let harness = Harness(debounce: { from, to in
            guard let from, from / 10 == to / 10 else { return .zero }
            return .seconds(5)
        })
        harness.source.value = 11
        harness.startEngine()
        await harness.probe.waitUntilRequested(11)
        try await harness.probe.succeed(request: 11, draft: "a")
        await waitUntil { harness.engine.current != nil }

        harness.source.value = 12
        await settle()

        #expect(await harness.probe.requestCount(for: 12) == 0)
        #expect(harness.engine.isLoading)

        harness.engine.refresh()
        await settle()

        #expect(await harness.probe.requestCount(for: 11) == 1)
        #expect(await harness.probe.requestCount(for: 12) == 0)

        harness.source.value = 21
        await harness.probe.waitUntilRequested(21)

        #expect(await harness.probe.requestCount(for: 12) == 0)

        try await harness.probe.succeed(request: 21, draft: "c")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.current?.request == 21)
    }

    @Test
    func `one load runs at a time and the latest request follows`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)

        harness.source.value = 2
        await settle()
        harness.source.value = 3
        await settle()

        #expect(await harness.probe.requestCount(for: 2) == 0)
        #expect(await harness.probe.requestCount(for: 3) == 0)

        try await harness.probe.succeed(request: 1, draft: "stale")
        await harness.probe.waitUntilRequested(3)

        #expect(await harness.probe.requestCount(for: 2) == 0)

        try await harness.probe.succeed(request: 3, draft: "three")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.current?.request == 3)
    }

    @Test
    func `returning to the request in flight does not queue a duplicate`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)

        harness.source.value = 2
        await settle()
        harness.source.value = 1
        await settle()
        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }
        await settle()

        #expect(await harness.probe.requestCount(for: 1) == 1)
        #expect(await harness.probe.requestCount(for: 2) == 0)
        #expect(!harness.engine.isRefreshing)
    }

    @Test
    func `feedback consumes a queued refresh without duplicating the new load`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.engine.onLoad = { [weak source = harness.source] snapshot in
            if snapshot.request == 1 {
                source?.value = 2
            }
        }
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        harness.engine.refresh()
        try await harness.probe.succeed(request: 1, draft: "one")
        await harness.probe.waitUntilRequested(2)
        try await harness.probe.succeed(request: 2, draft: "two")
        await waitUntil { harness.engine.current?.request == 2 }
        await settle()

        #expect(await harness.probe.requestCount(for: 2) == 1)
        #expect(!harness.engine.isRefreshing)
    }

    @Test
    func `feedback from onLoad reloads immediately bypassing debounce`() async throws {
        let harness = Harness(debounce: { from, _ in
            from == nil ? .zero : .seconds(5)
        })
        harness.source.value = 1
        harness.startEngine()
        harness.engine.onLoad = { snapshot in
            if snapshot.request == 1 {
                harness.source.value = 2
            }
        }
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "one")
        await harness.probe.waitUntilRequested(2)

        try await harness.probe.succeed(request: 2, draft: "two")
        await waitUntil { harness.engine.current?.request == 2 }

        #expect(harness.engine.current?.draft == "two")
    }

    @Test
    func `refresh inside an input observer is not retriggered by publishes`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }

        // An owner-style wallet-event observer: reads an input, calls
        // refresh(). Engine state transitions must not re-trigger it.
        let retriggered = Flag()
        withPerceptionTracking {
            _ = harness.source.noise
            harness.engine.refresh()
        } onChange: {
            Task { @MainActor in
                retriggered.value = true
            }
        }
        await harness.probe.waitUntilRequested(1, count: 2)
        try await harness.probe.succeed(request: 1, draft: "two")
        await waitUntil { harness.engine.current?.draft == "two" }
        await settle()

        #expect(!retriggered.value)
        #expect(await harness.probe.requestCount(for: 1) == 2)
    }

    @Test
    func `synchronize applies a programmatic change without debounce`() async throws {
        let harness = Harness(debounce: { from, _ in
            from == nil ? .zero : .seconds(5)
        })
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }

        harness.source.value = 2
        harness.engine.synchronize()
        await harness.probe.waitUntilRequested(2)

        try await harness.probe.succeed(request: 2, draft: "two")
        await waitUntil { harness.engine.current?.draft == "two" }

        harness.engine.synchronize()
        await settle()

        #expect(await harness.probe.requestCount(for: 2) == 1)
    }

    @Test
    func `queued refresh supersedes an in-flight failure`() async throws {
        let harness = Harness()
        var failures = 0
        harness.source.value = 1
        harness.startEngine()
        harness.engine.onFailure = { _, _ in
            failures += 1
        }
        await harness.probe.waitUntilRequested(1)

        harness.engine.refresh()
        try await harness.probe.fail(request: 1, error: TestError.expected)
        await harness.probe.waitUntilRequested(1, count: 2)

        #expect(harness.engine.failure == nil)
        #expect(harness.engine.isLoading)
        #expect(failures == 0)

        try await harness.probe.succeed(request: 1, draft: "recovered")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.current?.draft == "recovered")
    }

    @Test
    func `queue drain defers to a pending debounce`() async throws {
        let harness = Harness(debounce: { from, to in
            from != nil && to == 3 ? .milliseconds(150) : .zero
        })
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)

        harness.source.value = 2
        await settle()
        harness.source.value = 3
        await settle()

        try await harness.probe.succeed(request: 1, draft: "stale")
        await harness.probe.waitUntilRequested(3)

        // The debounced transition owns the reload: the queued follow-up
        // must not fire an extra load for a superseded request.
        #expect(await harness.probe.requestCount(for: 2) == 0)
        #expect(await harness.probe.requestCount(for: 3) == 1)

        try await harness.probe.succeed(request: 3, draft: "three")
        await waitUntil { harness.engine.current != nil }
        await settle()

        #expect(await harness.probe.requestCount(for: 3) == 1)
    }

    @Test
    func `starting a load cancels the scheduled tick`() async throws {
        let harness = Harness(refreshInterval: .milliseconds(200))
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "first")
        await waitUntil { harness.engine.current != nil }

        harness.engine.refresh()
        await harness.probe.waitUntilRequested(1, count: 2)
        // Outlive the tick that was scheduled before the refresh started.
        try? await Task.sleep(for: .milliseconds(300))
        try await harness.probe.succeed(request: 1, draft: "second")
        await waitUntil { harness.engine.current?.draft == "second" }
        await settle()

        // The superseded tick must not queue a third load behind the
        // explicit refresh.
        #expect(await harness.probe.requestCount(for: 1) == 2)
    }

    @Test
    func `pause stops loading and resume catches up`() async throws {
        let harness = Harness()
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "one")
        await waitUntil { harness.engine.current != nil }

        harness.engine.pause()
        harness.source.value = 2
        await settle()

        #expect(await harness.probe.requestCount(for: 2) == 0)
        #expect(!harness.engine.isLoading)

        harness.engine.resume()
        await harness.probe.waitUntilRequested(2)

        try await harness.probe.succeed(request: 2, draft: "two")
        await waitUntil { harness.engine.current != nil }

        #expect(harness.engine.current?.draft == "two")
    }

    @Test
    func `load handlers can change the next refresh interval`() async throws {
        let harness = Harness(refreshInterval: .seconds(60))
        harness.source.value = 1
        harness.engine.onFailure = { [weak engine = harness.engine] _, _ in
            engine?.refreshInterval = .milliseconds(25)
        }
        harness.engine.onLoad = { [weak engine = harness.engine] _ in
            engine?.refreshInterval = nil
        }
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.fail(request: 1, error: TestError.expected)

        await harness.probe.waitUntilRequested(1, count: 2)
        try await harness.probe.succeed(request: 1, draft: "recovered")
        await waitUntil { harness.engine.current != nil }
        try await Task.sleep(for: .milliseconds(100))

        #expect(harness.engine.current?.draft == "recovered")
        #expect(await harness.probe.requestCount(for: 1) == 2)
    }

    @Test
    func `periodic refresh revalidates the current request`() async throws {
        let harness = Harness(refreshInterval: .milliseconds(25))
        harness.source.value = 1
        harness.startEngine()
        await harness.probe.waitUntilRequested(1)
        try await harness.probe.succeed(request: 1, draft: "first")

        await harness.probe.waitUntilRequested(1, count: 2)

        #expect(harness.engine.current?.draft == "first")
        #expect(harness.engine.isRefreshing)

        try await harness.probe.succeed(request: 1, draft: "second")
        await waitUntil { harness.engine.current?.draft == "second" }
    }
}

// MARK: - Harness

@Perceptible
@MainActor
private final class RequestSource {
    var value: Int?
    var noise = 0
}

@MainActor
private final class Flag {
    var value = false
}

@MainActor
private final class Harness {
    let source = RequestSource()
    let probe: DraftLoaderProbe
    let engine: DraftEngine<Int, String>

    init(
        debounce: @escaping DraftEngine<Int, String>.DebouncePolicy = { _, _ in .zero },
        refreshInterval: Duration? = nil,
        sameScope: @escaping DraftEngine<Int, String>.ScopePredicate = { $0 == $1 }
    ) {
        let probe = DraftLoaderProbe()
        self.probe = probe
        engine = DraftEngine(
            debounce: debounce,
            refreshInterval: refreshInterval,
            sameScope: sameScope,
            load: { request, previous in
                try await probe.load(request, previous: previous)
            }
        )
    }

    func startEngine() {
        let source = source
        engine.start { source.value }
    }
}

private enum TestError: Error {
    case expected
    case missingPendingRequest(Int)
}

private actor DraftLoaderProbe {
    private struct RequestWaiter {
        let request: Int
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requests: [Int] = []
    private var previousDrafts: [Int: [String?]] = [:]
    private var pending: [Int: [CheckedContinuation<String, any Error>]] = [:]
    private var requestWaiters: [RequestWaiter] = []

    func load(_ request: Int, previous: String?) async throws -> String {
        requests.append(request)
        previousDrafts[request, default: []].append(previous)
        resumeSatisfiedRequestWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            pending[request, default: []].append(continuation)
        }
    }

    func requestCount(for request: Int) -> Int {
        requests.count(where: { $0 == request })
    }

    func previous(for request: Int) -> [String?] {
        previousDrafts[request] ?? []
    }

    func waitUntilRequested(_ request: Int, count: Int = 1) async {
        guard requestCount(for: request) < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(RequestWaiter(
                request: request,
                count: count,
                continuation: continuation
            ))
        }
    }

    func succeed(request: Int, draft: String) throws {
        try takePendingRequest(request).resume(returning: draft)
    }

    func fail(request: Int, error: any Error) throws {
        try takePendingRequest(request).resume(throwing: error)
    }

    private func takePendingRequest(
        _ request: Int
    ) throws -> CheckedContinuation<String, any Error> {
        guard var continuations = pending[request],
              !continuations.isEmpty else {
            throw TestError.missingPendingRequest(request)
        }
        let continuation = continuations.removeFirst()
        pending[request] = continuations
        return continuation
    }

    private func resumeSatisfiedRequestWaiters() {
        var remaining: [RequestWaiter] = []
        for waiter in requestWaiters {
            if requestCount(for: waiter.request) >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        requestWaiters = remaining
    }
}

@MainActor
private func settle() async {
    for _ in 0..<50 {
        await Task.yield()
    }
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<1_000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    Issue.record("Timed out waiting for engine state")
}

import Foundation
import os
import Testing
import WalletContext
@testable import WalletCore

@Suite("JS bridge storage", .timeLimit(.minutes(1)))
struct JSBridgeStorageTests {
    private typealias Response = JSBridgeStorage.Response
    private typealias Request = (method: JSBridgeStorage.Method, key: String?, value: String?)

    @Test @MainActor
    func queuedOperationsPreserveStorageOrderOffMainThread() async throws {
        let provider = StorageProbe()
        let storage = JSBridgeStorage(provider: provider)
        let results = await enqueueBatch(storage, requests: [
            (.set, "a", "1"), (.get, "a", nil),
            (.set, "a", "2"), (.get, "a", nil), (.keys, nil, nil),
            (.remove, "a", nil), (.get, "a", nil),
            (.set, "b", "3"), (.clear, nil, nil), (.keys, nil, nil),
        ])

        #expect(try results.map { try $0.get() } == [
            .void, .value("1"), .void, .value("2"), .keys(["a"]),
            .void, .value(nil), .void, .void, .keys([]),
        ])
        #expect(provider.calls.withLock { $0.count } == 11)
        #expect(provider.calls.withLock { $0.allSatisfy { !$0.isMainThread } })
    }

    @Test @MainActor
    func blockedWriteAllowsMainActorToRunAndReadWaitsForWrite() async throws {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let provider = StorageProbe(beforeStore: {
            continuation.yield(())
            continuation.finish()
            _ = release.wait(timeout: .now() + 5)
        })
        let storage = JSBridgeStorage(provider: provider)
        let pending = Task {
            await enqueueBatch(storage, requests: [(.set, "a", "1"), (.get, "a", nil)])
        }

        for await _ in started { break }
        // This main-actor continuation must run while the provider's write is blocked.
        #expect(provider.calls.withLock { $0.map(\.method) } == [.set])
        release.signal()

        let results = await pending.value
        #expect(try results.map { try $0.get() } == [.void, .value("1")])
        #expect(provider.calls.withLock { $0.allSatisfy { !$0.isMainThread } })
    }

    @Test(arguments: [JSBridgeStorage.Method.get, .set, .remove])
    func storageErrorsPropagateAndLaterRequestsStillComplete(method: JSBridgeStorage.Method) async throws {
        let storage = JSBridgeStorage(provider: StorageProbe(failingMethod: method))
        let results = await enqueueBatch(storage, requests: [(method, "a", "1"), (.keys, nil, nil)])

        guard case .failure(KeychainStorageProviderError.keychain(-50)) = results[0] else {
            Issue.record("Expected the provider's keychain error")
            return
        }
        #expect(try results[1].get() == .keys([]))
    }

    @Test
    func missingArgumentsFailWithoutCallingStorage() async {
        let provider = StorageProbe()
        let results = await enqueueBatch(JSBridgeStorage(provider: provider), requests: [
            (.get, nil, nil), (.set, nil, "1"), (.set, "a", nil), (.remove, nil, nil),
        ])
        for result in results {
            guard case .failure(KeychainStorageProviderError.invalidValue) = result else {
                Issue.record("Expected invalid storage arguments to fail")
                continue
            }
        }
        #expect(provider.calls.withLock { $0.isEmpty })
    }

    private nonisolated(nonsending) func enqueueBatch(
        _ storage: JSBridgeStorage,
        requests: [Request]
    ) async -> [Result<Response, any Error>] {
        let results = OSAllocatedUnfairLock(initialState: [Result<Response, any Error>]())
        return await withCheckedContinuation { continuation in
            for request in requests {
                storage.enqueue(request.method, key: request.key, value: request.value) { result in
                    let completed = results.withLock { results in
                        results.append(result)
                        return results
                    }
                    if completed.count == requests.count {
                        continuation.resume(returning: completed)
                    }
                }
            }
        }
    }
}

private final class StorageProbe: IKeychainStorageProvider, Sendable {
    struct Call: Sendable {
        let method: JSBridgeStorage.Method
        let isMainThread: Bool
    }

    let calls = OSAllocatedUnfairLock(initialState: [Call]())
    private let values = OSAllocatedUnfairLock(initialState: [String: String]())
    private let failingMethod: JSBridgeStorage.Method?
    private let beforeStore: (@Sendable () -> Void)?

    init(failingMethod: JSBridgeStorage.Method? = nil, beforeStore: (@Sendable () -> Void)? = nil) {
        self.failingMethod = failingMethod
        self.beforeStore = beforeStore
    }

    func load(key: String) throws -> String? {
        try record(.get)
        return values.withLock { $0[key] }
    }

    func store(key: String, value: String) throws {
        try record(.set)
        beforeStore?()
        values.withLock { $0[key] = value }
    }

    func removeOrThrow(key: String) throws {
        try record(.remove)
        _ = values.withLock { $0.removeValue(forKey: key) }
    }

    func keys() -> [String] {
        try? record(.keys)
        return values.withLock { $0.keys.sorted() }
    }

    func remove(key: String) -> Bool {
        do {
            try removeOrThrow(key: key)
            return true
        } catch {
            return false
        }
    }

    func set(key: String, value: String) -> Bool { fatalError("Unexpected legacy set") }
    func get(key: String) -> (Bool, String?) { fatalError("Unexpected legacy get") }

    private func record(_ method: JSBridgeStorage.Method) throws {
        calls.withLock { $0.append(Call(method: method, isMainThread: Thread.isMainThread)) }
        if method == failingMethod {
            throw KeychainStorageProviderError.keychain(-50)
        }
    }
}

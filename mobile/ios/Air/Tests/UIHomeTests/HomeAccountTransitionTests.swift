import Testing
import UIKit
import WalletCore
@testable import UIHome

@MainActor
@Suite("Home account transition", .serialized)
struct HomeAccountTransitionTests {
    @Test
    func preparationDoesNotChangeTheDisplayedAccountAndLatestRequestWins() async throws {
        let transition = HomeAccountTransition<String>()
        let loader = Loader()
        var commits: [String] = []
        transition.request(accountId: "a", prepare: { "a" }, commit: { commits.append($0) })
        try await wait { commits == ["a"] }

        for id in ["b", "c"] {
            transition.request(accountId: id, prepare: { await loader.load(id) }, commit: { commits.append($0) })
            try await wait { loader.pending[id] != nil }
        }
        #expect(transition.displayedAccountId == "a")
        loader.complete("c")
        try await wait { commits == ["a", "c"] }
        loader.complete("b")
        try await Task.sleep(for: .milliseconds(20))
        #expect(commits == ["a", "c"])
        #expect(transition.displayedAccountId == "c")
    }

    @Test
    func returningToTheDisplayedAccountCancelsAnUnfinishedSwitch() async throws {
        let transition = HomeAccountTransition<String>()
        let loader = Loader()
        var commits: [String] = []
        transition.request(accountId: "a", prepare: { "a" }, commit: { commits.append($0) })
        try await wait { commits == ["a"] }
        transition.request(accountId: "b", prepare: { await loader.load("b") }, commit: { commits.append($0) })
        try await wait { loader.pending["b"] != nil }
        transition.request(accountId: "a", prepare: { "unexpected" }, commit: { commits.append($0) })
        loader.complete("b")
        try await Task.sleep(for: .milliseconds(20))
        #expect(commits == ["a"])
        #expect(transition.displayedAccountId == "a")
    }

    @Test
    func duplicateNotificationsDoNotRestartPreparationOrCommitTwice() async throws {
        let transition = HomeAccountTransition<String>()
        let loader = Loader()
        var commits: [String] = []
        transition.request(accountId: "a", prepare: { await loader.load("a") }, commit: { commits.append($0) })
        try await wait { loader.pending["a"] != nil }
        transition.request(accountId: "a", prepare: { "unexpected" }, commit: { commits.append($0) })
        loader.complete("a")
        try await wait { commits == ["a"] }
        transition.request(accountId: "a", prepare: { "unexpected" }, commit: { commits.append($0) })
        try await Task.sleep(for: .milliseconds(20))
        #expect(commits == ["a"])
    }

    @Test
    func anInvalidPreparationCanBeRetried() async throws {
        let transition = HomeAccountTransition<String>()
        var prepared = false
        var commits: [String] = []
        transition.request(accountId: "a", prepare: { prepared = true; return nil }, commit: { commits.append($0) })
        try await wait { prepared }
        #expect(transition.displayedAccountId == nil)
        transition.request(accountId: "a", prepare: { "a" }, commit: { commits.append($0) })
        try await wait { commits == ["a"] }
    }

    private final class Loader {
        var pending: [String: CheckedContinuation<String?, Never>] = [:]
        func load(_ id: String) async -> String? {
            await withCheckedContinuation { pending[id] = $0 }
        }
        func complete(_ id: String) {
            pending.removeValue(forKey: id)?.resume(returning: id)
        }
    }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

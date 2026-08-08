import Testing
import ProtectedAction
@testable import UIProtectedAction
import WalletCore

@Suite("Activity Waiter")
@MainActor
struct ActivityWaiterTests {
    @Test
    func `exact activity emitted before the latest submission is retained`() async {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .seconds(1)
        )
        waiter.receive(accountId: "account", activities: [activity(id: "expected")])
        waiter.markSubmissionStarted()

        let result = await waiter.wait(
            receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
            matches: { activity, _ in activity.id == "expected" }
        )

        guard case .activity(let activity) = result else {
            Issue.record("Expected activity")
            return
        }
        #expect(activity.id == "expected")
    }

    @Test
    func `fallback ignores activities observed before submission`() async {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .seconds(1)
        )
        waiter.receive(accountId: "account", activities: [activity(id: "candidate-before")])
        waiter.markSubmissionStarted()
        let task = Task { @MainActor in
            await waiter.wait(
                receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
                matches: { _, _ in false },
                fallbackMatches: { activity, _ in activity.id.hasPrefix("candidate") }
            )
        }
        await Task.yield()

        waiter.receive(accountId: "account", activities: [activity(id: "candidate-after")])

        guard case .activity(let activity) = await task.value else {
            Issue.record("Expected post-submission fallback activity")
            return
        }
        #expect(activity.id == "candidate-after")
    }

    @Test
    func `latest submission watermark excludes activities observed while awaiting mfa`() async {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .seconds(1)
        )
        waiter.markSubmissionStarted()
        waiter.receive(accountId: "account", activities: [activity(id: "candidate-before-mfa")])
        waiter.markSubmissionStarted()
        let task = Task { @MainActor in
            await waiter.wait(
                receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
                matches: { _, _ in false },
                fallbackMatches: { activity, _ in activity.id.hasPrefix("candidate") }
            )
        }
        await Task.yield()

        waiter.receive(accountId: "account", activities: [activity(id: "candidate-after-mfa")])

        guard case .activity(let activity) = await task.value else {
            Issue.record("Expected post-MFA fallback activity")
            return
        }
        #expect(activity.id == "candidate-after-mfa")
    }

    @Test
    func `timeout starts only after authorization completes`() async throws {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .milliseconds(10)
        )
        try await Task.sleep(for: .milliseconds(20))
        waiter.receive(accountId: "account", activities: [activity(id: "expected")])

        let result = await waiter.wait(
            receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
            matches: { activity, _ in activity.id == "expected" }
        )

        guard case .activity(let activity) = result else {
            Issue.record("Expected activity")
            return
        }
        #expect(activity.id == "expected")
    }

    @Test
    func `activities for another account are ignored`() async {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .seconds(1)
        )
        let task = Task { @MainActor in
            await waiter.wait(
                receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
                matches: { activity, _ in activity.id == "expected" }
            )
        }
        await Task.yield()

        waiter.receive(accountId: "other", activities: [activity(id: "expected")])
        waiter.receive(accountId: "account", activities: [activity(id: "expected")])

        guard case .activity(let activity) = await task.value else {
            Issue.record("Expected activity")
            return
        }
        #expect(activity.id == "expected")
    }

    @Test
    func `missing activity times out`() async {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .milliseconds(10)
        )

        let result = await waiter.wait(
            receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
            matches: { _, _ in true }
        )

        guard case .timedOut = result else {
            Issue.record("Expected timeout")
            return
        }
    }

    @Test
    func `task cancellation cancels waiter`() async {
        let waiter = ActivityWaiter(
            accountId: "account",
            sources: [.local],
            timeout: .seconds(1)
        )
        let task = Task { @MainActor in
            await waiter.wait(
                receipt: ActionSubmissionReceipt<ApiMfaProtectedResult>(),
                matches: { _, _ in true }
            )
        }
        await Task.yield()

        task.cancel()

        guard case .cancelled = await task.value else {
            Issue.record("Expected cancellation")
            return
        }
    }
}

private func activity(id: String) -> ApiActivity {
    .transaction(
        ApiTransactionActivity(
            id: id,
            kind: "transaction",
            externalMsgHashNorm: nil,
            timestamp: 0,
            amount: 0,
            fromAddress: "from",
            toAddress: "to",
            comment: nil,
            encryptedComment: nil,
            fee: 0,
            slug: "toncoin",
            isIncoming: false,
            normalizedAddress: nil,
            type: nil,
            metadata: nil,
            nft: nil,
            status: .pendingTrusted
        )
    )
}

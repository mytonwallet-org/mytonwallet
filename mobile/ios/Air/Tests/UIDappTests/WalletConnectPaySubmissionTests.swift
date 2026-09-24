import Testing
@testable import UIDapp

@MainActor
@Suite("WalletConnect Pay dismissal")
struct WalletConnectPaySubmissionTests {
    private enum TestError: Error { case failed }

    @Test
    func `dismissal before signing cancels once and prevents submission`() async {
        var cancellations = 0
        var dismissals = 0
        let submission = WalletConnectPaySubmission(
            onCancel: { cancellations += 1 }, onDismiss: { dismissals += 1 }
        )
        submission.dismiss()
        submission.dismiss()
        var didSubmit = false
        await #expect(throws: CancellationError.self) {
            try await submission.submit { didSubmit = true }
        }
        #expect(!didSubmit)
        #expect(cancellations == 1)
        #expect(dismissals == 1)
    }

    @Test(arguments: [false, true])
    func `dismissal during signing lets the operation finish before deciding cancellation`(fails: Bool) async throws {
        var cancellations = 0
        var dismissals = 0
        let submission = WalletConnectPaySubmission(
            onCancel: { cancellations += 1 }, onDismiss: { dismissals += 1 }
        )
        let operation = SuspendedOperation()
        let task = Task {
            try await submission.submit { try await operation.run() }
        }
        await operation.waitForStart()
        await #expect(throws: CancellationError.self) {
            try await submission.submit { Issue.record("Duplicate submission") }
        }
        submission.dismiss()
        submission.dismiss()
        #expect(dismissals == 1)
        #expect(cancellations == 0)
        #expect(!task.isCancelled)

        operation.finish(fails ? .failure(TestError.failed) : .success(()))
        if fails {
            await #expect(throws: TestError.self) { try await task.value }
        } else {
            try await task.value
        }
        submission.dismiss()
        #expect(cancellations == (fails ? 1 : 0))
        #expect(dismissals == 1)
    }

    @Test
    func `failed signing can retry and completed signing dismisses without cancellation`() async throws {
        var cancellations = 0
        var dismissals = 0
        let submission = WalletConnectPaySubmission(
            onCancel: { cancellations += 1 }, onDismiss: { dismissals += 1 }
        )
        await #expect(throws: TestError.self) {
            try await submission.submit { throw TestError.failed }
        }
        #expect(cancellations == 0)
        let result = try await submission.submit { 42 }
        #expect(result == 42)
        submission.dismiss()
        #expect(cancellations == 0)
        #expect(dismissals == 1)
    }
}

@MainActor
private final class SuspendedOperation {
    private var result: CheckedContinuation<Void, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func run() async throws {
        try await withCheckedThrowingContinuation {
            result = $0
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        guard result == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ value: Result<Void, any Error>) {
        result?.resume(with: value)
        result = nil
    }
}

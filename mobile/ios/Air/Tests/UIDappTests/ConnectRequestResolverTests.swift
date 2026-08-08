import Testing
@testable import UIDapp
import WalletCore

@MainActor
@Suite("Dapp Connect Resolution")
struct ConnectRequestResolverTests {
    @Test
    func `cancellation claimed first prevents confirmation`() async {
        let spy = RequestSpy()
        let resolver = makeResolver(spy: spy)

        #expect(resolver.cancel(reason: "Cancel"))
        await spy.waitForCancellation()
        let outcome = await resolver.confirm(
            accountId: "account",
            proofSignatures: ["signature"]
        )

        guard case .cancelled = outcome else {
            Issue.record("Expected cancellation to own the request")
            return
        }
        #expect(await spy.confirmations == 0)
        #expect(await spy.cancellations == 1)
    }

    @Test
    func `confirmation claimed first prevents cancellation`() async {
        let spy = RequestSpy()
        let blocker = ConfirmationBlocker()
        let resolver = makeResolver(spy: spy, blocker: blocker)

        let confirmation = Task {
            await resolver.confirm(
                accountId: "account",
                proofSignatures: ["signature"]
            )
        }
        await blocker.waitUntilStarted()

        #expect(!resolver.cancel(reason: "Cancel"))
        await blocker.release()
        let outcome = await confirmation.value

        guard case .confirmed = outcome else {
            Issue.record("Expected confirmation to own the request")
            return
        }
        #expect(await spy.confirmations == 1)
        #expect(await spy.cancellations == 0)
    }

    @Test
    func `duplicate confirmation joins the one bridge call`() async {
        let spy = RequestSpy()
        let blocker = ConfirmationBlocker()
        let resolver = makeResolver(spy: spy, blocker: blocker)

        let first = Task {
            await resolver.confirm(accountId: "account", proofSignatures: nil)
        }
        await blocker.waitUntilStarted()
        let second = Task {
            await resolver.confirm(accountId: "account", proofSignatures: nil)
        }
        await blocker.release()

        guard case .confirmed = await first.value,
              case .confirmed = await second.value else {
            Issue.record("Expected both callers to observe the same confirmation")
            return
        }
        #expect(await spy.confirmations == 1)
    }

    @Test
    func `confirmation bridge failure is indeterminate and cannot be cancelled`() async {
        let spy = RequestSpy()
        let resolver = ConnectRequestResolver(
            promiseId: "promise",
            confirmRequest: { _, _ in
                await spy.recordConfirmation()
                throw TestError.failed
            },
            cancelRequest: { _, _ in
                await spy.recordCancellation()
            }
        )

        let outcome = await resolver.confirm(
            accountId: "account",
            proofSignatures: nil
        )
        #expect(!resolver.cancel(reason: "Cancel"))

        guard case .indeterminate = outcome else {
            Issue.record("Expected an indeterminate confirmation outcome")
            return
        }
        #expect(await spy.confirmations == 1)
        #expect(await spy.cancellations == 0)
    }

    private func makeResolver(
        spy: RequestSpy,
        blocker: ConfirmationBlocker? = nil
    ) -> ConnectRequestResolver {
        ConnectRequestResolver(
            promiseId: "promise",
            confirmRequest: { _, _ in
                await spy.recordConfirmation()
                if let blocker {
                    await blocker.block()
                }
            },
            cancelRequest: { _, _ in
                await spy.recordCancellation()
            }
        )
    }
}

private actor RequestSpy {
    private(set) var confirmations = 0
    private(set) var cancellations = 0
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func recordConfirmation() {
        confirmations += 1
    }

    func recordCancellation() {
        cancellations += 1
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForCancellation() async {
        guard cancellations == 0 else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }
}

private actor ConfirmationBlocker {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func block() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum TestError: Error {
    case failed
}

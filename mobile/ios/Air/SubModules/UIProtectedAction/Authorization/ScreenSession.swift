import ProtectedAction
import WalletCore

protocol ScreenValue: Sendable {
    var preventsRetry: Bool { get }
}

extension ActionSubmissionResult: ScreenValue {}

extension SoftwareSubmission: ScreenValue {
    var preventsRetry: Bool {
        switch self {
        case .requiresMfa:
            false
        case .resolved(let result):
            result.preventsRetry
        }
    }
}

@MainActor
enum ScreenResolution<Value: ScreenValue> {
    case value(Value, shouldContinuePresentation: Bool)
    case cancelled(AuthorizationCancellation)
    case failed(any Error)
}

@MainActor
final class ScreenSession<Value: ScreenValue> {
    private var continuation: CheckedContinuation<ScreenResolution<Value>, Never>?
    private var didInstallContinuation = false
    private var isSubmissionInProgress = false
    private var deferredCancellation: CancellationReason?
    private var didResolvePreventingRetry = false
    private let onDeferredCancellationResolved: () -> Void
    private let onSubmissionStarted: () -> Void
    private(set) var stage: CancellationStage

    init(
        stage: CancellationStage,
        onDeferredCancellationResolved: @escaping () -> Void = {},
        onSubmissionStarted: @escaping () -> Void = {}
    ) {
        self.stage = stage
        self.onDeferredCancellationResolved = onDeferredCancellationResolved
        self.onSubmissionStarted = onSubmissionStarted
    }

    var isFinished: Bool {
        didInstallContinuation && continuation == nil
    }

    func install(
        _ continuation: CheckedContinuation<ScreenResolution<Value>, Never>
    ) {
        precondition(!didInstallContinuation, "Protected action continuation installed more than once")
        didInstallContinuation = true
        self.continuation = continuation
        if !isSubmissionInProgress {
            resolveDeferredCancellationIfNeeded()
        }
    }

    func beginSubmission() {
        guard !isFinished else { return }
        isSubmissionInProgress = true
        onSubmissionStarted()
    }

    @discardableResult
    func resolveDeferredCancellationIfRetryAllowed(for value: Value) -> Bool {
        guard !value.preventsRetry else { return false }
        isSubmissionInProgress = false
        return resolveDeferredCancellationIfNeeded()
    }

    @discardableResult
    func resolve(_ value: Value) -> Bool {
        isSubmissionInProgress = false
        let preventsRetry = value.preventsRetry
        if !preventsRetry, resolveDeferredCancellationIfNeeded() {
            return false
        }
        let shouldPresentCompletion = deferredCancellation == nil
        deferredCancellation = nil
        guard let continuation = takeContinuation() else { return false }
        didResolvePreventingRetry = preventsRetry
        continuation.resume(
            returning: .value(
                value,
                shouldContinuePresentation: shouldPresentCompletion
            )
        )
        return true
    }

    @discardableResult
    func fail(_ error: any Error) -> Bool {
        isSubmissionInProgress = false
        guard !resolveDeferredCancellationIfNeeded(), let continuation = takeContinuation() else {
            return false
        }
        continuation.resume(returning: .failed(error))
        return true
    }

    @discardableResult
    func cancel(_ reason: CancellationReason) -> Bool {
        guard !isFinished else { return false }
        if isSubmissionInProgress || !didInstallContinuation {
            deferredCancellation = deferredCancellation ?? reason
            return false
        }
        return resolveCancellation(reason)
    }

    @discardableResult
    func cancel(
        _ reason: CancellationReason,
        onPreventedRetryCancellation: () -> Void
    ) -> Bool {
        if didResolvePreventingRetry {
            onPreventedRetryCancellation()
            return false
        }
        return cancel(reason)
    }

    @discardableResult
    private func resolveDeferredCancellationIfNeeded() -> Bool {
        guard let reason = deferredCancellation, didInstallContinuation else { return false }
        deferredCancellation = nil
        let didResolve = resolveCancellation(reason)
        if didResolve {
            onDeferredCancellationResolved()
        }
        return didResolve
    }

    private func resolveCancellation(_ reason: CancellationReason) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(returning: .cancelled(.init(stage: stage, reason: reason)))
        return true
    }

    private func takeContinuation(
    ) -> CheckedContinuation<ScreenResolution<Value>, Never>? {
        guard didInstallContinuation else { return nil }
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}

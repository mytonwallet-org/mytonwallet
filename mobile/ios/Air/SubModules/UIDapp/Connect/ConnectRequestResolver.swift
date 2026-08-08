import Foundation
import WalletContext
import WalletCore

private let connectRequestResolverLog = Log("ConnectRequestResolver")

@MainActor
final class ConnectRequestResolver {
    typealias ConfirmRequest = @Sendable (
        _ promiseId: String,
        _ data: ApiDappRequestConfirmation
    ) async throws -> Void
    typealias CancelRequest = @Sendable (
        _ promiseId: String,
        _ reason: String?
    ) async throws -> Void

    enum ConfirmationOutcome {
        case confirmed
        case cancelled
        case indeterminate(any Error)
    }

    private enum State {
        case pending
        case confirming([CheckedContinuation<ConfirmationOutcome, Never>])
        case confirmed
        case confirmationFailed(any Error)
        case cancelling
        case cancelled
        case cancellationFailed
    }

    private let promiseId: String
    private let confirmRequest: ConfirmRequest
    private let cancelRequest: CancelRequest
    private var state: State = .pending

    init(
        promiseId: String,
        confirmRequest: @escaping ConfirmRequest = { promiseId, data in
            try await Api.confirmDappRequestConnect(promiseId: promiseId, data: data)
        },
        cancelRequest: @escaping CancelRequest = { promiseId, reason in
            try await Api.cancelDappRequest(promiseId: promiseId, reason: reason)
        }
    ) {
        self.promiseId = promiseId
        self.confirmRequest = confirmRequest
        self.cancelRequest = cancelRequest
    }

    func confirm(
        accountId: String,
        proofSignatures: [String]?
    ) async -> ConfirmationOutcome {
        switch state {
        case .pending:
            state = .confirming([])
        case .confirmed:
            return .confirmed
        case .cancelling, .cancelled, .cancellationFailed:
            return .cancelled
        case .confirming(var waiters):
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
                state = .confirming(waiters)
            }
        case .confirmationFailed(let error):
            return .indeterminate(error)
        }

        let outcome: ConfirmationOutcome
        do {
            try await confirmRequest(
                promiseId,
                ApiDappRequestConfirmation(
                    accountId: accountId,
                    proofSignatures: proofSignatures
                )
            )
            outcome = .confirmed
        } catch {
            let error = ConnectConfirmationIndeterminateError(underlying: error)
            outcome = .indeterminate(error)
        }
        finishConfirmation(with: outcome)
        return outcome
    }

    @discardableResult
    func cancel(reason: String?) -> Bool {
        guard case .pending = state else { return false }
        state = .cancelling

        let promiseId = self.promiseId
        let cancelRequest = self.cancelRequest
        Task { [weak self] in
            do {
                try await cancelRequest(promiseId, reason)
                self?.finishCancellation(error: nil)
            } catch {
                self?.finishCancellation(error: error)
                connectRequestResolverLog.error(
                    "Failed to reject dapp Connect request: \(error, .public)"
                )
            }
        }
        return true
    }

    private func finishCancellation(error: (any Error)?) {
        guard case .cancelling = state else { return }
        state = error == nil ? .cancelled : .cancellationFailed
    }

    private func finishConfirmation(with outcome: ConfirmationOutcome) {
        guard case .confirming(let waiters) = state else { return }
        switch outcome {
        case .confirmed:
            state = .confirmed
        case .cancelled:
            assertionFailure("Confirmation cannot become cancelled after it is claimed")
            state = .cancelled
        case .indeterminate(let error):
            state = .confirmationFailed(error)
        }
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
    }
}

private struct ConnectConfirmationIndeterminateError: Error, LocalizedError {
    let underlying: any Error

    var errorDescription: String? {
        underlying.localizedDescription
    }
}

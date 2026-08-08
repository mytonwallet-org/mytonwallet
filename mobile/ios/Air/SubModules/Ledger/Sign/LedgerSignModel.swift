import Foundation
import OrderedCollections
import ProtectedAction
import WalletContext
import WalletCore

private let ledgerSignStartSteps: OrderedDictionary<StepId, StepStatus> = [
    .connect: .current,
    .openApp: .none,
    .sign: .none,
]

private let ledgerSignLog = Log("LedgerSignModel")

@MainActor
public enum LedgerSignSubmissionState<Payload: Sendable> {
    case idle
    case submitting
    case retryableFailure(any Error)
    case partiallyCommitted(
        receipt: ActionSubmissionReceipt<Payload>,
        remainingWork: ActionRemainingWork
    )
    case resolved(ActionSubmissionResult<Payload>)
}

@MainActor
public final class LedgerSignModel<Payload: Sendable>: Sendable {
    public var onCancel: (@MainActor () -> Void)?
    public var onSubmissionStateChange: (@MainActor (LedgerSignSubmissionState<Payload>) -> Void)?

    public private(set) var submissionState: LedgerSignSubmissionState<Payload> = .idle {
        didSet {
            onSubmissionStateChange?(submissionState)
        }
    }

    private let operation: HardwareOperation<Payload>
    private var submissionAccumulator = ActionSubmissionStateAccumulator<Payload>()
    private lazy var flow = LedgerFlowController(
        steps: ledgerSignStartSteps,
        allowsCancellation: { [weak self] in self?.allowsCancellation ?? false },
        onCancel: { [weak self] in self?.onCancel?() },
        performSteps: { [weak self] in
            guard let self else { return }
            try await self.performSteps()
        }
    )

    var allowsCancellation: Bool {
        switch submissionState {
        case .idle, .retryableFailure, .partiallyCommitted:
            true
        case .submitting, .resolved:
            false
        }
    }

    public var safetyResult: ActionSubmissionResult<Payload>? {
        switch submissionState {
        case .partiallyCommitted(let receipt, let remainingWork):
            .partiallyCommitted(receipt: receipt, remainingWork: remainingWork)
        case .resolved(let result) where result.preventsRetry:
            result
        case .idle, .submitting, .retryableFailure, .resolved:
            nil
        }
    }

    public var isSubmitting: Bool {
        if case .submitting = submissionState {
            true
        } else {
            false
        }
    }

    public var viewModel: LedgerViewModel { flow.viewModel }

    public init(operation: HardwareOperation<Payload>) {
        self.operation = operation
    }

    public func start() {
        flow.start()
    }

    func cancel() {
        flow.cancel()
    }

    private func performSteps() async throws {
        try await flow.connect()
        try await flow.openApp()
        await signAndSubmit()
    }

    private func signAndSubmit() async {
        flow.updateStep(.sign, status: .current)
        viewModel.exitButtonTitle = lang("Cancel")
        submissionState = .submitting
        let context = HardwareOperationContext { [weak self] completed, total in
            guard let self else { return }
            let current = min(completed + 1, total)
            Task { @MainActor in
                self.flow.updateStepSubtitle(
                    .sign,
                    subtitle: lang("$ledger_confirm_progress", arg1: current, arg2: total)
                )
            }
        }
        let result = submissionAccumulator.record(
            await operation.perform(context: context)
        )
        if case .indeterminate(let error, _) = result,
           error is ActionSubmissionAccumulationError {
            ledgerSignLog.fault("Ledger partial commit progress moved backwards")
        }
        flow.updateStepSubtitle(.sign, subtitle: nil)

        switch result {
        case .notCommitted(let error):
            viewModel.exitButtonTitle = lang("Cancel")
            submissionState = .retryableFailure(error)
            flow.updateStep(.sign, status: .error(errorDescription(error)))

        case .partiallyCommitted(let receipt, let remainingWork):
            viewModel.exitButtonTitle = lang("Close")
            submissionState = .partiallyCommitted(receipt: receipt, remainingWork: remainingWork)
            flow.updateStep(.sign, status: .error(errorDescription(remainingWork.error)))

        case .committed:
            flow.updateStep(.sign, status: .done)
            try? await Task.sleep(for: .seconds(0.8))
            submissionState = .resolved(result)

        case .indeterminate(let error, _):
            flow.updateStep(.sign, status: .error(errorDescription(error)))
            submissionState = .resolved(result)
        }
    }

    private func errorDescription(_ error: any Error) -> String? {
        (error as? LocalizedError)?.errorDescription
    }

}

import CoreBluetooth
import Foundation
import OrderedCollections
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let log = Log("LedgerFlowController")

@MainActor
final class LedgerFlowController {
    private let startSteps: OrderedDictionary<StepId, StepStatus>
    private let allowsCancellation: @MainActor () -> Bool
    private let onCancel: @MainActor () -> Void
    private let performSteps: @MainActor () async throws -> Void

    private var steps: OrderedDictionary<StepId, StepStatus>
    private var stepSubtitles: [StepId: String] = [:]
    private let connection = LedgerConnectionManager.shared
    private var task: Task<Void, Never>?
    private var appInfo: LedgerAppInfo?

    private(set) var connectedIdentifier: LedgerIdentifier?
    let viewModel = LedgerViewModel()

    init(
        steps: OrderedDictionary<StepId, StepStatus>,
        allowsCancellation: @escaping @MainActor () -> Bool,
        onCancel: @escaping @MainActor () -> Void,
        performSteps: @escaping @MainActor () async throws -> Void
    ) {
        self.startSteps = steps
        self.steps = steps
        self.allowsCancellation = allowsCancellation
        self.onCancel = onCancel
        self.performSteps = performSteps

        viewModel.stop = { [weak self] in self?.handleStop() }
        viewModel.restart = { [weak self] in self?.handleRestart() }
        viewModel.retryCurrentStep = { [weak self] in self?.handleRetryCurrentStep() }
        updateViewModelSteps()
    }

    deinit {
        log.info("deinit")
        task?.cancel()
    }

    func start() {
        guard task?.isCancelled == true || task == nil else { return }
        let performSteps = self.performSteps
        task = Task {
            do {
                try await performSteps()
            } catch {
                log.error("\(error)")
            }
        }
    }

    func connect() async throws {
        updateStep(.connect, status: .current)
        do {
            try await withRetries(4) {
                if connection.bleTransport.isConnected {
                    try await connection.disconnect()
                }
                let identifier = try await connection.scanAndConnectToFirst(timeout: 3)
                try Task.checkCancellation()
                connectedIdentifier = identifier
                updateStep(.connect, status: .done)
            } handleError: { @MainActor error in
                if CBManager.authorization == .denied {
                    topViewController()?.showAlert(
                        title: lang("Bluetooth Access Denied"),
                        text: lang("Bluetooth access is needed to connect Ledger."),
                        button: lang("Open Settings"),
                        buttonPressed: {
                            DispatchQueue.main.async {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        },
                        secondaryButton: lang("Cancel"),
                        preferPrimary: true
                    )
                    throw error
                }
            }
        } catch {
            log.error("\(error)")
            let errorString = (error as? LocalizedError)?.errorDescription
            updateStep(.connect, status: .error(errorString))
            throw error
        }
    }

    func openApp() async throws {
        let id = try connectedIdentifier.orThrow("logic error")
        updateStep(.openApp, status: .current)
        do {
            try await withRetries(4) {
                appInfo = try await connection.connectToTonApp(peripheralID: id)
                try Task.checkCancellation()
                updateStep(.openApp, status: .done)
            }
        } catch {
            log.error("\(error)")
            let errorString = (error as? LocalizedError)?.errorDescription
            updateStep(.openApp, status: .error(errorString))
            throw error
        }
    }

    func cancel() {
        task?.cancel()
    }

    func updateStep(_ stepId: StepId, status: StepStatus) {
        steps[stepId] = status
        updateViewModelSteps()
        if case .error = status {
            viewModel.backEnabled = allowsCancellation()
            viewModel.retryEnabled = true
            viewModel.showRetry = true
        }
    }

    func updateStepSubtitle(_ stepId: StepId, subtitle: String?) {
        stepSubtitles[stepId] = subtitle
        updateViewModelSteps()
    }

    private func handleStop() {
        guard allowsCancellation() else { return }
        cancel()
        let onCancel = self.onCancel
        Task { @MainActor in onCancel() }
    }

    private func handleRestart() {
        task?.cancel()
        steps = startSteps
        stepSubtitles.removeAll()
        viewModel.backEnabled = allowsCancellation()
        viewModel.retryEnabled = false
        updateViewModelSteps()
        start()
    }

    private func handleRetryCurrentStep() {
        handleRestart()
    }

    private func updateViewModelSteps() {
        viewModel.steps = steps.compactMap { stepId, status in
            guard status != .hidden else { return nil }
            return LedgerViewModel.Step(
                id: stepId,
                status: status,
                subtitle: stepSubtitles[stepId]
            )
        }
    }
}


import Foundation
import WalletContext
import WalletCore
import OrderedCollections
import UIKit
import CoreBluetooth
import UIComponents

private let log = Log("LedgerBaseModel")

public class LedgerBaseModel: @unchecked Sendable {
    
    var steps: OrderedDictionary<StepId, StepStatus>
    let startSteps: OrderedDictionary<StepId, StepStatus>
    
    @MainActor public let viewModel = LedgerViewModel()
    public var onDone: (@MainActor () -> ())?
    public var onCancel: (@MainActor () -> ())?
    
    var connection = LedgerConnectionManager.shared
    var task: Task<Void, Never>?
    
    var connectedIdentifier: LedgerIdentifier?
    var appInfo: LedgerAppInfo?
    
    public init(steps: OrderedDictionary<StepId, StepStatus>) async {
        self.startSteps = steps
        self.steps = steps
        await MainActor.run {
            self.viewModel.stop = { [weak self] in self?.handleStop() }
            self.viewModel.restart = { [weak self] in self?.handleRestart() }
            self.viewModel.retryCurrentStep = { [weak self] in self?.handleRetryCurrentStep() }
        }
        await self.updateViewModelSteps()
    }
    
    deinit {
        log.info("deinit")
        task?.cancel()
    }
    
    public func start() {
        guard self.task?.isCancelled == true || self.task == nil else { return }
        self.task = Task {
            do {
                try await performSteps()
            } catch {
                log.error("\(error)")
            }
        }
    }
    
    func performSteps() async throws {
        fatalError("abstract")
    }
    
    func connect() async throws {
        await updateStep(.connect, status: .current)
        do {
            try await withRetries(4) {
                if connection.bleTransport.isConnected {
                    try await connection.bleTransport.disconnect()
                }
                let identifier: LedgerIdentifier
                // connect to recorded deviceId instead? 
//                if let _id = ledger.deviceId, let id = UUID(uuidString: _id) {
//                    identifier = try await connection.connect(toPeripheralID: LedgerIdentifier(uuid: id, name: nil))
//                } else {
                identifier = try await connection.scanAndConnectToFirst(timeout: 3)
//                }
                try Task.checkCancellation()
                self.connectedIdentifier = identifier
                await updateStep(.connect, status: .done)
            } handleError: { @MainActor error in
                if CBManager.authorization == .denied {
                    topViewController()?.showAlert(title: lang("Bluetooth Access Denied"), text: lang("Bluetooth access is needed to connect Ledger."), button: lang("Open Settings"), buttonPressed: {
                        DispatchQueue.main.async {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }, secondaryButton: lang("Cancel"), preferPrimary: true)
                    throw error
                }
            }
        } catch {
            log.error("\(error)")
            let errorString = (error as? LocalizedError)?.errorDescription
            await updateStep(.connect, status: .error(errorString))
            throw error
        }
    }
    
    func openApp() async throws {
        let id = try self.connectedIdentifier.orThrow("logic error")
        await updateStep(.openApp, status: .current)
        do {
            try await withRetries(4) {
                self.appInfo = try await connection.connectToTonApp(peripheralID: id)
                try Task.checkCancellation()
                await updateStep(.openApp, status: .done)
            }
        } catch {
            log.error("\(error)")
            let errorString = (error as? LocalizedError)?.errorDescription
            await updateStep(.openApp, status: .error(errorString))
            throw error
        }
    }
    
    // MARK: - View model
    
    func handleStop() {
        task?.cancel()
        Task { @MainActor in onCancel?() }
    }
    
    func handleRestart() {
        task?.cancel()
        steps = startSteps
        Task { @MainActor in
            viewModel.backEnabled = true
            viewModel.retryEnabled = false
            await self.updateViewModelSteps()
        }
        start()
    }
    
    func handleRetryCurrentStep() {
        handleRestart()
    }
    
    func updateStep(_ stepId: StepId, status: StepStatus) async {
        self.steps[stepId] = status
        await updateViewModelSteps()
        if case .error = status {
            await MainActor.run {
                viewModel.backEnabled = true
                viewModel.retryEnabled = true
                viewModel.showRetry = true
            }
        }
    }
    
    func updateViewModelSteps() async {
        var vmSteps: [LedgerViewModel.Step] = []
        for (stepId, status) in steps where status != .hidden {
            vmSteps.append(
                LedgerViewModel.Step(
                    id: stepId,
                    status: status
                )
            )
        }
        let _vmSteps = vmSteps
        await MainActor.run { viewModel.steps = _vmSteps }
    }
}

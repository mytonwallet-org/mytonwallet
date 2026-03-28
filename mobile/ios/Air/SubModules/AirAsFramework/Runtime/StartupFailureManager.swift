import Foundation
import WalletContext

@MainActor
enum StartupFailureManager {
    static func handle(_ error: any Error, phase: StartupFailurePhase, retry: @escaping () -> Void) async {
        let failure = StartupFailureClassifier.classify(error, phase: phase)
        StartupTrace.mark("startup.failure", details: "phase=\(phase.rawValue) kind=\(failure.kind.rawValue)")
        await StartupFailureReporter.report(error, failure: failure)
        StartupFailurePresenter.present(failure, retry: retry)
    }
}

@MainActor
private enum StartupFailurePresenter {
    static func present(_ failure: StartupFailure, retry: @escaping () -> Void) {
        RootStateCoordinator.shared.showStartupFailure(failure, onRetry: retry)
    }
}

private enum StartupFailureReporter {
    private static let log = Log("StartupFailure")

    static func report(_ error: any Error, failure: StartupFailure) async {
        let report = StartupFailureDiagnostics.diagnosticsReport(error, failure: failure)
        await log.critical("\(report, .public)")
    }
}

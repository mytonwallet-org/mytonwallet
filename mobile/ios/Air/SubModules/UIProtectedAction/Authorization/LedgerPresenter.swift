import Ledger
import ProtectedAction
import SwiftUI
import UIKit
import UIComponents
import WalletCore

@MainActor
enum LedgerPresenter {
    static func authorize<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        makeOperation: () async throws -> HardwareOperation<Result>,
        confirmation: Confirmation<HeaderView>,
        on presenter: UIViewController,
        completionBehavior: CompletionBehavior,
        authorizationUI: AuthorizationUI,
        isPresentationValid: @escaping @MainActor () -> Bool
    ) async -> ScreenResolution<ActionSubmissionResult<Result>> {
        if case .push = confirmation.presentationStyle,
           presenter.navigationController == nil {
            return .failed(
                InvariantError.missingPresenter("Ledger navigation controller")
            )
        }
        let operation: HardwareOperation<Result>
        do {
            operation = try await makeOperation()
        } catch {
            return .failed(error)
        }
        guard isPresentationValid() else {
            return .cancelled(.init(stage: .ledger, reason: .dismissed))
        }
        let model = LedgerSignModel(operation: operation)
        let session = ScreenSession<ActionSubmissionResult<Result>>(
            stage: .ledger,
            onDeferredCancellationResolved: { authorizationUI.dismiss() },
            onSubmissionStarted: { authorizationUI.beginSubmission() }
        )
        let ledgerController = Reference<LedgerSignVC<HeaderView, Result>>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.install(continuation)
                if Task.isCancelled {
                    session.cancel(.taskCancelled)
                    return
                }
                let ledgerVC = LedgerSignVC(
                    model: model,
                    title: confirmation.title,
                    headerView: confirmation.headerView,
                    compactHeaderView: AnyView(confirmation.headerView.compactRepresentation)
                )
                ledgerController.value = ledgerVC
                ledgerVC.onEvent = { completedVC, event in
                    switch event {
                    case .submissionStarted:
                        session.beginSubmission()

                    case .retryableFailure(let error):
                        _ = session.resolveDeferredCancellationIfRetryAllowed(
                            for: .notCommitted(error)
                        )

                    case .cancellationRequested(let reason):
                        session.cancel(cancellationReason(reason))

                    case .cancelled(let reason):
                        authorizationUI.clear()
                        session.cancel(cancellationReason(reason)) {
                            authorizationUI.requestCompletionCancellation()
                        }
                        ledgerController.value = nil

                    case .resolved(let submission):
                        Task {
                            if shouldRemoveScreen(
                                after: submission,
                                completionBehavior: completionBehavior
                            ) {
                                await remove(
                                    completedVC,
                                    presentationStyle: confirmation.presentationStyle
                                )
                                authorizationUI.clear()
                            }
                            session.resolve(submission)
                            ledgerController.value = nil
                        }
                    }
                }
                guard present(
                    ledgerVC,
                    presentationStyle: confirmation.presentationStyle,
                    on: presenter,
                    authorizationUI: authorizationUI
                ) else {
                    session.fail(InvariantError.missingPresenter("Ledger transition"))
                    return
                }
                authorizationUI.setAlertHost(ledgerVC.navigationController ?? ledgerVC)
            }
        } onCancel: {
            Task { @MainActor in
                if let ledgerController = ledgerController.value {
                    ledgerController.requestCancellation(reason: .taskCancelled)
                } else if session.cancel(.taskCancelled) {
                    authorizationUI.dismiss()
                }
            }
        }
    }

    private static func cancellationReason(
        _ reason: LedgerSignCancellationReason
    ) -> CancellationReason {
        switch reason {
        case .dismissed:
            .dismissed
        case .cancelButton:
            .cancelButton
        case .closeButton:
            .closeButton
        case .taskCancelled:
            .taskCancelled
        }
    }

    private static func present<HeaderView: View, Result: MfaProtectedActionResult>(
        _ ledgerVC: LedgerSignVC<HeaderView, Result>,
        presentationStyle: PresentationStyle,
        on presenter: UIViewController,
        authorizationUI: AuthorizationUI
    ) -> Bool {
        switch presentationStyle {
        case .push:
            guard let navigationController = presenter.navigationController else { return false }
            navigationController.pushViewController(ledgerVC, animated: true)
            guard navigationController.topViewController === ledgerVC else { return false }
            authorizationUI.setDismissHandler { [weak navigationController, weak ledgerVC] in
                guard let navigationController, let ledgerVC else { return }
                Task {
                    await AuthorizationSupport.remove(
                        ledgerVC,
                        from: navigationController,
                        animated: false
                    )
                }
            }
        case .sheet:
            let navigationController = WNavigationController(rootViewController: ledgerVC)
            guard AuthorizationSupport.presentSheet(navigationController, on: presenter) else {
                return false
            }
            authorizationUI.setDismissHandler { [weak navigationController] in
                navigationController?.dismiss(animated: true)
            }
        }
        return true
    }

    private static func remove<HeaderView: View, Result: MfaProtectedActionResult>(
        _ ledgerVC: LedgerSignVC<HeaderView, Result>,
        presentationStyle: PresentationStyle
    ) async {
        guard let navigationController = ledgerVC.navigationController else {
            ledgerVC.dismiss(animated: true)
            return
        }
        switch presentationStyle {
        case .push:
            await AuthorizationSupport.remove(
                ledgerVC,
                from: navigationController,
                animated: true
            )
        case .sheet:
            await AuthorizationSupport.dismiss(navigationController)
        }
    }

    private static func shouldRemoveScreen<Result>(
        after result: ActionSubmissionResult<Result>,
        completionBehavior: CompletionBehavior
    ) -> Bool {
        switch result {
        case .committed:
            completionBehavior == .popAuthorization
        case .notCommitted, .partiallyCommitted, .indeterminate:
            false
        }
    }
}

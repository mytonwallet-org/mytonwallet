import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import WalletCore

@MainActor
enum MfaPresenter {
    static func authorize<Result: MfaProtectedActionResult>(
        account: MAccount,
        requestHash: String,
        title: String,
        compactRepresentation: AnyView,
        prefersNavigationTitleWithCustomHeader: Bool,
        result: Result,
        software: SoftwareOperation<Result>,
        presentationStyle: PresentationStyle,
        on presenter: UIViewController,
        completionBehavior: CompletionBehavior,
        authorizationUI: AuthorizationUI
    ) async -> ScreenResolution<ActionSubmissionResult<Result>> {
        if case .push = presentationStyle,
           presenter.navigationController == nil {
            return .failed(
                InvariantError.missingPresenter("MFA navigation controller")
            )
        }
        let session = ScreenSession<ActionSubmissionResult<Result>>(
            stage: .mfa,
            onDeferredCancellationResolved: { authorizationUI.dismiss() },
            onSubmissionStarted: { authorizationUI.beginSubmission() }
        )
        let mfaController = WeakReference<MfaConfirmationVC>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.install(continuation)
                if Task.isCancelled {
                    if session.cancel(.taskCancelled) {
                        authorizationUI.dismiss()
                    }
                    return
                }
                let model = MfaConfirmationModel(requestHash: requestHash)
                let mfaVC = MfaConfirmationVC(
                    account: account,
                    model: model,
                    title: title,
                    compactRepresentation: compactRepresentation,
                    prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader
                )
                mfaController.value = mfaVC
                var isResolving = false
                mfaVC.onEvent = { [weak mfaVC] event in
                    guard !isResolving else { return }
                    switch event {
                    case .confirmed(let request):
                        session.beginSubmission()
                        Task {
                            let submission = await software.confirmMfa(
                                result: result,
                                accountId: account.id,
                                request: request
                            )
                            guard !session.resolveDeferredCancellationIfRetryAllowed(for: submission) else {
                                return
                            }
                            isResolving = true
                            if shouldRemoveScreen(
                                after: submission,
                                completionBehavior: completionBehavior
                            ), let mfaVC {
                                await remove(mfaVC, presentationStyle: presentationStyle)
                                authorizationUI.clear()
                            }
                            session.resolve(submission)
                        }

                    case .failed(let error):
                        session.beginSubmission()
                        isResolving = true
                        Task {
                            let submission: ActionSubmissionResult<Result> = actionSubmissionFailure(
                                for: error
                            )
                            guard !session.resolveDeferredCancellationIfRetryAllowed(
                                for: submission
                            ) else {
                                return
                            }
                            session.resolve(submission)
                        }

                    case .cancelled(let reason):
                        authorizationUI.clear()
                        session.cancel(cancellationReason(reason)) {
                            authorizationUI.requestCompletionCancellation()
                        }
                    }
                }
                guard present(
                    mfaVC,
                    presentationStyle: presentationStyle,
                    on: presenter,
                    authorizationUI: authorizationUI
                ) else {
                    session.fail(InvariantError.missingPresenter("MFA transition"))
                    return
                }
                authorizationUI.setAlertHost(mfaVC.navigationController ?? mfaVC)
            }
        } onCancel: {
            Task { @MainActor in
                if session.cancel(.taskCancelled) {
                    authorizationUI.dismiss()
                } else {
                    mfaController.value?.dismiss(animated: true)
                }
            }
        }
    }

    private static func cancellationReason(
        _ reason: MfaConfirmationCancellationReason
    ) -> CancellationReason {
        switch reason {
        case .dismissed:
            .dismissed
        case .cancelButton:
            .cancelButton
        case .closeButton:
            .closeButton
        }
    }

    private static func present(
        _ mfaVC: MfaConfirmationVC,
        presentationStyle: PresentationStyle,
        on presenter: UIViewController,
        authorizationUI: AuthorizationUI
    ) -> Bool {
        switch authorizationUI.transitionToNextScreen(mfaVC) {
        case .succeeded:
            return true
        case .failed:
            return false
        case .unavailable:
            break
        }
        switch presentationStyle {
        case .push:
            guard let navigationController = presenter.navigationController else {
                return false
            }
            navigationController.pushViewController(mfaVC, animated: true)
            authorizationUI.setDismissHandler { [weak navigationController, weak mfaVC] in
                guard let navigationController, let mfaVC else { return }
                Task {
                    await AuthorizationSupport.remove(
                        mfaVC,
                        from: navigationController,
                        animated: false
                    )
                }
            }
        case .sheet:
            let navigationController = WNavigationController(rootViewController: mfaVC)
            guard AuthorizationSupport.presentSheet(navigationController, on: presenter) else {
                return false
            }
            authorizationUI.setDismissHandler { [weak navigationController] in
                navigationController?.dismiss(animated: true)
            }
        }
        return true
    }

    private static func remove(
        _ mfaVC: MfaConfirmationVC,
        presentationStyle: PresentationStyle
    ) async {
        guard let navigationController = mfaVC.navigationController else {
            mfaVC.dismiss(animated: true)
            return
        }
        switch presentationStyle {
        case .push:
            await AuthorizationSupport.remove(
                mfaVC,
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

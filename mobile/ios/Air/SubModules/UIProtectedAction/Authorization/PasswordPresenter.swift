import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import UIPasscode
import WalletContext
import WalletCore

@MainActor
enum PasswordPresenter {
    static func authorize<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        account: MAccount,
        software: SoftwareOperation<Result>,
        confirmation: Confirmation<HeaderView>,
        on viewController: UIViewController,
        completionBehavior: CompletionBehavior,
        authorizationUI: AuthorizationUI,
        isPresentationValid: @escaping @MainActor () -> Bool
    ) async -> ScreenResolution<SoftwareSubmission<Result>> {
        guard isPresentationValid() else {
            return .cancelled(.init(stage: .authentication, reason: .dismissed))
        }

        if confirmation.biometricPolicy == .beforePresentation,
           let enclaveToken = await biometricTokenIfAvailable() {
            guard isPresentationValid() else {
                return .cancelled(.init(stage: .authentication, reason: .dismissed))
            }
            authorizationUI.beginSubmission()
            let value = await AuthorizationSupport.performSoftwareSubmission(
                account: account,
                software: software,
                enclaveToken: enclaveToken
            )
            if Task.isCancelled, !value.preventsRetry {
                return .cancelled(.init(stage: .authentication, reason: .taskCancelled))
            }
            return .value(
                value,
                shouldContinuePresentation: !Task.isCancelled
            )
        }

        guard isPresentationValid() else {
            return .cancelled(.init(stage: .authentication, reason: .dismissed))
        }

        switch confirmation.presentationStyle {
        case .push:
            return await pushPasswordScreen(
                account: account,
                software: software,
                confirmation: confirmation,
                on: viewController,
                completionBehavior: completionBehavior,
                authorizationUI: authorizationUI
            )
        case .sheet:
            return await presentPasswordScreen(
                account: account,
                software: software,
                confirmation: confirmation,
                on: viewController,
                completionBehavior: completionBehavior,
                authorizationUI: authorizationUI
            )
        }
    }

    private static func presentPasswordScreen<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        account: MAccount,
        software: SoftwareOperation<Result>,
        confirmation: Confirmation<HeaderView>,
        on presenter: UIViewController,
        completionBehavior: CompletionBehavior,
        authorizationUI: AuthorizationUI
    ) async -> ScreenResolution<SoftwareSubmission<Result>> {
        let session = ScreenSession<SoftwareSubmission<Result>>(
            stage: .authentication,
            onDeferredCancellationResolved: { authorizationUI.dismiss() },
            onSubmissionStarted: { authorizationUI.beginSubmission() }
        )
        weak var navigationController: UINavigationController?
        return await awaitSession(session, authorizationUI: authorizationUI) {
            var value: SoftwareSubmission<Result>?
            var isResolving = false
            let headerController = UIHostingController(rootView: confirmation.headerView)
            headerController.view.backgroundColor = .clear
            let compactHeaderController = UIHostingController(
                rootView: CompactConfirmationHeader(content: confirmation.headerView)
            )
            compactHeaderController.view.backgroundColor = .clear
            let unlockVC = UnlockVC(
                title: confirmation.title,
                replacedTitle: nil,
                subtitle: nil,
                customHeaderVC: headerController,
                compactHeaderVC: compactHeaderController,
                prefersNavigationTitleWithCustomHeader: confirmation.prefersNavigationTitleWithCustomHeader,
                animatedPresentation: false,
                dissmissWhenAuthorized: false,
                shouldBeThemedLikeHeader: false,
                onAuthTask: { enclaveToken, onTaskDone in
                    session.beginSubmission()
                    Task {
                        value = await AuthorizationSupport.performSoftwareSubmission(
                            account: account,
                            software: software,
                            enclaveToken: enclaveToken
                        )
                        onTaskDone()
                    }
                },
                onDone: { _ in
                    guard let value, !isResolving else { return }
                    isResolving = true
                    Task {
                        guard !session.resolveDeferredCancellationIfRetryAllowed(for: value) else { return }
                        let removeScreen = shouldRemovePasswordScreen(
                            after: value,
                            completionBehavior: completionBehavior
                        )
                        if removeScreen, let navigationController {
                            await AuthorizationSupport.dismiss(navigationController)
                            authorizationUI.clear()
                        }
                        session.resolve(value)
                    }
                },
                cancellable: true,
                onCancel: {
                    guard !isResolving else { return }
                    session.cancel(.dismissed) {
                        authorizationUI.requestCompletionCancellation()
                    }
                },
                useBioOnPresent: confirmation.biometricPolicy == .onAuthorizationScreen,
                biometricPassAllowed: confirmation.biometricPolicy != .disabled,
                authSessionKind: .reusable
            )
            let navigation = WNavigationController(rootViewController: unlockVC)
            navigation.navigationBar.tintColor = AirTintColor
            guard AuthorizationSupport.presentSheet(navigation, on: presenter) else {
                session.fail(InvariantError.missingPresenter("password sheet"))
                return
            }
            navigationController = navigation
            authorizationUI.setAlertHost(navigation)
            authorizationUI.setDismissHandler { [weak navigation] in
                navigation?.dismiss(animated: true)
            }
            authorizationUI.setNextScreenTransition { [weak navigation, weak unlockVC] nextScreen in
                guard let navigation, let unlockVC,
                      AuthorizationSupport.push(
                        nextScreen,
                        replacing: unlockVC,
                        in: navigation
                      )
                else {
                    return nil
                }
                return { [weak navigation] in
                    navigation?.dismiss(animated: true)
                }
            }
        }
    }

    private static func pushPasswordScreen<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        account: MAccount,
        software: SoftwareOperation<Result>,
        confirmation: Confirmation<HeaderView>,
        on presenter: UIViewController,
        completionBehavior: CompletionBehavior,
        authorizationUI: AuthorizationUI
    ) async -> ScreenResolution<SoftwareSubmission<Result>> {
        guard let navigationController = presenter.navigationController else {
            return .failed(InvariantError.missingPresenter("password navigation controller"))
        }
        let session = ScreenSession<SoftwareSubmission<Result>>(
            stage: .authentication,
            onDeferredCancellationResolved: { authorizationUI.dismiss() },
            onSubmissionStarted: { authorizationUI.beginSubmission() }
        )
        weak var unlockController: UnlockVC?
        return await awaitSession(session, authorizationUI: authorizationUI) {
            var value: SoftwareSubmission<Result>?
            var isResolving = false
            let headerController = UIHostingController(rootView: confirmation.headerView)
            headerController.view.backgroundColor = .clear
            let compactHeaderController = UIHostingController(
                rootView: CompactConfirmationHeader(content: confirmation.headerView)
            )
            compactHeaderController.view.backgroundColor = .clear
            unlockController = UnlockVC.pushAuth(
                on: presenter,
                title: confirmation.title,
                customHeaderVC: headerController,
                compactHeaderVC: compactHeaderController,
                sessionKind: .reusable,
                useBioOnPresent: confirmation.biometricPolicy == .onAuthorizationScreen,
                biometricPassAllowed: confirmation.biometricPolicy != .disabled,
                prefersNavigationTitleWithCustomHeader: confirmation.prefersNavigationTitleWithCustomHeader,
                onAuthTask: { enclaveToken, onTaskDone in
                    session.beginSubmission()
                    Task {
                        value = await AuthorizationSupport.performSoftwareSubmission(
                            account: account,
                            software: software,
                            enclaveToken: enclaveToken
                        )
                        onTaskDone()
                    }
                },
                onDone: { _ in
                    guard let value, !isResolving else { return }
                    isResolving = true
                    Task {
                        guard !session.resolveDeferredCancellationIfRetryAllowed(for: value) else { return }
                        let removeScreen = shouldRemovePasswordScreen(
                            after: value,
                            completionBehavior: completionBehavior
                        )
                        if removeScreen, let unlockController {
                            await AuthorizationSupport.remove(
                                unlockController,
                                from: navigationController,
                                animated: true
                            )
                            authorizationUI.clear()
                        }
                        session.resolve(value)
                    }
                },
                onCancel: {
                    guard !isResolving else { return }
                    session.cancel(.dismissed) {
                        authorizationUI.requestCompletionCancellation()
                    }
                }
            )
            guard let unlockController else {
                session.fail(InvariantError.missingPresenter("password screen"))
                return
            }
            authorizationUI.setAlertHost(navigationController)
            authorizationUI.setDismissHandler { [weak navigationController, weak unlockController] in
                guard let navigationController, let unlockController else { return }
                Task {
                    await AuthorizationSupport.remove(
                        unlockController,
                        from: navigationController,
                        animated: false
                    )
                }
            }
            authorizationUI.setNextScreenTransition {
                [weak navigationController, weak unlockController] nextScreen in
                guard let navigationController, let unlockController,
                      AuthorizationSupport.push(
                        nextScreen,
                        replacing: unlockController,
                        in: navigationController
                      )
                else {
                    return nil
                }
                return { [weak navigationController, weak unlockController, weak nextScreen] in
                    guard let navigationController else { return }
                    AuthorizationSupport.removeAuthorizationSequence(
                        [unlockController, nextScreen].compactMap { $0 },
                        from: navigationController
                    )
                }
            }
        }
    }

    private static func shouldRemovePasswordScreen<Result>(
        after value: SoftwareSubmission<Result>,
        completionBehavior: CompletionBehavior
    ) -> Bool {
        switch value {
        case .requiresMfa:
            false
        case .resolved(.committed):
            completionBehavior == .popAuthorization
        case .resolved(.notCommitted), .resolved(.partiallyCommitted), .resolved(.indeterminate):
            false
        }
    }

    private static func awaitSession<Value: ScreenValue>(
        _ session: ScreenSession<Value>,
        authorizationUI: AuthorizationUI,
        start: () -> Void
    ) async -> ScreenResolution<Value> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.install(continuation)
                if Task.isCancelled {
                    if session.cancel(.taskCancelled) {
                        authorizationUI.dismiss()
                    }
                    return
                }
                guard !session.isFinished else { return }
                start()
            }
        } onCancel: {
            Task { @MainActor in
                if session.cancel(.taskCancelled) {
                    authorizationUI.dismiss()
                }
            }
        }
    }

    private static func biometricTokenIfAvailable() async -> EnclaveToken? {
        guard AuthSupport.status.authorizableMethods.contains(.biometrics) else {
            return nil
        }
        do {
            return try await AuthSupport.authorizeWithBiometrics(sessionKind: .reusable)
        } catch {
            return nil
        }
    }
}

private struct CompactConfirmationHeader<Content: ConfirmationContent>: View {
    let content: Content

    var body: some View {
        content.compactRepresentation
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }
}

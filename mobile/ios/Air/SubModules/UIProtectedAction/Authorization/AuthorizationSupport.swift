import UIKit
import ProtectedAction
import UIComponents
import WalletContext
import WalletCore

private let authorizationLog = Log("ProtectedActionAuthorization")

@MainActor
enum AuthorizationSupport {
    static func performSoftwareSubmission<Result: MfaProtectedActionResult>(
        account: MAccount,
        software: SoftwareOperation<Result>,
        enclaveToken: EnclaveToken
    ) async -> SoftwareSubmission<Result> {
        do {
            try await AccountStore.refreshStoredMfa(accountId: account.id, enclaveToken: enclaveToken)
        } catch {
            authorizationLog.error(
                "Failed to refresh MFA state before protected action: \(error, .public)"
            )
        }
        return await software.submit(enclaveToken)
    }

    static func presentFeedbackAndWait(
        on viewController: UIViewController,
        feedback: SubmissionFeedback
    ) async -> Bool {
        switch feedback {
        case .notCommitted(let error):
            return await presentErrorAndWait(error, on: viewController)
        case .partiallyCommitted, .indeterminate:
            guard let title = feedback.title, let message = feedback.message else {
                return false
            }
            return await presentAlertAndWait(
                title: title,
                message: message,
                on: viewController
            )
        }
    }

    @discardableResult
    static func presentErrorAndWait(
        _ error: any Error,
        on viewController: UIViewController
    ) async -> Bool {
        guard canPresentAlert(on: viewController) else { return false }
        await withCheckedContinuation { continuation in
            viewController.showAlert(error: error) {
                continuation.resume()
            }
        }
        return true
    }

    private static func presentAlertAndWait(
        title: String,
        message: String,
        on viewController: UIViewController
    ) async -> Bool {
        guard canPresentAlert(on: viewController) else { return false }
        await withCheckedContinuation { continuation in
            viewController.showAlert(
                title: title,
                text: message,
                button: lang("OK")
            ) {
                continuation.resume()
            }
        }
        return true
    }

    private static func canPresentAlert(on viewController: UIViewController) -> Bool {
        !(viewController is UIAlertController)
            && viewController.presentedViewController == nil
            && !(topViewController() is UIAlertController)
            && viewController.viewIfLoaded?.window != nil
    }

    static func presentSheet(
        _ viewController: UIViewController,
        on presenter: UIViewController,
        animated: Bool = true
    ) -> Bool {
        guard presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil,
              !presenter.isBeingDismissed else {
            return false
        }
        presenter.present(viewController, animated: animated)
        return viewController.presentingViewController != nil
    }

    static func remove(
        _ viewController: UIViewController,
        from navigationController: UINavigationController,
        animated: Bool
    ) async {
        guard let index = navigationController.viewControllers.firstIndex(where: { $0 === viewController }) else {
            return
        }
        if animated, navigationController.topViewController === viewController {
            navigationController.popViewController(animated: true)
            await waitForTransition(navigationController)
        } else {
            var viewControllers = navigationController.viewControllers
            viewControllers.remove(at: index)
            navigationController.setViewControllers(viewControllers, animated: false)
        }
    }

    static func dismiss(_ navigationController: UINavigationController) async {
        guard navigationController.presentingViewController != nil else { return }
        await withCheckedContinuation { continuation in
            navigationController.dismiss(animated: true) {
                continuation.resume()
            }
        }
    }

    @discardableResult
    static func push(
        _ viewController: UIViewController,
        replacing previousViewController: UIViewController,
        in navigationController: UINavigationController
    ) -> Bool {
        guard navigationController.topViewController === previousViewController else {
            return false
        }
        navigationController.pushViewController(viewController, animated: true)
        Task { @MainActor in
            await waitForTransition(navigationController)
            guard navigationController.viewControllers.contains(where: { $0 === viewController }) else {
                return
            }
            await remove(
                previousViewController,
                from: navigationController,
                animated: false
            )
        }
        return true
    }

    static func removeAuthorizationSequence(
        _ viewControllers: [UIViewController],
        from navigationController: UINavigationController
    ) {
        let identifiers = Set(viewControllers.map(ObjectIdentifier.init))
        let remaining = navigationController.viewControllers.filter {
            !identifiers.contains(ObjectIdentifier($0))
        }
        guard !remaining.isEmpty else { return }
        navigationController.setViewControllers(remaining, animated: false)
    }

    private static func waitForTransition(_ navigationController: UINavigationController) async {
        guard let coordinator = navigationController.transitionCoordinator else {
            await Task.yield()
            return
        }
        await withCheckedContinuation { continuation in
            var resumed = false
            let resume = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            if !coordinator.animate(alongsideTransition: nil, completion: { _ in resume() }) {
                resume()
            }
        }
    }
}

@MainActor
final class WeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?
}

@MainActor
final class Reference<Value>: @unchecked Sendable {
    var value: Value?
}

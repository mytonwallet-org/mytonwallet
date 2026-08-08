import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor
public enum PasscodeAuthPresenter {
    @discardableResult
    public static func push(
        on vc: UIViewController,
        title: String,
        customHeaderVC: UIViewController,
        compactHeaderVC: UIViewController? = nil,
        sessionKind: AuthSessionKind = .oneShot,
        useBioOnPresent: Bool = true,
        biometricPassAllowed: Bool = true,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        onAuthTask: @escaping (_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void,
        onDone: @escaping (_ enclaveToken: EnclaveToken) -> Void,
        onCancel: (() -> Void)? = nil
    ) -> UnlockVC? {
        guard let navigationController = vc.navigationController else { return nil }
        let unlockVC = UnlockVC(
            title: title,
            replacedTitle: nil,
            subtitle: nil,
            customHeaderVC: customHeaderVC,
            compactHeaderVC: compactHeaderVC,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
            animatedPresentation: false,
            dissmissWhenAuthorized: false,
            shouldBeThemedLikeHeader: false,
            onAuthTask: onAuthTask,
            onDone: onDone,
            cancellable: false,
            onCancel: onCancel,
            useBioOnPresent: useBioOnPresent,
            biometricPassAllowed: biometricPassAllowed,
            authSessionKind: sessionKind
        )
        navigationController.pushViewController(unlockVC, animated: true)
        return unlockVC
    }

    public static func present(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        compactHeaderVC: UIViewController? = nil,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        onAuthTask: ((_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void)? = nil,
        onDone: @escaping (_ enclaveToken: EnclaveToken?) -> Void,
        cancellable: Bool,
        onCancel: (() -> Void)? = nil
    ) {
        guard AuthSupport.accountsSupportAppLock else {
            onDone(nil)
            return
        }

        func makeUnlockVC(useBioOnPresent: Bool) -> UIViewController {
            let unlockVC = UnlockVC(
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                compactHeaderVC: compactHeaderVC,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                dissmissWhenAuthorized: false,
                onAuthTask: onAuthTask,
                onDone: { enclaveToken in onDone(enclaveToken) },
                cancellable: cancellable,
                onCancel: onCancel,
                useBioOnPresent: useBioOnPresent
            )
            if cancellable {
                let navVC = WNavigationController(rootViewController: unlockVC)
                navVC.navigationBar.tintColor = AirTintColor
                return navVC
            } else {
                return unlockVC
            }
        }

        let canUseBiometric = AuthSupport.status.authorizableMethods.contains(.biometrics)
        vc.present(makeUnlockVC(useBioOnPresent: canUseBiometric), animated: true)
    }

    public static func presentAsync(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        compactHeaderVC: UIViewController? = nil,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        authTask: (@MainActor (_ enclaveToken: EnclaveToken) async -> Void)? = nil
    ) async -> EnclaveToken? {
        guard AuthSupport.accountsSupportAppLock else {
            return nil
        }

        var onAuthTask: ((_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void)?
        if let authTask {
            onAuthTask = { enclaveToken, onTaskDone in
                Task {
                    await authTask(enclaveToken)
                    onTaskDone()
                }
            }
        }
        let lock = NSLock()

        return await withCheckedContinuation { (continuation: CheckedContinuation<EnclaveToken?, Never>) in
            var nillableContinuation: CheckedContinuation<EnclaveToken?, Never>? = continuation

            present(
                on: vc,
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                compactHeaderVC: compactHeaderVC,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                onAuthTask: onAuthTask,
                onDone: { enclaveToken in
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(returning: enclaveToken)
                    nillableContinuation = nil
                },
                cancellable: true,
                onCancel: {
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(returning: nil)
                    nillableContinuation = nil
                }
            )
        }
    }
}

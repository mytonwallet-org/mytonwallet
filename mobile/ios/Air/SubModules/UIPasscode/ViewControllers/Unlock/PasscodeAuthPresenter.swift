import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor
public enum PasscodeAuthPresenter {
    public static func push(
        on vc: UIViewController,
        title: String,
        customHeaderVC: UIViewController,
        useBioOnPresent: Bool = true,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        onAuthTask: @escaping (_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void,
        onDone: @escaping (_ passcode: String) -> Void
    ) {
        let unlockVC = UnlockVC(
            title: title,
            replacedTitle: nil,
            subtitle: nil,
            customHeaderVC: customHeaderVC,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
            animatedPresentation: false,
            dissmissWhenAuthorized: false,
            shouldBeThemedLikeHeader: false,
            onAuthTask: onAuthTask,
            onDone: onDone,
            cancellable: false,
            onCancel: nil,
            useBioOnPresent: useBioOnPresent
        )
        vc.navigationController?.pushViewController(unlockVC, animated: true)
    }

    public static func present(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        onAuthTask: ((_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void)? = nil,
        onDone: @escaping (_ passcode: String?) -> Void,
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
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                dissmissWhenAuthorized: false,
                onAuthTask: onAuthTask,
                onDone: onDone,
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

        let canUseBiometric = AppStorageHelper.isBiometricActivated() && BiometricHelper.biometryType != nil
        if onAuthTask == nil && canUseBiometric {
            Task { @MainActor [weak vc] in
                let result = await BiometricHelper.authenticate()
                switch result {
                case .success:
                    let passcode = KeychainHelper.biometricPasscode()
                    do {
                        guard try await AuthSupport.verifyPassword(password: passcode) else {
                            vc?.present(makeUnlockVC(useBioOnPresent: false), animated: true)
                            return
                        }
                        onDone(passcode)
                    } catch {
                        vc?.present(makeUnlockVC(useBioOnPresent: false), animated: true)
                    }

                case .canceled, .error, .userDeniedBiometrics:
                    vc?.present(makeUnlockVC(useBioOnPresent: false), animated: true)
                }
            }
        } else {
            vc.present(makeUnlockVC(useBioOnPresent: canUseBiometric), animated: true)
        }
    }

    public static func presentAsync(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        authTask: (@MainActor (_ passcode: String) async -> Void)? = nil
    ) async -> String? {
        guard AuthSupport.accountsSupportAppLock else {
            return nil
        }

        var onAuthTask: ((_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void)?
        if let authTask {
            onAuthTask = { passcode, onTaskDone in
                Task {
                    await authTask(passcode)
                    onTaskDone()
                }
            }
        }
        let lock = NSLock()

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var nillableContinuation: CheckedContinuation<String?, Never>? = continuation

            present(
                on: vc,
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                onAuthTask: onAuthTask,
                onDone: { password in
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(returning: password)
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

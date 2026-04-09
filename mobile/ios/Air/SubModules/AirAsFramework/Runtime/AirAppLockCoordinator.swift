import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

@MainActor
final class AirAppLockCoordinator: NSObject {
    private enum LockMode: Equatable {
        case launch
        case app
    }

    private let rootStateCoordinator: RootStateCoordinator
    private weak var unlockViewController: UnlockVC?
    private var lockMode: LockMode?
    private var bridgeIsReady = false
    private var canTryBiometrics = false

    private var didResolveUnlockPresentationDecision = false
    private var didPresentLaunchUnlock = false
    private var didRequestLaunchUnlockBiometric = false
    private var didAuthorizeLaunchUnlock = false
    private var isInitialRouteReady = false
    private var pendingLaunchPresentationCompletions: [() -> Void] = []

    var onUnlock: (() -> Void)?

    private(set) var isAppUnlocked = false

    init(rootStateCoordinator: RootStateCoordinator = .shared) {
        self.rootStateCoordinator = rootStateCoordinator
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func beginLaunchUnlockIfNeeded() {
        bridgeIsReady = false
        isAppUnlocked = false
        isInitialRouteReady = false
        didResolveUnlockPresentationDecision = false
        didPresentLaunchUnlock = false
        didRequestLaunchUnlockBiometric = false
        didAuthorizeLaunchUnlock = false
        lockMode = nil
        unlockViewController = nil
        pendingLaunchPresentationCompletions.removeAll()

        if DebugBypassLockscreen.isEnabled {
            resolveUnlockPresentationDecision(mark: "splash.afterUnlock.skipLock", result: "debugBypass")
            isAppUnlocked = true
            rootStateCoordinator.hideUnlockState()
            return
        }

        guard AuthSupport.accountsSupportAppLock else {
            resolveUnlockPresentationDecision(mark: "splash.afterUnlock.skipLock", result: "lockDisabled")
            isAppUnlocked = true
            rootStateCoordinator.hideUnlockState()
            return
        }

        resolveUnlockPresentationDecision(mark: "splash.afterUnlock.presentUnlock", result: "presentUnlock")
        rootStateCoordinator.transition(to: .unlock, animationDuration: nil)
        lockMode = .launch

        let unlockVC = UnlockVC(
            title: lang("Wallet is Locked"),
            replacedTitle: lang("Enter your Wallet Passcode"),
            animatedPresentation: true,
            dissmissWhenAuthorized: false,
            shouldBeThemedLikeHeader: true,
            onDone: { [weak self] _ in
                guard let self else { return }
                self.didAuthorizeLaunchUnlock = true
                self.completeLaunchUnlockIfPossible()
            },
            onSignOutRequested: { [weak self] in
                guard let self else { return }
                try await self.removeAllWalletsFromLockScreen()
            },
            successCompletionDelay: 0
        )
        unlockVC.modalPresentationStyle = .overFullScreen
        unlockVC.modalTransitionStyle = .crossDissolve
        unlockVC.modalPresentationCapturesStatusBarAppearance = true
        unlockVC.loadViewIfNeeded()
        unlockVC.passcodeScreenView.isUserInteractionEnabled = false
        unlockViewController = unlockVC
        present(unlockVC, animated: true) {
            self.didPresentLaunchUnlock = true
            let pendingLaunchPresentationCompletions = self.pendingLaunchPresentationCompletions
            self.pendingLaunchPresentationCompletions.removeAll()
            unlockVC.passcodeScreenView.isUserInteractionEnabled = self.bridgeIsReady
            pendingLaunchPresentationCompletions.forEach { $0() }
            self.tryLaunchUnlockBiometricIfPossible()
        }
    }

    func bridgeDidBecomeReady() {
        bridgeIsReady = true
        if lockMode == .launch {
            unlockViewController?.passcodeScreenView.isUserInteractionEnabled = true
        }
        tryLaunchUnlockBiometricIfPossible()
    }

    func markInitialRouteReady() {
        isInitialRouteReady = true
        completeLaunchUnlockIfPossible()
    }

    func performAfterLaunchUnlockPresentation(_ action: @escaping () -> Void) {
        guard lockMode == .launch, !didPresentLaunchUnlock else {
            action()
            return
        }
        pendingLaunchPresentationCompletions.append(action)
    }

    func lockApp(animated: Bool) {
        if DebugBypassLockscreen.isEnabled {
            unlockViewController?.dismiss(animated: false)
            unlockViewController = nil
            lockMode = nil
            isAppUnlocked = true
            rootStateCoordinator.hideUnlockState()
            return
        }

        guard AuthSupport.accountsSupportAppLock else { return }
        guard lockMode == nil else { return }

        isAppUnlocked = false
        lockMode = .app
        rootStateCoordinator.transition(to: .unlock, animationDuration: nil)

        let unlockVC = UnlockVC(
            title: lang("Wallet is Locked"),
            replacedTitle: lang("Enter your Wallet Passcode"),
            animatedPresentation: true,
            dissmissWhenAuthorized: true,
            shouldBeThemedLikeHeader: true,
            onDone: { [weak self] _ in
                guard let self else { return }
                self.unlockViewController = nil
                self.lockMode = nil
                self.rootStateCoordinator.hideUnlockState()
                self.isAppUnlocked = true
                self.onUnlock?()
            },
            onSignOutRequested: { [weak self] in
                guard let self else { return }
                try await self.removeAllWalletsFromLockScreen()
            }
        )
        unlockVC.modalPresentationStyle = .overFullScreen
        unlockVC.modalTransitionStyle = .crossDissolve
        unlockVC.modalPresentationCapturesStatusBarAppearance = true
        unlockVC.loadViewIfNeeded()
        unlockViewController = unlockVC

        present(unlockVC, animated: animated) {
            self.tryBiometricsIfPossible()
        }
    }

    func reset() {
        unlockViewController?.dismiss(animated: false)
        unlockViewController = nil
        lockMode = nil
        bridgeIsReady = false
        canTryBiometrics = false
        didResolveUnlockPresentationDecision = false
        didPresentLaunchUnlock = false
        didRequestLaunchUnlockBiometric = false
        didAuthorizeLaunchUnlock = false
        isInitialRouteReady = false
        pendingLaunchPresentationCompletions.removeAll()
        isAppUnlocked = false
        rootStateCoordinator.hideUnlockState()
    }

    private func removeAllWalletsFromLockScreen() async throws {
        try await AccountStore.resetAccounts()
        reset()
    }

    private func completeLaunchUnlockIfPossible() {
        guard lockMode == .launch else { return }
        guard didAuthorizeLaunchUnlock, isInitialRouteReady else { return }

        StartupTrace.mark("splash.afterUnlock.completed")
        isAppUnlocked = true
        lockMode = nil
        didPresentLaunchUnlock = false
        didRequestLaunchUnlockBiometric = false
        didAuthorizeLaunchUnlock = false
        rootStateCoordinator.hideUnlockState()

        let dismissingUnlockViewController = unlockViewController
        unlockViewController = nil
        dismissingUnlockViewController?.dismiss(animated: true) {
            self.onUnlock?()
        }
    }

    private func resolveUnlockPresentationDecision(mark: String, result: String) {
        guard !didResolveUnlockPresentationDecision else { return }
        didResolveUnlockPresentationDecision = true
        StartupTrace.mark(mark)
        StartupTrace.endInterval("startup.toPresentUnlock", details: "result=\(result)")
    }

    private func tryLaunchUnlockBiometricIfPossible() {
        guard lockMode == .launch else { return }
        guard !didRequestLaunchUnlockBiometric else { return }
        guard bridgeIsReady else { return }
        guard let unlockViewController, !isAppUnlocked else { return }
        didRequestLaunchUnlockBiometric = true
        unlockViewController.passcodeScreenView.isUserInteractionEnabled = true
        StartupTrace.markOnce("splash.biometric.begin")
        unlockViewController.tryBiometric()
    }

    private func present(_ unlockViewController: UnlockVC, animated: Bool, completion: @escaping () -> Void) {
        let presenter = topViewController() ?? rootStateCoordinator.rootHostViewController
        if presenter is UIActivityViewController, let presentingViewController = presenter.presentingViewController {
            presentingViewController.dismiss(animated: false) {
                self.present(unlockViewController, animated: animated, completion: completion)
            }
            return
        }

        presenter.present(unlockViewController, animated: animated, completion: completion)
    }

    private func tryBiometricsIfPossible() {
        guard lockMode == .app else { return }
        guard canTryBiometrics else { return }
        guard unlockViewController != nil else { return }

        canTryBiometrics = false
        unlockViewController?.tryBiometric()
    }

    @objc
    private func appDidBecomeActive() {
        tryBiometricsIfPossible()
    }

    @objc
    private func willEnterForeground() {
        canTryBiometrics = true
        if lockMode == .app {
            unlockViewController?.passcodeScreenView?.fadeIn()
        }
    }
}

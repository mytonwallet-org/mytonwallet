import Foundation
import WalletCore
import WalletContext

private let log = Log("AirStartupCoordinator")

@MainActor
final class AirStartupCoordinator {
    private let lockCoordinator: AirAppLockCoordinator

    private var bridgeIsReady = false
    private var walletCoreDataReady = false
    private var didResolveInitialRoute = false
    private var didStartAccountActivation = false
    private var accountActivationTask: Task<Void, Never>?

    init(lockCoordinator: AirAppLockCoordinator) {
        self.lockCoordinator = lockCoordinator
    }

    func beginLaunch() {
        StartupTrace.mark("splashVM.startApp")
        didResolveInitialRoute = false
        didStartAccountActivation = false
        accountActivationTask?.cancel()
        accountActivationTask = nil
        lockCoordinator.beginLaunchUnlockIfNeeded()
    }

    func bridgeDidBecomeReady() {
        StartupTrace.mark("splash.bridge.ready")
        bridgeIsReady = true
        lockCoordinator.bridgeDidBecomeReady()
        activateCurrentAccountIfPossible()
    }

    func walletCoreBootstrapDidFinish() {
        StartupTrace.mark("splash.walletCoreData.ready")
        walletCoreDataReady = true
        resolveInitialRouteIfPossible()
        activateCurrentAccountIfPossible()
    }

    func restart() {
        StartupTrace.mark("splash.startApp.restart")
        didResolveInitialRoute = false
        resolveInitialRouteIfPossible()
    }

    private func resolveInitialRouteIfPossible() {
        guard walletCoreDataReady, !didResolveInitialRoute else { return }
        didResolveInitialRoute = true
        let initialRootState: AppRootState
        let animationDuration: Double
        if preferredStartupAccountId() == nil {
            initialRootState = .intro
            animationDuration = 0.5
        } else {
            initialRootState = .active
            animationDuration = 0.2
        }

        lockCoordinator.performAfterLaunchUnlockPresentation { [weak self] in
            guard let self else { return }
            switch initialRootState {
            case .intro:
                StartupTrace.mark("splash.navigateToIntro")
            case .active:
                StartupTrace.mark("splash.navigateToHome")
            case .unlock:
                return
            case .startupFailure:
                return
            }
            AppActions.transitionToRootState(initialRootState, animationDuration: animationDuration)
            self.lockCoordinator.markInitialRouteReady()
        }
    }

    private func activateCurrentAccountIfPossible() {
        guard walletCoreDataReady, bridgeIsReady, !didStartAccountActivation else { return }
        guard let activeAccountId = preferredStartupAccountId() else { return }
        didStartAccountActivation = true
        log.info("activating account \(activeAccountId, .public)")
        StartupTrace.beginInterval("splashVM.activateAccount")
        StartupTrace.mark("splashVM.activateAccount.begin")
        accountActivationTask = Task { @MainActor in
            defer { self.accountActivationTask = nil }
            do {
                let account = try await AccountStore.activateAccount(accountId: activeAccountId)
                self.activationFinished(account: account)
            } catch {
                log.fault("failed to activate account: \(error, .public) id=\(activeAccountId, .public)")
                StartupTrace.mark("splashVM.activateAccount.failed", details: "tryingFallback=true")
                for accountId in fallbackStartupAccountIds(excluding: activeAccountId) {
                    do {
                        let account = try await AccountStore.activateAccount(accountId: accountId)
                        StartupTrace.mark("splashVM.activateAccount.fallback.success")
                        self.activationFinished(account: account)
                        return
                    } catch {
                        log.fault("failed to activate fallback account: \(error, .public) id=\(accountId, .public)")
                        continue
                    }
                }
                log.error("failed to activate all startup accounts; will continue without blocking login")
                StartupTrace.mark("splashVM.activateAccount.fallback.failedAll", details: "continuingWithoutBlockingLogin=true")
                StartupTrace.endInterval("splashVM.activateAccount", details: "result=allFailedNonBlocking")
            }
            do {
                try await AccountStore.removeAllTemporaryAccounts()
            } catch {
                log.error("failed to remove all temporary accounts: \(error, .public)")
            }
        }
    }

    private func preferredStartupAccountId() -> String? {
        if let accountId = AccountStore.accountId {
            return accountId
        }
        if let orderedAccountId = AccountStore.orderedAccountIds.first {
            return orderedAccountId
        }
        return AccountStore.accountsById.keys.sorted().first
    }

    private func fallbackStartupAccountIds(excluding activeAccountId: String) -> [String] {
        let orderedFallbackIds = AccountStore.orderedAccountIds.filter { $0 != activeAccountId }
        let extraFallbackIds = AccountStore.accountsById.keys
            .sorted()
            .filter { $0 != activeAccountId && !orderedFallbackIds.contains($0) }
        return orderedFallbackIds + extraFallbackIds
    }

    private func activationFinished(account: Any?) {
        guard account != nil else { return }
        StartupTrace.mark("splashVM.activateAccount.success")
        StartupTrace.endInterval("splashVM.activateAccount", details: "result=success")
    }
}

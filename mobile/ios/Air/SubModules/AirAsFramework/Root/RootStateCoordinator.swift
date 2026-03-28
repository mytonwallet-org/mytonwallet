import UIKit
import UICreateWallet
import UIComponents
import WalletCore
import WalletContext

private let log = Log("RootStateCoordinator")

@MainActor
final class RootStateCoordinator: WalletCoreData.EventsObserver {
    static let shared = RootStateCoordinator()
    private let hostViewController = RootHostVC()
    private let layoutResolver: any RootContainerLayoutResolving = RootContainerLayoutResolver()
    private var startupFailureController: StartupFailureVC?
    
    private init() {
        WalletCoreData.add(eventObserver: self)
    }

    var rootHostViewController: RootHostVC {
        hostViewController
    }
    
    func transition(to rootState: AppRootState, animationDuration: Double?) {
        let rootStateName = name(for: rootState)
        StartupTrace.beginInterval("rootState.transition.\(rootStateName)")
        StartupTrace.mark("rootState.transition.begin", details: "state=\(rootStateName)")
        if rootState == .unlock {
            showUnlockState()
            StartupTrace.mark("rootState.transition.contentAttached", details: "state=\(rootStateName)")
            StartupTrace.endInterval("rootState.transition.\(rootStateName)", details: "result=done")
            return
        }

        let targetContentViewController = buildRootViewController(for: rootState)
        guard let window = UIApplication.shared.sceneKeyWindow ?? UIApplication.shared.anySceneKeyWindow else {
            log.fault("failed to set root state: key window is nil")
            StartupTrace.mark("rootState.transition.abort", details: "state=\(rootStateName) window=nil")
            StartupTrace.endInterval("rootState.transition.\(rootStateName)", details: "result=windowNil")
            return
        }
        
        installAsRootViewController(on: window, animationDuration: nil)
        hostViewController.setContentViewController(targetContentViewController, rootState: rootState, animationDuration: animationDuration)
        StartupTrace.mark("rootState.transition.contentAttached", details: "state=\(rootStateName)")
        
        if rootState != .startupFailure {
            do {
                let apiBridgeTarget = apiBridgeTargetViewController(for: hostViewController)
                try Api.bridge.moveToViewController(apiBridgeTarget)
                StartupTrace.mark("rootState.transition.bridgeMoved", details: "state=\(rootStateName)")
            } catch {
                log.fault("moveToViewController failed: bridge is nil")
            }
        }
        StartupTrace.endInterval("rootState.transition.\(rootStateName)", details: "result=done")
    }

    func showStartupFailure(_ failure: StartupFailure, onRetry: @escaping () -> Void) {
        startupFailureController = StartupFailureVC(failure: failure, onRetry: onRetry)
        transition(to: .startupFailure, animationDuration: 0.2)
    }

    func installAsRootViewController(on window: UIWindow, animationDuration: Double?) {
        guard window.rootViewController !== hostViewController else { return }
        window.rootViewController = hostViewController
        if let animationDuration {
            UIView.transition(with: window, duration: animationDuration, options: [.transitionCrossDissolve]) {
            }
        }
    }

    func showUnlockState() {
        hostViewController.setUnlockPresented(true)
    }

    func hideUnlockState() {
        hostViewController.setUnlockPresented(false)
    }

    func reset() {
        hideUnlockState()
        hostViewController.reset()
        startupFailureController = nil
    }
    
    private func buildRootViewController(for rootState: AppRootState) -> UIViewController {
        switch rootState {
        case .intro:
            return WNavigationController(rootViewController: IntroVC(introModel: IntroModel(network: .mainnet, password: nil)))
        case .active:
            return layoutResolver.buildActiveRootViewController()
        case .unlock:
            return UIViewController()
        case .startupFailure:
            return startupFailureController ?? StartupFailureVC(
                failure: StartupFailure(
                    phase: .databaseBootstrap,
                    kind: .unknown,
                    title: lang("Error"),
                    message: "MyTonWallet couldn't start safely.",
                    technicalCode: "databaseBootstrap.unknown",
                    detailsText: "Technical code: databaseBootstrap.unknown"
                ),
                onRetry: {}
            )
        }
    }
    
    private func apiBridgeTargetViewController(for rootViewController: UIViewController) -> UIViewController {
        if let nc = rootViewController as? UINavigationController, let firstVC = nc.viewControllers.first {
            return firstVC
        }
        return rootViewController
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountsReset:
            WalletCoreData.removeObservers()
            WalletContextManager.delegate?.walletIsReady(isReady: false)
            transition(to: .intro, animationDuration: 0.5)
        default:
            break
        }
    }

    private func name(for rootState: AppRootState) -> String {
        switch rootState {
        case .intro:
            "intro"
        case .active:
            "active"
        case .unlock:
            "unlock"
        case .startupFailure:
            "startupFailure"
        }
    }
}

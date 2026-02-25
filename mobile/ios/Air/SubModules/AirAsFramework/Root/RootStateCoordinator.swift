import UIKit
import UICreateWallet
import UIComponents
import WalletCore
import WalletContext

private let log = Log("RootStateCoordinator")

@MainActor
final class RootStateCoordinator: WalletCoreData.EventsObserver {
    static let shared = RootStateCoordinator()
    private let rootHostViewController = RootHostVC()
    private let layoutResolver: any RootContainerLayoutResolving = RootContainerLayoutResolver()
    
    private init() {
        WalletCoreData.add(eventObserver: self)
    }
    
    func transition(to rootState: AppRootState, animationDuration: Double?) {
        let targetContentViewController = buildRootViewController(for: rootState)
        guard let window = UIApplication.shared.sceneKeyWindow ?? UIApplication.shared.anySceneKeyWindow else {
            log.fault("failed to set root state: key window is nil")
            return
        }
        
        if window.rootViewController === rootHostViewController {
            rootHostViewController.setContentViewController(targetContentViewController, animationDuration: animationDuration)
        } else {
            window.rootViewController = self.rootHostViewController
            self.rootHostViewController.setContentViewController(targetContentViewController, animationDuration: nil)
            if let animationDuration {
                // layout happens before animated transition
                UIView.transition(with: window, duration: animationDuration, options: [.transitionCrossDissolve]) {
                }
            }
        }
        
        do {
            let apiBridgeTarget = apiBridgeTargetViewController(for: rootHostViewController)
            try Api.bridge.moveToViewController(apiBridgeTarget)
        } catch {
            log.fault("moveToViewController failed: bridge is nil")
        }
    }
    
    private func buildRootViewController(for rootState: AppRootState) -> UIViewController {
        switch rootState {
        case .intro:
            return WNavigationController(rootViewController: IntroVC(introModel: IntroModel(network: .mainnet, password: nil)))
        case .active:
            return layoutResolver.buildActiveRootViewController()
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
}

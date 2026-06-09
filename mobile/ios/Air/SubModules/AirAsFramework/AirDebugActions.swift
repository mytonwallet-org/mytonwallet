import UIKit
import UIAgent
import UIComponents
import UICreateWallet
import UIHome
import UIPasscode
import WalletCore
import WalletContext

@MainActor
public enum AirDebugActions {
    public static func forceIntro() {
        guard let presenter = topViewController() else { return }

        guard AuthSupport.accountsSupportAppLock else {
            presentIntro(password: nil)
            return
        }

        UnlockVC.presentAuth(
            on: presenter,
            onDone: { passcode in
                Task { @MainActor in
                    guard let passcode else { return }
                    presentIntro(password: passcode)
                }
            },
            cancellable: true
        )
    }

    public static func resetAgentConsentState() {
        AgentEntryPoint.resetConsentStateForDebug()
        resetAgentRoot()
    }

    private static func presentIntro(password: String?) {
        let intro = IntroVC(introModel: IntroModel(network: .mainnet, password: password), showsCloseButton: true)
        let navigationController = WNavigationController(rootViewController: intro)
        navigationController.modalPresentationStyle = .fullScreen
        topViewController()?.present(navigationController, animated: true)
    }

    private static func resetAgentRoot() {
        for window in UIApplication.shared.sceneWindows {
            window.rootViewController?
                .descendantViewController(of: HomeTabBarController.self)?
                .debugOnly_resetAgentRoot()
            window.rootViewController?
                .descendantViewController(of: SplitRootViewController.self)?
                .debugOnly_resetAgentRoot()
        }
    }
}

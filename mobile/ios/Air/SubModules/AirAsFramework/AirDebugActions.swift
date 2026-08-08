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
            presentIntro(enclaveToken: nil)
            return
        }

        UnlockVC.presentAuth(
            on: presenter,
            onDone: { enclaveToken in
                Task { @MainActor in
                    presentIntro(enclaveToken: enclaveToken)
                }
            },
            cancellable: true
        )
    }

    public static func resetAgentConsentState() {
        AgentEntryPoint.resetConsentStateForDebug()
        resetAgentRoot()
    }

    #if DEBUG && targetEnvironment(simulator)

    public enum AppWalletsExportOutcome: Sendable {
        case success(AppWalletsExport.ExportResult)
        case cancelled
        case failure(Error)
    }

    public static func exportWallets() async -> AppWalletsExportOutcome {
        var enclaveToken: EnclaveToken?
        if AppWalletsExport.hasDecryptableMnemonicAccounts() {
            guard let authPresenter = topViewController() else {
                return .failure(DisplayError(text: "No presenter"))
            }

            guard let token = await UnlockVC.presentAuthAsync(on: authPresenter, title: lang("Enter your code")) else {
                return .cancelled
            }
            enclaveToken = token
        }

        do {
            let result = try await AppWalletsExport.export(enclaveToken: enclaveToken)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    #endif

    private static func presentIntro(enclaveToken: EnclaveToken?) {
        let intro = IntroVC(introModel: IntroModel(network: .mainnet, authMode: IntroAuthMode(enclaveToken: enclaveToken)), showsCloseButton: true)
        let navigationController = WNavigationController(rootViewController: intro)
        navigationController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
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

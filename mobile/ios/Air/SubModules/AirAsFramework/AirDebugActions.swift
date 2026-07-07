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

    #if DEBUG && targetEnvironment(simulator)

    public enum AppWalletsExportOutcome: Sendable {
        case success(AppWalletsExport.ExportResult)
        case cancelled
        case failure(Error)
    }

    public static func exportWallets() async -> AppWalletsExportOutcome {
        var passcode: String?

        if AppWalletsExport.hasDecryptableMnemonicAccounts() {
            guard let authPresenter = topViewController() else {
                return .failure(DisplayError(text: "No presenter"))
            }

            guard let enteredPasscode = await UnlockVC.presentAuthAsync(on: authPresenter, title: lang("Enter your code")) else {
                return .cancelled
            }
            passcode = enteredPasscode
        }

        do {
            let result = try await AppWalletsExport.export(passcode: passcode)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    #endif

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

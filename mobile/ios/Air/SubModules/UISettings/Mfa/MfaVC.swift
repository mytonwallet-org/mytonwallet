import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("MfaVC")

@MainActor
final class MfaVC: SettingsBaseVC {
    private let accountContext = AccountContext(source: .current)
    private lazy var flowModel = MfaFlowModel(accountContext: accountContext)
    private var hostingController: UIHostingController<MfaView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        bindFlow()
    }

    private func setupViews() {
        title = nil
        hostingController = addHostingController(
            MfaView(accountContext: accountContext, model: flowModel),
            constraints: .fill
        )
        view.backgroundColor = .air.groupedBackground
    }

    private func bindFlow() {
        flowModel.onInstallConfirmationRequested = { [weak self] user in
            self?.showConfirmation(
                title: lang("Confirm Connection"),
                user: user,
                useBioOnPresent: false
            ) { viewModel, passcode in
                try await viewModel.confirmInstall(passcode: passcode)
            }
        }
        flowModel.onRemoveConfirmationRequested = { [weak self] user in
            self?.showConfirmation(
                title: lang("Confirm Disconnection"),
                user: user
            ) { viewModel, passcode in
                try await viewModel.confirmRemove(passcode: passcode)
            }
        }
    }

    private func showConfirmation(
        title: String,
        user: AccountMfa.User?,
        useBioOnPresent: Bool = true,
        action: @escaping @MainActor (MfaFlowModel, String) async throws -> Void
    ) {
        guard navigationController?.topViewController === self else {
            return
        }

        let account = accountContext.account
        Task {
            do {
                _ = try await AppActions.authorizeProtectedAction(
                    on: self,
                    account: account,
                    title: title,
                    headerView: MfaConfirmHeaderView(account: account, title: title, user: user),
                    passwordAction: { [weak self] passcode in
                        guard let self else { throw CancellationError() }
                        try await action(self.flowModel, passcode)
                        return ApiMfaProtectedResult()
                    },
                    useBioOnPresent: useBioOnPresent,
                    mfaTitle: title
                )
            } catch is CancellationError {
            } catch {
                log.error("MFA confirmation failed: \(error, .public)")
                showAlert(error: error)
            }
        }
    }
}

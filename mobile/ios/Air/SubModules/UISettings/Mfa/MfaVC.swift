import SwiftUI
import UIKit
import ProtectedAction
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
                biometricPolicy: .disabled
            ) { viewModel, enclaveToken in
                try await viewModel.confirmInstall(enclaveToken: enclaveToken)
            }
        }
        flowModel.onRemoveConfirmationRequested = { [weak self] user in
            self?.showConfirmation(
                title: lang("Confirm Disconnection"),
                user: user
            ) { viewModel, enclaveToken in
                try await viewModel.confirmRemove(enclaveToken: enclaveToken)
            }
        }
    }

    private func showConfirmation(
        title: String,
        user: AccountMfa.User?,
        biometricPolicy: BiometricPolicy = .onAuthorizationScreen,
        action: @escaping @MainActor (MfaFlowModel, EnclaveToken) async throws -> Void
    ) {
        guard navigationController?.topViewController === self else {
            return
        }

        let account = accountContext.account
        let protectedAction = ProtectedAction.mfaSettings(
            account: account,
            title: title,
            user: user,
            biometricPolicy: biometricPolicy,
            flowModel: flowModel,
            action: action
        )
        Task {
            let outcome = await ProtectedActionExecutor.execute(protectedAction, on: self)
            if case .failed(let error) = outcome {
                log.error("MFA confirmation failed: \(error, .public)")
            }
        }
    }
}

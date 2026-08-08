import WalletContext
import WalletCore
import ProtectedAction

extension ProtectedAction where HeaderView == MfaConfirmHeaderView, Result == ApiMfaProtectedResult {
    static func mfaSettings(
        account: MAccount,
        title: String,
        user: AccountMfa.User?,
        biometricPolicy: BiometricPolicy,
        flowModel: MfaFlowModel,
        action: @escaping @MainActor (MfaFlowModel, EnclaveToken) async throws -> Void
    ) -> Self {
        Self(
            account: account,
            software: .single { enclaveToken in
                try await action(flowModel, enclaveToken)
                return ApiMfaProtectedResult()
            },
            hardware: nil,
            confirmation: .init(
                title: title,
                header: MfaConfirmHeaderView(account: account, title: title, user: user),
                biometricPolicy: biometricPolicy,
                prefersNavigationTitleWithCustomHeader: false
            )
        )
    }
}

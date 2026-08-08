import WalletContext
import WalletCore
import ProtectedAction

extension ProtectedAction where HeaderView == RenewDomainAuthHeader, Result == ApiMfaProtectedResult {
    static func renewDomains(
        snapshot: RenewDomainConfirmationSnapshot,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: snapshot.account,
            software: .custom { enclaveToken in
                await submitRenewDomains(snapshot: snapshot, enclaveToken: enclaveToken)
            },
            hardware: makeRenewDomainsLedgerOperation(snapshot: snapshot),
            confirmation: .init(
                title: lang("Confirm Renewing"),
                header: RenewDomainAuthHeader(snapshot: snapshot)
            ),
            completion: .handoff { _ in
                onCommitted()
            }
        )
    }
}

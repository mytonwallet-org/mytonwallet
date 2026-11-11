import WalletContext
import WalletCore
import ProtectedAction

extension ProtectedAction where HeaderView == LinkDomainAuthHeader, Result == ApiMfaProtectedResult {
    static func linkDomain(
        snapshot: LinkDomainConfirmationSnapshot,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            account: snapshot.account,
            software: .single { enclaveToken in
                try await submitLinkDomain(snapshot: snapshot, enclaveToken: enclaveToken)
            },
            hardware: makeLinkDomainLedgerOperation(snapshot: snapshot),
            confirmation: .init(
                title: snapshot.isUnlinking ? lang("Confirm Unlinking") : lang("Confirm Linking"),
                header: LinkDomainAuthHeader(snapshot: snapshot)
            ),
            completion: .handoff { _ in
                onCommitted()
            }
        )
    }
}

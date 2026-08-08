import ProtectedAction
import WalletContext

extension ProtectedAction
where HeaderView == TokenSendingHeaderView,
      Result == SendSubmissionResult {
    static func tokenSend(
        confirmed: ConfirmedTokenSend
    ) -> Self {
        Self(
            account: confirmed.account,
            software: .single { enclaveToken in
                try await confirmed.submit(enclaveToken: enclaveToken)
            },
            hardware: {
                try await confirmed.makeLedgerOperation()
            },
            confirmation: .init(
                title: confirmed.protectedActionTitle,
                header: TokenSendingHeaderView(
                    confirmed: confirmed
                ),
                prefersNavigationTitleWithCustomHeader: false
            ),
            completion: .activity(ActivityCompletion(
                context: .sendConfirmation,
                matches: { activity, receipt in
                    receipt.correlates(with: activity)
                },
                fallbackMatches: { activity, _ in
                    confirmed.matchesCommittedActivity(activity)
                }
            ))
        )
    }
}

import ProtectedAction

extension ProtectedAction
where HeaderView == NftSendingHeaderView,
      Result == SendSubmissionResult {
    static func nftSend(
        confirmed: ConfirmedNftSend
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
                header: NftSendingHeaderView(
                    confirmed: confirmed
                ),
                prefersNavigationTitleWithCustomHeader: true
            ),
            completion: .replace { _ in
                makeSuccessReplacement(confirmed: confirmed)
            }
        )
    }

    private static func makeSuccessReplacement(
        confirmed: ConfirmedNftSend
    ) -> Replacement {
        let viewController = NftSendSuccessViewController(
            confirmed: confirmed
        )
        viewController.navigationItem.hidesBackButton = true
        return Replacement(viewController: viewController) { [weak viewController] in
            viewController?.animateToCollapsed()
        }
    }
}

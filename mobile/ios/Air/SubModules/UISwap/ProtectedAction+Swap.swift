import ProtectedAction
import WalletContext
import WalletCore

extension ProtectedAction where HeaderView == SwapConfirmHeaderView, Result == SwapExecutionResult {

    static func swap(
        model: SwapModel,
        presentCrosschainResult: Bool,
        payoutAddress: String?
    ) -> Self? {
        guard let snapshot = model.makeConfirmationSnapshot(payoutAddress: payoutAddress) else {
            return nil
        }
        let completion: Completion<SwapExecutionResult>
        if presentCrosschainResult {
            completion = .replace { receipt in
                Self.makeCrosschainResultReplacement(receipt: receipt)
            }
        } else {
            let context: ActivityDetailsContext = snapshot.swapType == .onChain
                ? .onchainSwapConfirmation
                : .swapConfirmation
            completion = .activity(
                ActivityCompletion(
                    sources: [.local, .pendingOrConfirmed],
                    context: context,
                    matches: { activity, receipt in
                        SwapExecutionResult.matches(activity: activity, receipt: receipt)
                    }
                )
            )
        }
        return Self(
            account: snapshot.account.account,
            software: .single { [weak model] enclaveToken in
                guard let model else { throw CancellationError() }
                return try await model.performSwap(snapshot: snapshot, enclaveToken: enclaveToken)
            },
            hardware: nil,
            confirmation: .init(
                title: lang("Confirm Swap"),
                header: SwapConfirmHeaderView(
                    fromAmount: snapshot.confirmation.selling,
                    toAmount: snapshot.confirmation.buying
                ),
                prefersNavigationTitleWithCustomHeader: false
            ),
            completion: completion
        )
    }

    private static func makeCrosschainResultReplacement(
        receipt: ActionSubmissionReceipt<SwapExecutionResult>
    ) -> Replacement? {
        guard let swap = receipt.payload?.activity?.swap else { return nil }
        let crosschainSwapVC = CrosschainToWalletVC(swap: swap, accountId: nil)
        return Replacement(viewController: crosschainSwapVC)
    }
}

extension SwapExecutionResult {
    static func matches(
        activity candidate: ApiActivity,
        receipt: ActionSubmissionReceipt<Self>
    ) -> Bool {
        receipt.correlates(with: candidate)
            || receipt.payload?.matches(activity: candidate) == true
    }

    func matches(activity candidate: ApiActivity) -> Bool {
        guard candidate.swap != nil else { return false }
        if let activity {
            return candidate.id == activity.id
        }
        if let swapId {
            return candidate.parsedTxId.hash == swapId
        }
        return false
    }
}

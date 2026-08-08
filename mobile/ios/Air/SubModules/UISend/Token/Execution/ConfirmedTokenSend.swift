import ProtectedAction
import UIComponents
import WalletContext
import WalletCore

struct ConfirmedTokenSend: Sendable {
    let account: MAccount
    let token: ApiToken
    let addressViewModel: AddressViewModel
    let submission: TokenSendSubmission
    let explainedFee: ExplainedTransferFee?
    let amountInBaseCurrency: BaseCurrencyAmount?
    let isScamRecipient: Bool
    private let flow: TokenSendFlow

    init(
        account: MAccount,
        token: ApiToken,
        addressViewModel: AddressViewModel,
        submission: TokenSendSubmission,
        explainedFee: ExplainedTransferFee?,
        amountInBaseCurrency: BaseCurrencyAmount? = nil,
        isScamRecipient: Bool = false,
        flow: TokenSendFlow
    ) {
        self.account = account
        self.token = token
        self.addressViewModel = addressViewModel
        self.submission = submission
        self.explainedFee = explainedFee
        self.amountInBaseCurrency = amountInBaseCurrency
        self.isScamRecipient = isScamRecipient
        self.flow = flow
    }

    var amount: BigInt {
        submission.amount
    }

    var protectedActionTitle: String {
        lang("Confirm Sending")
    }

    func submit(
        enclaveToken: EnclaveToken?
    ) async throws -> SendSubmissionResult {
        try await flow.submit(
            submission,
            enclaveToken: enclaveToken,
            explainedFee: explainedFee
        )
    }

    @MainActor
    func makeLedgerOperation()
        async throws -> HardwareOperation<SendSubmissionResult> {
        try await flow.ledgerOperation(
            submission,
            explainedFee: explainedFee
        )
    }

    func matchesCommittedActivity(
        _ activity: ApiActivity
    ) -> Bool {
        return Self.matchesCommittedActivity(
            activity,
            amount: amount,
            tokenSlug: token.slug,
            resolvedAddress: submission.resolvedAddress,
            fromAddress: account.getAddress(chain: token.chain),
            comment: submission.payload?.comment
        )
    }

    static func matchesCommittedActivity(
        _ activity: ApiActivity,
        amount: BigInt,
        tokenSlug: String,
        resolvedAddress: String,
        fromAddress: String?,
        comment: String?
    ) -> Bool {
        guard let transaction = activity.transaction else {
            return false
        }
        return transaction.isIncoming == false
            && transaction.slug == tokenSlug
            && transaction.amount == -amount
            && transaction.toAddress == resolvedAddress
            && transaction.fromAddress == fromAddress
            && transaction.comment == comment
    }
}

#if DEBUG
extension ConfirmedTokenSend {
    static func presentationFixture(
        account: MAccount,
        token: ApiToken,
        amount: BigInt,
        addressViewModel: AddressViewModel
    ) -> Self {
        Self(
            account: account,
            token: token,
            addressViewModel: addressViewModel,
            submission: TokenSendSubmission(
                accountId: account.id,
                asset: TokenSendAsset(token),
                amount: amount,
                payload: nil,
                stateInit: nil,
                resolvedAddress: addressViewModel.address ?? "",
                diesel: nil
            ),
            explainedFee: nil,
            flow: TokenSendFlow()
        )
    }
}
#endif

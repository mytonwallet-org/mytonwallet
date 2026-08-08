import ProtectedAction
import UIComponents
import WalletContext
import WalletCore

struct ConfirmedNftSend: Sendable {
    let account: MAccount
    let addressViewModel: AddressViewModel
    let submission: NftSendSubmission
    let explainedFee: ExplainedTransferFee?
    let isScamRecipient: Bool
    let isTransferPayloadAvailable: Bool
    private let flow: NftSendFlow

    init(
        account: MAccount,
        addressViewModel: AddressViewModel,
        submission: NftSendSubmission,
        explainedFee: ExplainedTransferFee? = nil,
        isScamRecipient: Bool = false,
        isTransferPayloadAvailable: Bool,
        flow: NftSendFlow
    ) {
        self.account = account
        self.addressViewModel = addressViewModel
        self.submission = submission
        self.explainedFee = explainedFee
        self.isScamRecipient = isScamRecipient
        self.isTransferPayloadAvailable = isTransferPayloadAvailable
        self.flow = flow
    }

    var mode: NftSendMode {
        submission.mode
    }

    var chain: ApiChain {
        submission.chain
    }

    var nfts: [ApiNft] {
        submission.nfts
    }

    var protectedActionTitle: String {
        mode == .burn
            ? lang("Confirm Burning")
            : lang("Confirm Sending")
    }

    func submit(
        enclaveToken: EnclaveToken?
    ) async throws -> SendSubmissionResult {
        try await flow.submit(
            submission,
            enclaveToken: enclaveToken
        )
    }

    @MainActor
    func makeLedgerOperation()
        async throws -> HardwareOperation<SendSubmissionResult> {
        try await flow.ledgerOperation(submission)
    }
}

#if DEBUG
extension ConfirmedNftSend {
    static func presentationFixture(
        account: MAccount,
        mode: NftSendMode,
        chain: ApiChain,
        nfts: [ApiNft],
        addressViewModel: AddressViewModel
    ) -> Self {
        Self(
            account: account,
            addressViewModel: addressViewModel,
            submission: NftSendSubmission(
                accountId: account.id,
                chain: chain,
                nfts: nfts,
                comment: nil,
                mode: mode,
                resolvedAddress: addressViewModel.address ?? "",
                totalRealFee: nil
            ),
            isTransferPayloadAvailable: false,
            flow: NftSendFlow()
        )
    }
}
#endif

import WalletContext
import WalletCore

struct DappConnectSubmitResult: Sendable, MfaProtectedActionResult {
    let mfaRequestHash: String?

    private let accountId: String
    private let proofSignatures: [String]?
    private let resolver: ConnectRequestResolver

    init(
        accountId: String,
        proofSignatures: [String]?,
        mfaRequestHash: String?,
        resolver: ConnectRequestResolver
    ) {
        self.accountId = accountId
        self.proofSignatures = proofSignatures
        self.mfaRequestHash = mfaRequestHash
        self.resolver = resolver
    }

    @MainActor
    func resolveConfirmation() async -> ActionSubmissionResult<Self> {
        switch await resolver.confirm(
            accountId: accountId,
            proofSignatures: proofSignatures
        ) {
        case .confirmed:
            return .committed(ActionSubmissionReceipt(payload: self))
        case .cancelled:
            return .notCommitted(DisplayError(text: lang("Canceled by the user")))
        case .indeterminate(let error):
            return .indeterminate(error: error, receipt: nil)
        }
    }

    func handleMfaConfirmation(accountId _: String, request _: ApiMfaRequest) async throws {
        switch await resolver.confirm(
            accountId: accountId,
            proofSignatures: proofSignatures
        ) {
        case .confirmed:
            return
        case .cancelled:
            throw DisplayError(text: lang("Canceled by the user"))
        case .indeterminate(let error):
            throw error
        }
    }
}

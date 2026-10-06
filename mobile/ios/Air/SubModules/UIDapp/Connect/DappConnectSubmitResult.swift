import WalletContext
import WalletCore

struct DappConnectSubmitResult: Sendable, MfaProtectedActionResult {
    let mfaRequestHash: String? = nil

    private let accountId: String
    private let proofSignatures: [String]?
    private let proofPublicKeys: [String]?
    private let resolver: ConnectRequestResolver

    init(
        accountId: String,
        proofSignatures: [String]?,
        proofPublicKeys: [String]? = nil,
        resolver: ConnectRequestResolver
    ) {
        self.accountId = accountId
        self.proofSignatures = proofSignatures
        self.proofPublicKeys = proofPublicKeys
        self.resolver = resolver
    }

    @MainActor
    func resolveConfirmation() async -> ActionSubmissionResult<Self> {
        switch await resolver.confirm(
            accountId: accountId,
            proofSignatures: proofSignatures,
            proofPublicKeys: proofPublicKeys
        ) {
        case .confirmed:
            return .committed(ActionSubmissionReceipt(payload: self))
        case .cancelled:
            return .notCommitted(DisplayError(text: lang("Canceled by the user")))
        case .indeterminate(let error):
            return .indeterminate(error: error, receipt: nil)
        }
    }
}

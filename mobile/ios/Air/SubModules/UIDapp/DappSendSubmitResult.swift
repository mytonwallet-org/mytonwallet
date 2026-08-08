import WalletContext
import WalletCore

private let dappSendSubmitLog = Log("DappSendSubmitResult")

struct DappSendSubmitResult: MfaProtectedActionResult {
    typealias ConfirmMfaHandoff = @Sendable (
        _ promiseId: String,
        _ mfaRequestHash: String
    ) async throws -> Void

    let mfaRequestHash: String?
    let protectedActionError: String?

    private let promiseId: String
    private let confirmMfaHandoff: ConfirmMfaHandoff

    init(
        promiseId: String,
        result: ApiSignDappTransfersResult,
        confirmMfaHandoff: @escaping ConfirmMfaHandoff = { promiseId, mfaRequestHash in
            try await Api.confirmDappRequestSendTransactionMfa(
                promiseId: promiseId,
                mfaRequestHash: mfaRequestHash
            )
        }
    ) {
        self.promiseId = promiseId
        self.mfaRequestHash = result.mfaRequestHash
        self.protectedActionError = result.error
        self.confirmMfaHandoff = confirmMfaHandoff
    }

    func handleMfaConfirmation(accountId _: String, request _: ApiMfaRequest) async throws {
        guard let mfaRequestHash else { return }
        do {
            try await confirmMfaHandoff(promiseId, mfaRequestHash)
        } catch {
            // The MFA service has already returned a confirmed transaction hash. A failed dapp
            // promise handoff is post-commit and must not make the financial action retryable.
            dappSendSubmitLog.fault(
                "Failed to hand confirmed MFA transaction back to TonConnect: \(error, .public)"
            )
        }
    }
}

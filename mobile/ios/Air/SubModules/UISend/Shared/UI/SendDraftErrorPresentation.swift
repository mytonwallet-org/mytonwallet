import WalletContext
import WalletCore

private let sendDraftLog = Log("SendDraft")

@MainActor
func presentSendDraftError(_ error: any Error) {
    sendDraftLog.error("validate error: \(error, .public)")
    AppActions.showError(error: error)
}

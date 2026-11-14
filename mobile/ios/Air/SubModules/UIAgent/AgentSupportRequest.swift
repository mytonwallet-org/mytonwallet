import UIKit
import WalletContext
import WalletCore

/// Contact Support: the chat a request goes to, and the sheet that asks before it goes
@MainActor
enum AgentSupportRequest {
    /// The server's chats a request chooses from, as many as the chat list's first page has
    static let threadPageSize = 30

    /// The chat support has that was active last: a request from the starter hints opens it rather than a new one
    static func findSupportThread(in threads: [ApiAgentV2ThreadSummary]) -> ApiAgentV2ThreadSummary? {
        threads
            .filter { AgentSupportPresentation.getState(for: $0.support).isActive }
            .max { AgentV2DateParser.date($0.lastActivityAt) < AgentV2DateParser.date($1.lastActivityAt) }
    }

    /// Asks before a chat goes to a support operator. Call runs `onConfirm` only while `canConfirm` holds, which can
    /// change while the sheet shows; Cancel sends nothing.
    static func makeConfirmation(
        hasWalletAddresses: Bool,
        canConfirm: @escaping () -> Bool,
        onConfirm: @escaping () -> Void
    ) -> UIAlertController {
        let alert = UIAlertController(
            title: lang("$agent_support_confirm_title"),
            message: lang(hasWalletAddresses ? "$agent_support_confirm_text" : "$agent_support_confirm_text_no_wallet"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        let call = UIAlertAction(title: lang("$agent_support_confirm_action"), style: .default) { _ in
            guard canConfirm() else { return }
            onConfirm()
        }
        alert.addAction(call)
        alert.preferredAction = call
        return alert
    }

    /// The Call button of a sheet `makeConfirmation` made
    static func findCallAction(in alert: UIAlertController?) -> UIAlertAction? {
        alert?.actions.first { $0.style != .cancel }
    }
}

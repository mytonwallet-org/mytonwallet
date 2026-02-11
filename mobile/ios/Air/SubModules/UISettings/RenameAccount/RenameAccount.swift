
import UIKit
import WalletCore
import WalletContext

private let log = Log("RenameAccount")

@MainActor public func makeRenameAccountAlertController(account: MAccount) -> UIAlertController {
    let alertController = UIAlertController(title: lang("Enter wallet name:"),
                                            message: nil,
                                            preferredStyle: .alert)
    alertController.addTextField()
    let textField = alertController.textFields![0]
    textField.text = account.title ?? ""
    textField.autocapitalizationType = .words
    textField.autocorrectionType = .yes
    
    let submitAction = UIAlertAction(title: lang("OK"), style: .default) { [unowned alertController] _ in
        let walletName = alertController.textFields![0].text ?? ""
        Task {
            do {
                try await AccountStore.updateAccountTitle(accountId: account.id, newTitle: walletName.nilIfEmpty)
            } catch {
                log.error("rename failed: \(error, .public)")
            }
        }
    }
    alertController.addAction(submitAction)
    alertController.preferredAction = submitAction
    
    let cancelAction = UIAlertAction(title: lang("Cancel"), style: .cancel)
    alertController.addAction(cancelAction)
    
    return alertController
}

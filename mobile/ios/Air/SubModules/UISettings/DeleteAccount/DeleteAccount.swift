
import UIKit
import WalletCore
import WalletContext
import UIComponents

private let log = Log("DeleteAccount")

@MainActor public func showDeleteAccountAlert(accountToDelete: MAccount, isCurrentAccount: Bool) {
    let removingAccountId = accountToDelete.id
    var logoutWarning = lang("$logout_warning")
    logoutWarning = logoutWarning.replacingOccurrences(of: "**", with: "")
    topViewController()?.showAlert(
        title: lang("Remove Wallet"),
        text: logoutWarning,
        button: lang("Remove"),
        buttonStyle: .destructive,
        buttonPressed: {
            Task { @MainActor in
                do {
                    if AccountStore.accountsById.count == 1 {
                        // it is the last account id, delete all data and restart app
                        try await AccountStore.resetAccounts()
                    } else {
                        let nextAccount = isCurrentAccount ? AccountStore.accountsById.keys.first(where: { $0 != removingAccountId }) : AccountStore.accountId
                        let _ = try await AccountStore.removeAccount(accountId: removingAccountId, nextAccountId: nextAccount!)
                    }
                } catch {
                    topViewController()?.showAlert(error: error)
                }
            }
        },
        secondaryButton: lang("Cancel"),
        secondaryButtonPressed: { })
}

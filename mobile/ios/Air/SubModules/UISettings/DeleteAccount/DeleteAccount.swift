
import UIKit
import WalletCore
import WalletContext
import UIComponents

private func makeDeleteAccountWarningText(account: MAccount) -> String {
    let text: String
    if account.isView {
        text = lang("$logout_current_wallet_warning")
    } else {
        text = "\(lang("$logout_current_wallet_warning")) \(lang("$secret_words_backup_reminder"))"
    }
    return text.replacingOccurrences(of: "**", with: "")
}

@MainActor public func showDeleteAccountAlert(
    accountToDelete: MAccount,
    isCurrentAccount: Bool,
    onSuccess: (() -> Void)? = nil,
    onCancel: (() -> Void)? = nil,
    onFailure: ((Error) -> Void)? = nil
) {
    let removingAccountId = accountToDelete.id
    let logoutWarning = makeDeleteAccountWarningText(account: accountToDelete)
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
                        _ = try await AccountStore.removeAccount(accountId: removingAccountId, nextAccountId: nextAccount!)
                    }
                    onSuccess?()
                } catch {
                    if let onFailure {
                        onFailure(error)
                    } else {
                        AppActions.showError(error: error)
                    }
                }
            }
        },
        secondaryButton: lang("Cancel"),
        secondaryButtonPressed: { onCancel?() })
}

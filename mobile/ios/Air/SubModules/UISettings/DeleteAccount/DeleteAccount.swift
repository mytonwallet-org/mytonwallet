
import UIKit
import WalletCore
import WalletContext
import UIComponents

private func makeDeleteAccountWarningText(account: MAccount) -> String {
    let warningKey = account.isView ? "$logout_view_mode_warning" : "$logout_warning"
    return lang(warningKey).replacingOccurrences(of: "**", with: "")
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

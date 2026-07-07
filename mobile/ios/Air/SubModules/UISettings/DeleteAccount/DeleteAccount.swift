
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

@MainActor public func showDeleteSelectedAccountsAlert(
    accountsIdsToDelete: [String],
    onWillDelete: (() -> Void)? = nil,
    onSuccess: (() -> Void)? = nil,
    onCancel: (() -> Void)? = nil,
    onFailure: ((Error) -> Void)? = nil
) {
    let activeAccountId = AccountStore.accountId
    
    // Keep only existing accounts and handle the currently active one last to avoid redundant account switches
    var nonViewCount = 0
    let accountIds = accountsIdsToDelete
        .filter {
            guard let account = AccountStore.accountsById[$0] else { return false }
            if !account.isView {
                nonViewCount += 1
            }
            return true
        }
        .sorted { $0 != activeAccountId && $1 == activeAccountId }
    
    guard !accountIds.isEmpty else { return }
    
    let title = accountIds.count > 1 ? lang("Remove Wallets") :  lang("$remove_wallets", arg1: 1)
    let logoutWarning: String
    do {
        var text = lang(accountIds.count == 1 ? "$logout_selected_wallet_warning" : "$logout_selected_wallets_warning")
        switch nonViewCount {
        case 0: break
        case 1: text = "\(text) \(lang("$secret_words_backup_reminder"))"
        default: text = "\(text) \(lang("$all_secret_words_backup_reminder"))"
        }
        logoutWarning = text.replacingOccurrences(of: "**", with: "")
    }

    topViewController()?.showAlert(
        title: title,
        text: logoutWarning,
        button: lang("Remove"),
        buttonStyle: .destructive,
        buttonPressed: {
            onWillDelete?()
            Task { @MainActor in
                do {
                    // Use the user's ordering so the fallback is the first surviving wallet, not an arbitrary one
                    let remainingIds = AccountStore.orderedAccountIds.filter { !accountIds.contains($0) }
                    // Keep the active account if it survives, otherwise switch to the first remaining one
                    let nextAccountId = activeAccountId.flatMap { remainingIds.contains($0) ? $0 : nil } ?? remainingIds.first
                    if let nextAccountId {
                        for accountId in accountIds {
                            _ = try await AccountStore.removeAccount(accountId: accountId, nextAccountId: nextAccountId)
                        }
                    } else {
                        // removing every account, delete all data and restart app
                        try await AccountStore.resetAccounts()
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

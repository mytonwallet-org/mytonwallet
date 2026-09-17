
import UIKit
import Perception
import Dependencies
import WalletContext

/// Applies the current account's accent color to the app theme whenever the current account changes
@MainActor
public final class AccountThemeObserver {

    public static let shared = AccountThemeObserver()

    private var appliedAccountId: String?

    private init() {
        apply(animated: false)
        observeCurrentAccount()
    }

    private func observeCurrentAccount() {
        withPerceptionTracking {
            _ = AccountStore.currentAccountId
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.apply(animated: true)
                self?.observeCurrentAccount()
            }
        }
    }

    private func apply(animated: Bool) {
        let accountId = AccountStore.currentAccountId
        guard appliedAccountId != accountId else { return }
        appliedAccountId = accountId
        @Dependency(\.accountSettings) var accountSettings
        let accentColorIndex = accountSettings.for(accountId: accountId).accentColorIndex
        guard getAccentColorByIndex(accentColorIndex) != AirTintColor else { return }
        let updates = {
            changeThemeColors(to: accentColorIndex)
            UIApplication.shared.sceneWindows.forEach { $0.updateTheme() }
        }
        if animated {
            UIView.animate(withDuration: 0.3, animations: updates)
        } else {
            updates()
        }
    }
}

import UIKit
import WalletContext
import WalletCore

@MainActor
enum HomeScreenQuickAction: String {
    case getSupport = "org.mytonwallet.app.getSupport"

    static func updateShortcutItems() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: Self.getSupport.rawValue,
                localizedTitle: lang("Get Support"),
                localizedSubtitle: "@\(SUPPORT_USERNAME)",
                icon: UIApplicationShortcutIcon(systemImageName: "heart"),
                userInfo: nil
            )
        ]
    }

    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard Self(rawValue: shortcutItem.type) == .getSupport else {
            return false
        }

        UIApplication.shared.open(SupportDiagnostics.supportURL)
        return true
    }
}

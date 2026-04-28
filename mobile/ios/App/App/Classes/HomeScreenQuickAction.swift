import UIKit
import WalletContext
import WalletCore

@MainActor
enum HomeScreenQuickAction {
    private static var getSupportType: String {
        "\(Bundle.main.bundleIdentifier ?? "org.mytonwallet.app").getSupport"
    }

    static func updateShortcutItems() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: getSupportType,
                localizedTitle: lang("Get Support"),
                localizedSubtitle: "@\(SUPPORT_USERNAME)",
                icon: UIApplicationShortcutIcon(systemImageName: "heart"),
                userInfo: nil
            )
        ]
    }

    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == getSupportType else {
            return false
        }

        UIApplication.shared.open(SupportDiagnostics.supportURL)
        return true
    }
}

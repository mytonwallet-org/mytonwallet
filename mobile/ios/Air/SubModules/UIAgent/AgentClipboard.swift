import UIKit
import UIComponents
import WalletContext
import WalletCore

/// Copying from the Agent's menus. As in Telegram, the copy toast follows once the menu has closed; the tap plays the
/// haptic the wallet plays when an address is copied.
@MainActor
enum AgentClipboard {
    /// How long Telegram waits after a copy for the menu to close before its toast
    private static let toastDelay: TimeInterval = 0.2

    /// Telegram's copy toast
    static var copiedToast: ToastConfig {
        ToastConfig(style: .overlay, icon: .animatedCopy, message: lang("Message Copied"), transition: .scale)
    }

    /// Copies `text` with the wallet's copy haptic and Telegram's toast, over the screen or where `showToast` puts it
    static func copy(_ text: String, showToast: @escaping (ToastConfig) -> Void = { AppActions.showToast($0) }) {
        UIPasteboard.general.string = text
        Haptics.play(.lightTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + toastDelay) {
            showToast(copiedToast)
        }
    }
}

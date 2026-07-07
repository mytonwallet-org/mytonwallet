import UIKit
import ContextMenuKit
import WalletContext
import WalletCore

@MainActor
public enum WalletNameContextMenu {
    public static func makeConfiguration(
        accountId: @escaping () -> String,
        sourceSpacing: CGFloat = 8.0
    ) -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Rename"),
                        icon: .system("pencil.line"),
                        handler: {
                            AppActions.showRenameAccount(accountId: accountId())
                        }
                    )
                ),
                .action(
                    ContextMenuAction(
                        title: lang("Customize"),
                        icon: .system("wand.and.stars.inverse"),
                        handler: {
                            AppActions.showCustomizeWallet(accountId: accountId())
                        }
                    )
                ),
                .action(
                    ContextMenuAction(
                        title: lang("Manage Wallets"),
                        icon: .airBundle("MenuManageAssets26"),
                        handler: {
                            AppActions.showWalletSettings()
                        }
                    )
                )
            ]),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 220, sourceSpacing: sourceSpacing)
        )
    }
}

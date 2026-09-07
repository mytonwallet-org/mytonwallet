import UIKit
import SwiftUI
import UIComponents
import ContextMenuKit
import WalletCore
import WalletContext

private let switchAccountAccountRowVerticalMargin: CGFloat = 10
private let switchAccountAccountRowContentHeight: CGFloat = 40
private let switchAccountAccountRowHeight: CGFloat = switchAccountAccountRowContentHeight + switchAccountAccountRowVerticalMargin * 2
private let switchAccountAccountRowHorizontalPadding: CGFloat = 24
private let switchAccountMaxAccountsShown: Int = 9
private let switchAccountMenuWidth: CGFloat = 242
private let switchAccountSectionLabelTopPadding: CGFloat = 4
private let switchAccountSectionLabelBottomPadding: CGFloat = 10

@MainActor
public enum SwitchAccountMenu {
    public static func makeConfiguration() -> ContextMenuConfiguration {
        let activeAccount = AccountStore.account
        let otherAccounts = AccountStore.orderedAccounts.filter { $0.id != AccountStore.accountId }
        let visibleOtherAccounts = Array(otherAccounts.prefix(switchAccountMaxAccountsShown))

        var items: [ContextMenuItem] = [
            .action(
                ContextMenuAction(
                    title: lang("Manage Wallets"),
                    icon: .system("ellipsis"),
                    handler: {
                        AppActions.showWalletSettings()
                    }
                )
            )
        ]

        if let activeAccount {
            items.append(.separator)
            items.append(.custom(makeCurrentWalletLabelRow()))
            items.append(
                .custom(
                    makeAccountRow(account: activeAccount)
                )
            )
            if !visibleOtherAccounts.isEmpty {
                items.append(.separator)
            }
        }

        for account in visibleOtherAccounts {
            items.append(
                .custom(
                    makeAccountRow(account: account)
                )
            )
        }

        items.append(.separator)
        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Add Wallet"),
                    icon: .system("plus"),
                    handler: {
                        AppActions.showAddWallet(network: .mainnet)
                    }
                )
            )
        )

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: ContextMenuStyle(
                minWidth: switchAccountMenuWidth,
                maxWidth: switchAccountMenuWidth,
                maximumHeightRatio: 1.0,
                sourceSpacing: -32,
                animationSourceSpacing: 8,
                panelCornerRadius: 34,
                rowSideInset: 20,
                rowVerticalInset: 9.5,
                iconSideInset: 24,
                standardIconWidth: 28,
                separatorHeight: 21,
                screenInsets: .init(top: 0, left: 16, bottom: 0, right: 16)
            )
        )
    }

    private static func makeCurrentWalletLabelRow() -> ContextMenuCustomRow {
        .swiftUI(
            preferredWidth: switchAccountMenuWidth,
            sizing: .automatic(minHeight: 0),
            interaction: .contentHandlesTouches
        ) { _ in
            Text(lang("Current Wallet"))
                .textStyle(.footnoteEmphasized)
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(height: 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, switchAccountSectionLabelTopPadding)
                .padding(.bottom, switchAccountSectionLabelBottomPadding)
                .padding(.horizontal, switchAccountAccountRowHorizontalPadding)
        }
    }

    private static func makeAccountRow(account: MAccount) -> ContextMenuCustomRow {
        .swiftUI(
            preferredWidth: switchAccountMenuWidth,
            sizing: .fixed(height: switchAccountAccountRowHeight),
            interaction: .selectable(handler: {
                switchAccount(to: account)
            })
        ) { _ in
            let accountContext = AccountContext(accountId: account.id)
            AccountMenuCell(accountContext: accountContext)
                .padding(.horizontal, switchAccountAccountRowHorizontalPadding)
                .padding(.vertical, switchAccountAccountRowVerticalMargin)
        }
    }

    private static func switchAccount(to account: MAccount) {
        Task {
            do {
                _ = try await AccountStore.activateAccount(accountId: account.id)
                AppActions.showHome(popToRoot: true)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
}

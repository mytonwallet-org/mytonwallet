import UIKit
import SwiftUI
import UIComponents
import ContextMenuKit
import WalletCore
import WalletContext

private let switchAccountAccountRowVerticalMargin: CGFloat = 10
private let switchAccountAccountRowContentHeight: CGFloat = 40
private let switchAccountAccountRowHeight: CGFloat = switchAccountAccountRowContentHeight + switchAccountAccountRowVerticalMargin * 2
private let switchAccountAccountRowHorizontalPadding: CGFloat = 18
private let switchAccountMaxAccountsShown: Int = 8
private let switchAccountMenuWidth: CGFloat = 248
private let switchAccountSectionLabelTopPadding: CGFloat = 12
private let switchAccountSectionLabelBottomPadding: CGFloat = 6

@MainActor
enum SwitchAccountMenu {
    static func makeConfiguration() -> ContextMenuConfiguration {
        let activeAccount = AccountStore.account
        let otherAccounts = AccountStore.orderedAccounts.filter { $0.id != AccountStore.accountId }
        let visibleOtherAccounts = Array(otherAccounts.prefix(switchAccountMaxAccountsShown))
        let shouldShowAllWalletsRow = otherAccounts.count > visibleOtherAccounts.count

        var items: [ContextMenuItem] = [
            .action(
                ContextMenuAction(
                    title: lang("Add Wallet"),
                    icon: .airBundle("AddAccountIcon"),
                    handler: {
                        AppActions.showAddWallet(network: .mainnet, showCreateWallet: true, showSwitchToOtherVersion: true)
                    }
                )
            )
        ]

        if let activeAccount {
            items.append(.separator)
            items.append(.custom(makeCurrentWalletLabelRow()))
            items.append(
                .custom(
                    makeAccountRow(
                        account: activeAccount,
                        showCurrentAccountHighlight: false
                    )
                )
            )
            if !visibleOtherAccounts.isEmpty {
                items.append(.separator)
            }
        }

        for account in visibleOtherAccounts {
            items.append(
                .custom(
                    makeAccountRow(
                        account: account,
                        showCurrentAccountHighlight: true
                    )
                )
            )
        }

        if shouldShowAllWalletsRow {
            if !visibleOtherAccounts.isEmpty || activeAccount != nil {
                items.append(.separator)
            }
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Show All"),
                        icon: .system("ellipsis"),
                        handler: {
                            AppActions.showWalletSettings()
                        }
                    )
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: ContextMenuStyle(
                minWidth: switchAccountMenuWidth,
                maxWidth: switchAccountMenuWidth,
                maximumHeightRatio: 1.0,
                sourceSpacing: -32,
                animationSourceSpacing: 8,
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, switchAccountSectionLabelTopPadding)
                .padding(.bottom, switchAccountSectionLabelBottomPadding)
                .padding(.horizontal, switchAccountAccountRowHorizontalPadding)
        }
    }

    private static func makeAccountRow(
        account: MAccount,
        showCurrentAccountHighlight: Bool
    ) -> ContextMenuCustomRow {
        .swiftUI(
            preferredWidth: switchAccountMenuWidth,
            sizing: .fixed(height: switchAccountAccountRowHeight),
            interaction: .selectable(handler: {
                switchAccount(to: account)
            })
        ) { _ in
            let accountContext = AccountContext(accountId: account.id)
            AccountListCell(
                accountContext: accountContext,
                isReordering: false,
                showCurrentAccountHighlight: showCurrentAccountHighlight,
                showBalance: false
            )
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
                fatalError("failed to activate account: \(account.id)")
            }
        }
    }
}

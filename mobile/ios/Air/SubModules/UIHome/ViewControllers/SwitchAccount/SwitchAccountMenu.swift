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
private let switchAccountMenuBottomSpacing: CGFloat = 8
private let switchAccountSectionLabelTopPadding: CGFloat = 4
private let switchAccountSectionLabelBottomPadding: CGFloat = 10

@MainActor
public enum SwitchAccountMenu {
    public static func makeConfiguration(sourceView: UIView) -> ContextMenuConfiguration? {
        guard let window = sourceView.window else { return nil }
        var style = ContextMenuStyle(
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
        let activeAccount = AccountStore.account
        let otherAccounts = AccountStore.orderedAccounts.filter { $0.id != AccountStore.accountId }

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
        }

        let accountsInsertionIndex = items.count
        items.append(.separator)
        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Add Wallet"),
                    icon: .system("plus"),
                    handler: { [weak sourceView] in
                        AppActions.showAddWallet(network: .mainnet, sourceView: sourceView)
                    }
                )
            )
        )

        let sourceRect = sourceView.convert(sourceView.bounds, to: window)
        let safeFrame = window.bounds.inset(by: UIEdgeInsets(
            top: window.safeAreaInsets.top + style.screenInsets.top,
            left: style.screenInsets.left,
            bottom: window.safeAreaInsets.bottom + style.screenInsets.bottom,
            right: style.screenInsets.right
        ))
        let availableBelow = max(0, safeFrame.maxY - sourceRect.maxY - style.sourceSpacing)
        let availableAbove = max(0, sourceRect.minY - safeFrame.minY - style.sourceSpacing)
        let availableHeight = max(availableBelow, availableAbove)
        let fixedContentHeight = ContextMenuPage(items: items).measuredSize(
            maxWidth: min(style.maxWidth, safeFrame.width),
            style: style,
            layoutDirection: sourceView.effectiveUserInterfaceLayoutDirection
        ).height
        let reservedHeight = fixedContentHeight + (activeAccount == nil ? 0 : style.separatorHeight)
        let visibleAccountCount = min(
            switchAccountMaxAccountsShown,
            max(0, Int(floor((availableHeight - reservedHeight) / switchAccountAccountRowHeight)))
        )
        let visibleOtherAccounts = otherAccounts.prefix(visibleAccountCount)
        var accountItems = visibleOtherAccounts.map { ContextMenuItem.custom(makeAccountRow(account: $0)) }
        if activeAccount != nil, !accountItems.isEmpty {
            accountItems.insert(.separator, at: 0)
        }
        items.insert(contentsOf: accountItems, at: accountsInsertionIndex)

        let menuHeight = fixedContentHeight
            + CGFloat(visibleOtherAccounts.count) * switchAccountAccountRowHeight
            + (activeAccount != nil && !visibleOtherAccounts.isEmpty ? style.separatorHeight : 0)
        if visibleOtherAccounts.count < min(otherAccounts.count, switchAccountMaxAccountsShown),
           menuHeight <= availableBelow {
            style.sourceSpacing += max(0, availableBelow - menuHeight - switchAccountMenuBottomSpacing)
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: style
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

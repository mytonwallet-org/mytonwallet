import ContextMenuKit
import Dependencies
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let walletAssetsMenuStyle = ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)

@MainActor
func makeCollectiblesMenuConfig(
    accountSource: AccountSource,
    onReorder: @escaping () -> Void
) -> () -> ContextMenuConfiguration {
    return {
        @Dependency(\.accountStore) var accountStore

        let accountId = accountStore.resolveAccountId(source: accountSource)
        let collections = NftStore.getCollections(accountId: accountId)
        let gifts = collections.telegramGiftsCollections
        let notGifts = collections.notTelegramGiftsCollections
        let hasHidden = NftStore.getAccountHasHiddenNfts(accountId: accountId)

        var items: [ContextMenuItem] = []

        if !gifts.isEmpty {
            items.append(
                .submenu(
                    ContextMenuSubmenu(
                        title: lang("Telegram Gifts"),
                        makePage: {
                            var giftItems: [ContextMenuItem] = [
                                .back(
                                    ContextMenuBackAction(
                                        title: lang("Back"),
                                        icon: .airBundle("MenuBack")
                                    )
                                ),
                                .separator,
                                .action(
                                    ContextMenuAction(
                                        title: lang("All Telegram Gifts"),
                                        icon: .airBundle("MenuGift"),
                                        handler: {
                                            AppActions.showAssets(
                                                accountSource: accountSource,
                                                selectedTab: 1,
                                                collectionsFilter: .telegramGifts
                                            )
                                        }
                                    )
                                )
                            ]

                            giftItems.append(
                                contentsOf: gifts.map { collection in
                                    .action(
                                        ContextMenuAction(
                                            title: collection.name,
                                            handler: {
                                                AppActions.showAssets(
                                                    accountSource: accountSource,
                                                    selectedTab: 1,
                                                    collectionsFilter: .collection(collection)
                                                )
                                            }
                                        )
                                    )
                                }
                            )

                            return ContextMenuPage(items: giftItems)
                        }
                    )
                )
            )
            items.append(.separator)
        }

        if !notGifts.isEmpty {
            items.append(
                contentsOf: notGifts.map { collection in
                    .action(
                        ContextMenuAction(
                            title: collection.name,
                            handler: {
                                AppActions.showAssets(
                                    accountSource: accountSource,
                                    selectedTab: 1,
                                    collectionsFilter: .collection(collection)
                                )
                            }
                        )
                    )
                }
            )
            items.append(.separator)
        }

        if hasHidden {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Hidden NFTs"),
                        icon: .airBundle("MenuHidden26"),
                        handler: {
                            AppActions.showHiddenNfts(accountSource: accountSource)
                        }
                    )
                )
            )
            items.append(.separator)
        }

        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Reorder"),
                    icon: .airBundle("MenuReorder26"),
                    handler: onReorder
                )
            )
        )

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            style: walletAssetsMenuStyle
        )
    }
}

@MainActor
func makeNftCollectionMenuConfig(
    onReorder: @escaping () -> Void,
    onHide: (() -> Void)?
) -> () -> ContextMenuConfiguration {
    return {
        var items: [ContextMenuItem] = []

        if let onHide {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Hide tab"),
                        icon: .system("pin.slash"),
                        handler: onHide
                    )
                )
            )
        }

        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Reorder"),
                    icon: .airBundle("MenuReorder26"),
                    handler: onReorder
                )
            )
        )

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            style: walletAssetsMenuStyle
        )
    }
}

@MainActor
func makeTokensMenuConfig(onReorder: @escaping () -> Void) -> () -> ContextMenuConfiguration {
    return {
        let currentLimit = AppStorageHelper.homeWalletVisibleTokensLimit

        var items: [ContextMenuItem] = HomeWalletVisibleTokensLimit.allCases.map { limit in
            let icon: ContextMenuIcon? = currentLimit == limit ? (.system("checkmark") ?? .placeholder) : .placeholder

            return .action(
                ContextMenuAction(
                    title: limit.title,
                    icon: icon,
                    handler: {
                        AppStorageHelper.homeWalletVisibleTokensLimit = limit
                    }
                )
            )
        }

        items.append(.separator)
        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Add Token"),
                    icon: .system("plus"),
                    handler: {
                        AppActions.showAddToken()
                    }
                )
            )
        )
        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Reorder"),
                    icon: .airBundle("MenuReorder26"),
                    handler: onReorder
                )
            )
        )

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            style: walletAssetsMenuStyle
        )
    }
}

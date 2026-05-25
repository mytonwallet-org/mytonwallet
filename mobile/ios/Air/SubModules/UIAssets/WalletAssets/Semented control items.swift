import ContextMenuKit
import Dependencies
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let walletAssetsMenuStyle = ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)

extension DisplayAssetTab {
    var segmentedControlItemId: String {
        switch self {
        case .tokens:
            "tokens"
        case .nfts:
            "nfts"
        case .nftCollectionFilter(let filter):
            filter.stringValue
        }
    }

    var segmentedControlTitle: String {
        switch self {
        case .tokens:
            lang("Assets")
        case .nfts:
            lang("Collectibles")
        case .nftCollectionFilter(let filter):
            filter.displayTitle
        }
    }

    var isDeletableSegment: Bool {
        switch self {
        case .tokens, .nfts:
            false
        case .nftCollectionFilter:
            true
        }
    }

    static func fromSegmentedControlItemId(_ itemId: String, accountId: String) -> DisplayAssetTab? {
        switch itemId {
        case DisplayAssetTab.tokens.segmentedControlItemId:
            return .tokens
        case DisplayAssetTab.nfts.segmentedControlItemId:
            return .nfts
        default:
            let giftsFilter = NftCollectionFilter.telegramGifts
            if itemId == giftsFilter.stringValue {
                return .nftCollectionFilter(giftsFilter)
            }
            let collections = NftStore.getCollections(accountId: accountId).collections
            if let collection = collections.first(where: { $0.id == itemId }) {
                let filter = NftCollectionFilter.collection(collection)
                assert(filter.stringValue == itemId)
                return .nftCollectionFilter(filter)
            }
            assertionFailure("Unable to find a collection for the tab with id: \(itemId)")
            return nil
        }
    }
}

@MainActor
final class WalletAssetsTabContextMenuProviders {
    private let accountSource: AccountSource
    private let nftsVCManager: NftsVCManager
    private let sourceViewProvider: () -> UIView?
    private let onReorder: () -> Void
    private let includesTokenLimitActions: Bool
    private var contextMenuProviders: [DisplayAssetTab: SegmentedControlContextMenuProvider] = [:]

    init(
        accountSource: AccountSource,
        nftsVCManager: NftsVCManager,
        sourceViewProvider: @escaping () -> UIView?,
        onReorder: @escaping () -> Void,
        includesTokenLimitActions: Bool = true
    ) {
        self.accountSource = accountSource
        self.nftsVCManager = nftsVCManager
        self.sourceViewProvider = sourceViewProvider
        self.onReorder = onReorder
        self.includesTokenLimitActions = includesTokenLimitActions
    }

    func provider(for tab: DisplayAssetTab) -> SegmentedControlContextMenuProvider {
        if let provider = contextMenuProviders[tab] {
            return provider
        }

        let configuration: () -> ContextMenuConfiguration
        switch tab {
        case .tokens:
            configuration = makeTokensMenuConfig(
                onReorder: onReorder,
                includesTokenLimitActions: includesTokenLimitActions
            )
        case .nfts:
            configuration = makeCollectiblesMenuConfig(accountSource: accountSource, onReorder: onReorder)
        case let .nftCollectionFilter(filter):
            configuration = makeNftCollectionMenuConfig(
                onReorder: onReorder,
                onHide: { [weak nftsVCManager] in
                    Task {
                        try? await nftsVCManager?.setIsFavorited(filter: filter, isFavorited: false)
                    }
                }
            )
        }

        let provider = SegmentedControlContextMenuProvider(
            sourcePortal: ContextMenuSourcePortal(
                sourceViewProvider: sourceViewProvider,
                mask: .roundedAttachmentRect(cornerRadius: 12.0, cornerCurve: .circular),
                showsBackdropCutout: true
            ),
            configuration: configuration
        )
        contextMenuProviders[tab] = provider
        return provider
    }
}

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
                                                selectedTab: .nftCollectionFilter(.telegramGifts),
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
                                                    selectedTab: .nftCollectionFilter(.collection(collection)),
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
                                    selectedTab: .nftCollectionFilter(.collection(collection)),
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
                    title: lang("Reorder Tabs"),
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
                        title: lang("Hide Tab"),
                        icon: .system("pin.slash"),
                        handler: onHide
                    )
                )
            )
        }

        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Reorder Tabs"),
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
func makeTokensMenuConfig(
    onReorder: @escaping () -> Void,
    includesTokenLimitActions: Bool = true
) -> () -> ContextMenuConfiguration {
    return {
        var items: [ContextMenuItem] = []
        if includesTokenLimitActions {
            let currentLimit = AppStorageHelper.homeWalletVisibleTokensLimit

            items = HomeWalletVisibleTokensLimit.allCases.map { limit in
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
        }

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
                    title: lang("Manage Assets"),
                    icon: .airBundle("MenuManageAssets26"),
                    handler: {
                        AppActions.showAssetsAndActivity()
                    }
                )
            )
        )
        
        items.append(.separator)
        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Reorder Tabs"),
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


import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor func configureCollectiblesMenu(menuContext: MenuContext, onReorder: @escaping () -> ()) {
    menuContext.makeConfig = {
        var items: [MenuItem] = []
        let accountId = AccountStore.accountId ?? ""
        let collections = NftStore.getCollections(accountId: accountId)
        let gifts = collections.telegramGiftsCollections
        let notGifts = collections.notTelegramGiftsCollections
        let hasHidden = NftStore.currentAccountHasHiddenNfts
        
        if !gifts.isEmpty {
            items += .button(
                id: "0-gifts",
                title: lang("Telegram Gifts"),
                trailingIcon: .system("chevron.right"),
                action: {
                    menuContext.switchTo(submenuId: "1")
                },
                dismissOnSelect: false,
            )
            items += .wideSeparator()
        }
        
        if !notGifts.isEmpty {
            items += notGifts.enumerated().map { (idx, collection) in
                    .button(
                        id: "0-" + collection.id,
                        title: collection.name,
                        action: {
                            AppActions.showAssets(selectedTab: 1, collectionsFilter: .collection(collection))
                        },
                        reportWidth: idx < 8
                    )
            }
            items += .wideSeparator()
        }
        
        if hasHidden {
            items += .button(id: "0-hidden", title: lang("Hidden NFTs"), trailingIcon: .air("MenuHidden26")) {
                AppActions.showHiddenNfts()
            }
            items += .wideSeparator()
        }
        
        items += .button(id: "0-reorder", title: lang("Reorder"), trailingIcon: .air("MenuReorder26")) {
            onReorder()
        }
        
        return MenuConfig(menuItems: items)
    }
    menuContext.makeSubmenuConfig = {
        var items: [MenuItem] = []
        let accountId = AccountStore.accountId ?? ""
        let collections = NftStore.getCollections(accountId: accountId)
        let gifts = collections.telegramGiftsCollections
        
        items += .button(
            id: "1-back",
            title: lang("Back"),
            leadingIcon: .air("MenuBack"),
            action: {
                menuContext.switchTo(submenuId: "0")
            },
            dismissOnSelect: false,
        )
        items += .wideSeparator()
        
        items += .button(id: "1-all-gifts", title: lang("All Telegram Gifts"), trailingIcon: .air("MenuGift")) {
            AppActions.showAssets(selectedTab: 1, collectionsFilter: .telegramGifts)
        }
        
        items += gifts.map { collection in
                .button(id: "1-" + collection.id, title: collection.name) {
                    AppActions.showAssets(selectedTab: 1, collectionsFilter: .collection(collection))
                }
        }
        
        return MenuConfig(submenuId: "1", menuItems: items)
    }
}

@MainActor func configureNftCollectionMenu(menuContext: MenuContext, onReorder: @escaping () -> (), onHide: (() -> ())?) {
    menuContext.makeConfig = {
        var items: [MenuItem] = []
        items += .button(id: "0-reorder", title: lang("Reorder"), trailingIcon: .air("MenuReorder26")) {
            onReorder()
        }
        if let onHide {
            items += .button(id: "0-hide", title: lang("Hide tab"), trailingIcon: .system("pin.slash")) {
                onHide()
            }
        }
        return MenuConfig(menuItems: items)
    }
}

@MainActor func configureTokensMenu(menuContext: MenuContext, onReorder: @escaping () -> ()) {
    menuContext.makeConfig = {
        var items: [MenuItem] = []
        items += .button(id: "0-add", title: lang("Add Token"), trailingIcon: .system("plus")) {
            AppActions.showAddToken()
        }
        items += .button(id: "0-reorder", title: lang("Reorder"), trailingIcon: .air("MenuReorder26")) {
            onReorder()
        }
        return MenuConfig(menuItems: items)
    }
}

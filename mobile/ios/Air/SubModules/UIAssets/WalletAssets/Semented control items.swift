
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct AllNftsItem: View {
    
    @ObservedObject var menuContext: MenuContext
    
    @EnvironmentObject private var segmentedControl: SegmentedControlModel
    
    @Environment(\.segmentedControlItemSelectionIsClose) private var showAccessory: Bool
    @Environment(\.segmentedControlItemIsTopLayer) private var isTopLayer: Bool
    @Environment(\.segmentedControlItemDistanceToSelection) private var distance: CGFloat
    @Environment(\.segmentedControlItemIsSelected) private var isSelected: Bool
    
    var body: some View {
        let distance = clamp(distance, min: 0, max: 1)
        
        HStack(spacing: 2.666) {
            Text(lang("Collectibles"))

            Image(systemName: "ellipsis.circle.fill")
                .imageScale(.small)
                .padding(.trailing, -4)
                .scaleEffect(1 - distance)
                .opacity(isTopLayer ? 1 : 0)
                .frame(width: 12)
                .padding(.trailing, -12 * distance)
        }
        .menuSource(isTapGestureEnabled: isSelected, menuContext: menuContext)
        .task {
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
                    self.segmentedControl.startReordering()
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
        .animation(.snappy, value: showAccessory)
    }
}

struct NftCollectionItem<Content: View>: View {
    
    @ObservedObject var menuContext: MenuContext
    var hideAction: (() -> ())?
    var content: () -> Content
    
    @EnvironmentObject private var segmentedControl: SegmentedControlModel
    
    @Environment(\.segmentedControlItemSelectionIsClose) private var showAccessory: Bool
    @Environment(\.segmentedControlItemIsTopLayer) private var isTopLayer: Bool
    @Environment(\.segmentedControlItemDistanceToSelection) private var distance: CGFloat
    @Environment(\.segmentedControlItemIsSelected) private var isSelected: Bool

    init(menuContext: MenuContext, hideAction: (() -> ())?, @ViewBuilder content: @escaping () -> Content) {
        self.menuContext = menuContext
        self.hideAction = hideAction
        self.content = content
    }
    
    var body: some View {
        HStack(spacing: 2.666) {
            content()
            
            Image(systemName: "ellipsis.circle.fill")
                .imageScale(.small)
                .padding(.trailing, -4)
                .scaleEffect(1 - distance)
                .opacity(isTopLayer ? 1 : 0)
                .frame(width: 12)
                .padding(.trailing, -12 * distance)
        }
        .menuSource(isTapGestureEnabled: isSelected, menuContext: menuContext)
        .task {
            menuContext.makeConfig = {
                var items: [MenuItem] = []
                items += .button(id: "0-reorder", title: lang("Reorder"), trailingIcon: .air("MenuReorder26")) {
                    self.segmentedControl.startReordering()
                }
                
                if let hideAction {
                    items += .button(id: "0-hide", title: lang("Hide tab"), trailingIcon: .system("pin.slash")) {
                        hideAction()
                    }
                }
                return MenuConfig(menuItems: items)
            }
        }
    }
}


struct TokensItem<Content: View>: View {
    
    @ObservedObject var menuContext: MenuContext
    var content: () -> Content
    
    @EnvironmentObject private var segmentedControl: SegmentedControlModel
    @Environment(\.segmentedControlItemIsSelected) private var isSelected: Bool

    init(menuContext: MenuContext, @ViewBuilder content: @escaping () -> Content) {
        self.menuContext = menuContext
        self.content = content
    }
    
    var body: some View {
        content()
            .menuSource(isTapGestureEnabled: isSelected, menuContext: menuContext)
            .task {
                menuContext.makeConfig = {
                    var items: [MenuItem] = []
                    items += .button(id: "0-add", title: lang("Add Token"), trailingIcon: .system("plus")) {
                        AppActions.showAddToken()
                    }
                    items += .button(id: "0-reorder", title: lang("Reorder"), trailingIcon: .air("MenuReorder26")) {
                        self.segmentedControl.startReordering()
                    }
                    return MenuConfig(menuItems: items)
                }
            }
    }
}

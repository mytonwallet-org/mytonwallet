//
//  AddressActions.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext

public func makeTappableAddressMenu(accountContext: AccountContext, displayName: String?, chain: String, address: String) -> () -> MenuConfig {
    return {
        var menuItems: [MenuItem] = [
            .customView(id: "0-view-account", view: {
                AnyView(ViewAccountMenuItem(accountContext: accountContext, displayName: displayName, chain: chain, address: address))
            }, height: 60, width: 250),
            .wideSeparator(),
            .button(id: "0-copy", title: lang("Copy Address"), trailingIcon: .air("SendCopy")) {
                UIPasteboard.general.string = address
                AppActions.showToast(animationName: "Copy", message: lang("Address was copied!"))
                Haptics.play(.lightTap)
            },
        ]
        if let chain = ApiChain(rawValue: chain) {
            if let saved = accountContext.savedAddresses.get(chain: chain, address: address) {
                menuItems += .button(id: "0-unsave", title: lang("Remove from Saved"), trailingIcon: .system("star.slash")) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            accountContext.savedAddresses.delete(saved)
                        }
                    }
                }
            } else {
                menuItems += .button(id: "0-save", title: lang("Save Address"), trailingIcon: .system("star")) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        AppActions.showSaveAddressDialog(accountContext: accountContext, chain: chain, address: address)
                    }
                }
            }
        }

        menuItems += .button(id: "0-open-explorer", title: lang("Open in Explorer"), trailingIcon: .air("SendGlobe")) {
            if let chain = ApiChain(rawValue: chain) {
                let url = ExplorerHelper.addressUrl(chain: chain, address: address)
                AppActions.openInBrowser(url)
            }
        }
        return MenuConfig(menuItems: menuItems)
    }
}


struct ViewAccountMenuItem: View {
    var accountContext: AccountContext
    var displayName: String?
    var chain: String
    var address: String

    @Environment(MenuContext.self) var menuContext

    public var body: some View {
        SelectableMenuItem(id: "0-view-account", action: {
            topViewController()?.dismiss(animated: true) {
                AppActions.showTemporaryViewAccount(addressOrDomainByChain: [chain : address])
            }
        }, dismissOnSelect: true) {
            HStack(spacing: 8) {
                AccountIcon(account: account)
                
                VStack(alignment: .leading) {
                    if let name, name.count < 20 {
                        Text(name)
                            .font(.system(size: 17))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(formatStartEndAddress(address, prefix: 6, suffix: 6))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(formatStartEndAddress(address, prefix: 6, suffix: 6))
                            .font(.system(size: 17))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image.airBundle("DetailsChevronRight")
            }
            .padding(.horizontal, 4)
        }
        
        var name: String? {
            if let chain = ApiChain(rawValue: chain), let name = accountContext.getLocalName(chain: chain, address: address) {
                return name
            }
            return displayName
        }
    }
    
    var account: MAccount {
        MAccount(id: "", title: displayName, type: .view, byChain: [chain: AccountChain(address: address)], isTemporary: true)
    }
}

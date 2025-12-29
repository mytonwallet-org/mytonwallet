//
//  AddressActions.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext

public func makeTappableAddressMenu(displayName: String?, chain: String, address: String) -> () -> MenuConfig {
    return {
        MenuConfig(menuItems: [
            .customView(id: "0-view-account", view: {
                AnyView(ViewAccountMenuItem(displayName: displayName, chain: chain, address: address))
            }, height: 60, width: 250),
            .wideSeparator(),
            .button(id: "0-copy", title: lang("Copy"), trailingIcon: .air("SendCopy")) {
                UIPasteboard.general.string = address
                AppActions.showToast(animationName: "Copy", message: lang("Address was copied!"))
                Haptics.play(.lightTap)
            },
            .button(id: "0-open-explorer", title: lang("Open in Explorer"), trailingIcon: .air("SendGlobe")) {
                if let chain = ApiChain(rawValue: chain) {
                    let url = ExplorerHelper.addressUrl(chain: chain, address: address)
                    AppActions.openInBrowser(url)
                }
            },
        ])
    }
}


struct ViewAccountMenuItem: View {
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
                    if let displayName, displayName.count < 20 {
                        Text(displayName)
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
    }
    
    var account: MAccount {
        MAccount(id: "", title: displayName, type: .view, byChain: [chain: AccountChain(address: address)], isTemporary: true)
    }
}

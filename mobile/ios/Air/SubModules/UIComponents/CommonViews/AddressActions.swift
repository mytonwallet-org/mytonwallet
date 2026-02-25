//
//  AddressActions.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext

func makeTappableAddressMenu(accountContext: AccountContext, addressModel: AddressViewModel) -> () -> MenuConfig {
    let chain = addressModel.chain
    
    return {
        var menuItems: [MenuItem] = [
            .customView(id: "0-view-account", view: {
                    AnyView(ViewAccountMenuItem(addressModel: addressModel))
                }, height: 60, width: 250),
            .wideSeparator()
        ]
        
        if let address = addressModel.addressToCopy {
            menuItems += .button(id: "0-copy", title: lang("Copy Address"), trailingIcon: .air("SendCopy")) {
                UIPasteboard.general.string = address
                AppActions.showToast(animationName: "Copy", message: lang("%chain% Address Copied", arg1: chain.title))
                Haptics.play(.lightTap)
            }
        }
        
        if chain.isSupported, let saveKey = addressModel.effectiveSaveKey {
            if let saved = accountContext.savedAddresses.get(chain: chain, address: saveKey) {
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
                        AppActions.showSaveAddressDialog(accountContext: accountContext, chain: chain, address: saveKey)
                    }
                }
            }
        }
                
        if chain.isSupported, let address = addressModel.addressToCopy {
            menuItems += .button(id: "0-open-explorer", title: lang("Open in Explorer"), trailingIcon: .air("SendGlobe")) {
                let url = ExplorerHelper.addressUrl(chain: chain, address: address)
                AppActions.openInBrowser(url)
            }
        }

        return MenuConfig(menuItems: menuItems)
    }
}

private struct ViewAccountMenuItem: View {
    var addressModel: AddressViewModel

    @Environment(MenuContext.self) var menuContext

    public var body: some View {
        let address = addressModel.address ?? "?"
        let name = addressModel.name
        let chain = addressModel.chain
        let account = MAccount(id: "", title: name, type: .view, byChain: [chain: AccountChain(address: address)], isTemporary: true)
        
        SelectableMenuItem(id: "0-view-account", action: {
            topViewController()?.dismiss(animated: true) {
                AppActions.showTemporaryViewAccount(addressOrDomainByChain: [chain.rawValue: address])
            }
        }, dismissOnSelect: true) {
            HStack(spacing: 8) {
                AccountIcon(account: account)
                
                VStack(alignment: .leading) {
                    if let name {
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
    }
}

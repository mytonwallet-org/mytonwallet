//
//  AddressActions.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import ContextMenuKit
import SwiftUI
import WalletCore
import WalletContext

@MainActor func makeTappableAddressMenu(accountContext: AccountContext, addressModel: AddressViewModel) -> () -> ContextMenuConfiguration {
    let chain = addressModel.chain
    
    return {
        var items: [ContextMenuItem] = [
            .custom(
                .swiftUI(
                    preferredWidth: 250.0,
                    sizing: .fixed(height: 60.0),
                    interaction: .selectable(handler: {
                        topViewController()?.dismiss(animated: true) {
                            let address = addressModel.address ?? "?"
                            AppActions.showTemporaryViewAccount(addressOrDomainByChain: [chain.rawValue: address])
                        }
                    })
                ) { _ in
                    ViewAccountMenuRow(addressModel: addressModel)
                }
            ),
            .separator
        ]
        
        if let address = addressModel.addressToCopy {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Copy Address"),
                        icon: .airBundle("SendCopy"),
                        handler: {
                            UIPasteboard.general.string = address
                            AppActions.showToast(animationName: "Copy", message: lang("%chain% Address Copied", arg1: chain.title))
                            Haptics.play(.lightTap)
                        }
                    )
                )
            )
        }
        
        if chain.isSupported, let saveKey = addressModel.effectiveSaveKey {
            if let saved = accountContext.savedAddresses.get(chain: chain, address: saveKey) {
                items.append(
                    .action(
                        ContextMenuAction(
                            title: lang("Remove from Saved"),
                            icon: .system("star.slash"),
                            handler: {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        accountContext.savedAddresses.delete(saved)
                                    }
                                }
                            }
                        )
                    )
                )
            } else {
                items.append(
                    .action(
                        ContextMenuAction(
                            title: lang("Save Address"),
                            icon: .system("star"),
                            handler: {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    AppActions.showSaveAddressDialog(accountContext: accountContext, chain: chain, address: saveKey)
                                }
                            }
                        )
                    )
                )
            }
        }
                
        if chain.isSupported, let address = addressModel.addressToCopy {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Open in Explorer"),
                        icon: .airBundle("SendGlobe"),
                        handler: {
                            let url = ExplorerHelper.addressUrl(chain: chain, address: address)
                            AppActions.openInBrowser(url)
                        }
                    )
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            style: ContextMenuStyle(
                minWidth: 250.0,
                maxWidth: 280.0
            )
        )
    }
}

private struct ViewAccountMenuRow: View {
    var addressModel: AddressViewModel

    public var body: some View {
        let address = addressModel.address ?? "?"
        let name = addressModel.name
        let chain = addressModel.chain
        let account = MAccount(id: "", title: name, type: .view, byChain: [chain: AccountChain(address: address)], isTemporary: true)
        
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
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

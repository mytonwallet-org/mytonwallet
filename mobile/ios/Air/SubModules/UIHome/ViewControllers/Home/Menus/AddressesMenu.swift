import Foundation
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Dependencies

struct AddressesMenuContentRow: Identifiable {
    var chain: ApiChain
    var accountChain: AccountChain
    var id: String { "0-" + chain.nativeToken.slug }
}

nonisolated func makeAddressesMenuConfig(accountId: String) -> () -> MenuConfig {
    return {
        @Dependency(\.accountStore) var accountStore
        let account = accountStore.get(accountId: accountId)
        
        let rows: [AddressesMenuContentRow] = account.orderedChains
            .map { (chain, info) in
                AddressesMenuContentRow(chain: chain, accountChain: info)
            }
        var items: [MenuItem] = rows.map { row in
                .customView(
                    id: row.id,
                    view: {
                        AnyView(
                            AddressRowView(row: row)
                        )
                    },
                    height: 60
                )
        }
        items += .wideSeparator()
        items += .button(
            id: "0-share-link",
            title: lang("Share Wallet Link"),
            trailingIcon: .air("MenuShare28"),
            action: {
                MainActor.assumeIsolated {
                    UIPasteboard.general.url = account.shareLink
                    AppActions.shareUrl(account.shareLink)
                }
            },
        )
        return MenuConfig(menuItems: items)
    }
}

fileprivate struct AddressRowView: View {
    
    var row: AddressesMenuContentRow
    
    @Environment(MenuContext.self) var menuContext
    
    var body: some View {
        HStack(spacing: 10) {
            if let token = TokenStore.tokens[row.chain.nativeToken.slug] {
                WUIIconViewToken(token: token, isWalletView: false, showldShowChain: false, size: 28, chainSize: 0, chainBorderWidth: 0, chainBorderColor: .clear, chainHorizontalOffset: 0, chainVerticalOffset: 0)
                    .frame(width: 28, height: 28)
            }
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        let line1 = if let domain = row.accountChain.domain {
                            domain
                        } else {
                            formatStartEndAddress(row.accountChain.address, prefix: 6, suffix: 6)
                        }
                        Text(line1)
                            .font(.system(size: 17))
                            .lineLimit(1)
                        Image("HomeCopy", bundle: AirBundle)
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                    }
                    .frame(height: 20)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if row.accountChain.domain != nil {
                            let address = formatStartEndAddress(row.accountChain.address, prefix: 4, suffix: 4)
                            Text(address + " · ")
                                .truncationMode(.middle)
                                .onLongPressGesture(minimumDuration: 0.25) {
                                    onCopySecondary()
                                }
                        }
                        Text(row.chain.title)
//                            .fixedSize()
                    }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .frame(height: 18)
                }
                .padding(.trailing, 0)
                .padding(2)
                .contentShape(.rect)
            }
            .padding(-2)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: onOpenExplorer) {
                Image("HomeGlobe", bundle: AirBundle)
                    .foregroundStyle(Color(WTheme.tint))
                    .tint(Color(WTheme.tint))
                    .padding(10)
                    .contentShape(.circle)
            }
            .padding(-10)
            .padding(.trailing, 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    func onCopy() {
        if let domain = row.accountChain.domain {
            UIPasteboard.general.string = domain
            AppActions.showToast(animationName: "Copy", message: lang("%chain% Domain Copied", arg1: row.chain.title))
            Haptics.play(.lightTap)
            menuContext.dismiss()
        } else {
            onCopySecondary()
        }
    }
    
    func onCopySecondary() {
        UIPasteboard.general.string = row.accountChain.address
        AppActions.showToast(animationName: "Copy", message: lang("%chain% Address Copied", arg1: row.chain.title))
        Haptics.play(.lightTap)
        menuContext.dismiss()
    }
    
    func onOpenExplorer() {
        let url = ExplorerHelper.addressUrl(chain: row.chain, address: row.accountChain.address)
        AppActions.openInBrowser(url)
        menuContext.dismiss()
    }
}

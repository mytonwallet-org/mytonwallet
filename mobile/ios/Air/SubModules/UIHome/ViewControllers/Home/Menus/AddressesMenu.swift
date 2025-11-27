
import Foundation
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct AddressesMenuContentRow: Identifiable {
    var chain: ApiChain
    var address: String
    var id: String { "0-" + chain.tokenSlug }
}

func makeAddressesMenuConfig() -> MenuConfig {
    
    let rows: [AddressesMenuContentRow] = (AccountStore.account?.addressByChain ?? [:])
        .sorted(by: { $0.key < $1.key })
        .map { (chain, address) in
            AddressesMenuContentRow(chain: ApiChain(rawValue: chain)!, address: address)
        }
    let items: [MenuItem] = rows.map { row in
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
    return MenuConfig(menuItems: items)
}

fileprivate struct AddressRowView: View {
    
    var row: AddressesMenuContentRow
    
    @Environment(MenuContext.self) var menuContext
    
    var body: some View {
        HStack(spacing: 10) {
            if let token = TokenStore.tokens[row.chain.tokenSlug] {
                WUIIconViewToken(token: token, isWalletView: false, showldShowChain: false, size: 28, chainSize: 0, chainBorderWidth: 0, chainBorderColor: .clear, chainHorizontalOffset: 0, chainVerticalOffset: 0)
                    .frame(width: 28, height: 28)
            }
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(formatStartEndAddress(row.address, prefix: 6, suffix: 6))
                            .font(.system(size: 17))
                            .fixedSize()
                        Image("HomeCopy", bundle: AirBundle)
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                    }
                    Text(row.chain.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(WTheme.secondaryLabel))
                        .padding(.bottom, 1)
                }
                .padding(.trailing, 16)
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
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    func onCopy() {
        UIPasteboard.general.string = row.address
        topWViewController()?.showToast(animationName: "Copy", message: lang("Address was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        menuContext.dismiss()
    }
    
    func onOpenExplorer() {
        let url = ExplorerHelper.addressUrl(chain: row.chain, address: row.address)
        AppActions.openInBrowser(url)
        menuContext.dismiss()
    }
}

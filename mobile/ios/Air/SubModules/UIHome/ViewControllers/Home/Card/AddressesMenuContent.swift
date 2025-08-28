
import Foundation
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Popovers


struct AddressesMenuContent: View {
    
    var dismiss: () -> ()
    
    struct Row: Identifiable {
        var chain: ApiChain
        var address: String
        var id: String { chain.tokenSlug }
    }
    
    var rows: [Row] {
        return (AccountStore.account?.addressByChain ?? [:])
            .sorted(by: { $0.key < $1.key })
            .map { (chain, address) in
                Row(chain: ApiChain(rawValue: chain)!, address: address)
            }
    }
    
    var body: some View {
        Templates.DividedVStack {
            ForEach(rows) { row in
                AddressRowView(dismiss: dismiss, row: row)
            }
        }
        .clipShape(.rect(cornerRadius: 14))
    }
}


fileprivate struct AddressRowView: View {
    
    var dismiss: () -> ()
    var row: AddressesMenuContent.Row
    
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
        topWViewController()?.showToast(animationName: "Copy", message: lang("Address was copied to clipboard."))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        dismiss()
    }
    
    func onOpenExplorer() {
        let url = ExplorerHelper.addressUrl(chain: row.chain, address: row.address)
        AppActions.openInBrowser(url)
        dismiss()
    }
}

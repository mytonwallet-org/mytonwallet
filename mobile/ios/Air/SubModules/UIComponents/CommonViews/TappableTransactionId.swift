
import SwiftUI
import WalletCore
import WalletContext

public struct TappableTransactionId: View {
    
    var chain: ApiChain
    var txId: String
    
    @State private var menuContext = MenuContext()
    @State private var hover = false
    
    public init(chain: ApiChain, txId: String) {
        self.chain = chain
        self.txId = txId
    }
    
    public var body: some View {
        
        let tx: Text = Text(
            formatStartEndAddress(txId)
        )
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            tx
            Image.airBundle("ArrowUpDownSmall")
                .foregroundColor(Color(WTheme.secondaryLabel))
                .opacity(0.8)
                .offset(y: 1)
        }
        .menuSource(menuContext: menuContext)
        .foregroundStyle(Color(WTheme.primaryLabel))
        .opacity(hover ? 0.8 : 1)
        .task(id: txId) {
            menuContext.onAppear = { hover = true }
            menuContext.onDismiss = { hover = false }
            menuContext.makeConfig = {
                MenuConfig(menuItems: [
                    .button(id: "0-copy", title: lang("Copy"), trailingIcon: .air("SendCopy")) {
                        UIPasteboard.general.string = txId
                        AppActions.showToast(animationName: "Copy", message: lang("Transaction ID Copied"))
                        Haptics.play(.lightTap)
                    },
                    .button(id: "0-explorer", title: lang("Open in Explorer"), trailingIcon: .air("SendGlobe")) {
                        let url = ExplorerHelper.txUrl(chain: chain, txHash: txId)
                        AppActions.openInBrowser(url)
                    },
                ])
            }
        }
    }
}

    
public struct ChangellyTransactionId: View {
    
    var id: String
    
    @State private var menuContext = MenuContext()
    @State private var hover = false
    
    public init(id: String) {
        self.id = id
    }
    
    public var body: some View {
        
        let tx: Text = Text(
            id
        )
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            tx
            Image.airBundle("ArrowUpDownSmall")
                .foregroundColor(Color(WTheme.secondaryLabel))
                .opacity(0.8)
                .offset(y: 1)
        }
        .foregroundStyle(Color(WTheme.primaryLabel))
        .opacity(hover ? 0.8 : 1)
        .menuSource(menuContext: menuContext)
        .task {
            menuContext.onAppear = { hover = true }
            menuContext.onDismiss = { hover = false }
            menuContext.makeConfig = {
                MenuConfig(menuItems: [
                    .button(id: "0-copy", title: lang("Copy"), trailingIcon: .air("SendCopy")) {
                        UIPasteboard.general.string = id
                        AppActions.showToast(animationName: "Copy", message: lang("Transaction ID Copied"))
                        Haptics.play(.lightTap)
                    },
                    .button(id: "0-explorer", title: lang("Open in Explorer"), trailingIcon: .air("SendGlobe")) {
                        AppActions.openInBrowser(URL(string: "https://changelly.com/track/\(id)")!)
                    },
                ])
            }
        }
    }
}

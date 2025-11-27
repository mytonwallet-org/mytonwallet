
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
            formatStartEndAddress(txId, prefix: 8, suffix: 8, separator: "...")
        )
        let more: Text = Text(
            Image.airBundle("ChevronDown10")
        )

        HStack(alignment: .firstTextBaseline, spacing: 2) {
            tx
            more
        }
        .menuSource(menuContext: menuContext)
        .foregroundStyle(Color(WTheme.primaryLabel))
        .opacity(hover ? 0.8 : 1)
        .task {
            menuContext.onAppear = { hover = true }
            menuContext.onDismiss = { hover = false }
            menuContext.makeConfig = {
                MenuConfig(menuItems: [
                    .button(id: "0-copy", title: lang("Copy"), trailingIcon: .air("SendCopy")) {
                        UIPasteboard.general.string = txId
                        topWViewController()?.showToast(animationName: "Copy", message: lang("Transaction ID was copied!"))
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
        let more: Text = Text(
            Image.airBundle("ChevronDown10")
        )

        HStack(alignment: .firstTextBaseline, spacing: 2) {
            tx
            more
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
                        topWViewController()?.showToast(animationName: "Copy", message: lang("Transaction ID was copied!"))
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    },
                    .button(id: "0-explorer", title: lang("Open in Explorer"), trailingIcon: .air("SendGlobe")) {
                        AppActions.openInBrowser(URL(string: "https://changelly.com/track/\(id)")!)
                    },
                ])
            }
        }
    }
}

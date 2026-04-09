
import ContextMenuKit
import SwiftUI
import WalletCore
import WalletContext

public struct TappableTransactionId: View {
    
    var chain: ApiChain
    var txId: String
    
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
                .foregroundColor(Color.air.secondaryLabel)
                .opacity(0.8)
                .offset(y: 1)
        }
        .contextMenuSource {
            makeMenuConfiguration()
        }
        .foregroundStyle(Color.air.primaryLabel)
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Copy"),
                        icon: .airBundle("SendCopy"),
                        handler: {
                            UIPasteboard.general.string = txId
                            AppActions.showToast(animationName: "Copy", message: lang("Transaction ID Copied"))
                            Haptics.play(.lightTap)
                        }
                    )
                ),
                .action(
                    ContextMenuAction(
                        title: lang("Open in Explorer"),
                        icon: .airBundle("SendGlobe"),
                        handler: {
                            let url = ExplorerHelper.txUrl(chain: chain, txHash: txId)
                            AppActions.openInBrowser(url)
                        }
                    )
                ),
            ]),
            backdrop: .none
        )
    }
}

    
public struct ChangellyTransactionId: View {
    
    var id: String
    
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
                .foregroundColor(Color.air.secondaryLabel)
                .opacity(0.8)
                .offset(y: 1)
        }
        .foregroundStyle(Color.air.primaryLabel)
        .contextMenuSource {
            makeMenuConfiguration()
        }
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Copy"),
                        icon: .airBundle("SendCopy"),
                        handler: {
                            UIPasteboard.general.string = id
                            AppActions.showToast(animationName: "Copy", message: lang("Transaction ID Copied"))
                            Haptics.play(.lightTap)
                        }
                    )
                ),
                .action(
                    ContextMenuAction(
                        title: lang("Open in Explorer"),
                        icon: .airBundle("SendGlobe"),
                        handler: {
                            if let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                               let url = URL(string: "https://changelly.com/track/\(encodedId)") {
                                AppActions.openInBrowser(url)
                            }
                        }
                    )
                ),
            ]),
            backdrop: .none
        )
    }
}

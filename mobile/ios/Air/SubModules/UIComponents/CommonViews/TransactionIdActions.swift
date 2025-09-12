
import SwiftUI
import WalletCore
import WalletContext
import Popovers

public struct TransactionIdActions: View {
    
    var chain: ApiChain
    var txId: String
    
    public init(chain: ApiChain, txId: String) {
        self.chain = chain
        self.txId = txId
    }
    
    public var body: some View {
        Templates.DividedVStack {
            Templates.MenuButton(
                text: Text(lang("Copy")),
                image: Image("SendCopy", bundle: AirBundle),
                onCopy
            )
            Templates.MenuButton(
                text: Text(lang("Open in Explorer")),
                image: Image("SendGlobe", bundle: AirBundle),
                onOpenExplorer
            )
        }
    }
    
    func onCopy() {
        UIPasteboard.general.string = txId
        topWViewController()?.showToast(animationName: "Copy", message: lang("Transaction ID was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    func onOpenExplorer() {
        let url = ExplorerHelper.txUrl(chain: chain, txHash: txId)
        AppActions.openInBrowser(url)
    }
}


public struct ChangellyIdActions: View {
    
    var id: String
    
    public init(id: String) {
        self.id = id
    }
    
    public var body: some View {
        Templates.DividedVStack {
            Templates.MenuButton(
                text: Text(lang("Copy")),
                image: Image("SendCopy", bundle: AirBundle),
                onCopy
            )
            Templates.MenuButton(
                text: Text(lang("Open in Explorer")),
                image: Image("SendGlobe", bundle: AirBundle),
                onOpenExplorer
            )
        }
    }
    
    func onCopy() {
        UIPasteboard.general.string = id
        topWViewController()?.showToast(animationName: "Copy", message: lang("Transaction ID was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    func onOpenExplorer() {
        AppActions.openInBrowser(URL(string: "https://changelly.com/track/\(id)")!)
    }
}

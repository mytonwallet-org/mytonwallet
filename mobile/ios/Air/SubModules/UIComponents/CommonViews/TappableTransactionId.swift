
import SwiftUI
import WalletCore
import WalletContext
import Popovers

public struct TappableTransactionId: View {
    
    var chain: ApiChain
    var txId: String
    
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

        Templates.Menu {
            TransactionIdActions(chain: chain, txId: txId)
        } label: { hover in
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                tx
                more
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .opacity(hover ? 0.8 : 1)
        }
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
        let more: Text = Text(
            Image.airBundle("ChevronDown10")
        )

        Templates.Menu {
            ChangellyIdActions(id: id)
        } label: { hover in
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                tx
                more
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .opacity(hover ? 0.8 : 1)
        }
    }
}

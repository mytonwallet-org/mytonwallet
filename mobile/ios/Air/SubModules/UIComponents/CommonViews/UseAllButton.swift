
import SwiftUI
import WalletCore
import WalletContext


public struct UseAllButton: View {

    public var amount: TokenAmount
    public var onTap: () -> ()
    
    @Environment(\.isSensitiveDataHidden) private var isSensitiveDataHidden

    public init(amount: TokenAmount, onTap: @escaping () -> Void) {
        self.amount = amount
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            let label = Text(lang("$max_balance", arg1: ""))
                .foregroundColor(Color(WTheme.secondaryLabel))
            let balance = Text(amount: amount,format: .init(maxDecimals: 2, roundUp: false))
                .foregroundColor(Color(WTheme.tint))
            
            HStack(alignment: .center, spacing: 0) {
                Text("\(label)")
                
                balance
                    .sensitiveDataInPlace(cols: 10, rows: 2, cellSize: 7, theme: .adaptive, cornerRadius: 4)
            }
            .textCase(nil)
        }
        .animation(.snappy, value: isSensitiveDataHidden)
        .buttonStyle(.plain)
    }
}

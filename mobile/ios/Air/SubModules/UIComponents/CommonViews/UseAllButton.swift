
import SwiftUI
import WalletCore
import WalletContext
import Dependencies
import Perception

public struct UseAllButton: View {

    public var amount: TokenAmount
    public var onTap: () -> ()
    
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden
    
    public init(amount: TokenAmount, onTap: @escaping () -> Void) {
        self.amount = amount
        self.onTap = onTap
    }
    
    public var body: some View {
        WithPerceptionTracking {
            Button(action: onTap) {
                let label = Text(lang("$max_balance", arg1: ""))
                    .foregroundColor(Color(WTheme.secondaryLabel))
                let balance = Text(amount: amount, format: .init(preset: .defaultAdaptive, roundUp: false))
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
}

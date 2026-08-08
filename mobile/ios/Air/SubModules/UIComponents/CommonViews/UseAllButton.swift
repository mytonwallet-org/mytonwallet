
import SwiftUI
import WalletCore
import WalletContext
import Dependencies
import Perception

public struct UseAllButton: View {

    public var amount: TokenAmount
    public var textStyle: WTextStyle
    public var textScaling: WTextScaling
    public var onTap: () -> ()
    
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden
    
    public init(
        amount: TokenAmount,
        textStyle: WTextStyle = .supporting,
        textScaling: WTextScaling = .fixed,
        onTap: @escaping () -> Void
    ) {
        self.amount = amount
        self.textStyle = textStyle
        self.textScaling = textScaling
        self.onTap = onTap
    }
    
    public var body: some View {
        WithPerceptionTracking {
            Button(action: onTap) {
                let label = Text(lang("$max_balance", arg1: ""))
                    .textStyle(textStyle, scaling: textScaling)
                    .foregroundColor(.air.secondaryLabel)
                let balance = Text(amount: amount, format: .init(preset: .defaultAdaptive, roundHalfUp: false))
                    .textStyle(
                        textStyle,
                        content: .technical,
                        scaling: textScaling
                    )
                    .foregroundStyle(.tint)
                
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

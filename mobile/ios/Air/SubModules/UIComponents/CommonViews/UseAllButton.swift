
import SwiftUI
import WalletCore
import WalletContext
import Dependencies
import Perception

public struct UseAllButton: View {

    public var amount: TokenAmount
    public var textStyle: WTextStyle
    public var textScaling: WTextScaling
    public var isError: Bool
    public var onTap: () -> ()
    
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden
    
    public init(
        amount: TokenAmount,
        textStyle: WTextStyle = .supporting,
        textScaling: WTextScaling = .fixed,
        isError: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.amount = amount
        self.textStyle = textStyle
        self.textScaling = textScaling
        self.isError = isError
        self.onTap = onTap
    }
    
    public var body: some View {
        WithPerceptionTracking {
            Button(action: onTap) {
                let label = Text(L10n.maxBalance(balance: ""))
                    .font(Font(WTypography.uiFont(textStyle, scaling: textScaling)))
                    .foregroundColor(isError ? .air.error : .air.secondaryLabel)
                let balance = Text(amount: amount, format: .init(preset: .defaultAdaptive, roundHalfUp: false))
                    .font(Font(WTypography.uiFont(
                        textStyle,
                        content: .technical,
                        scaling: textScaling
                    )))
                    .foregroundStyle(isError ? AnyShapeStyle(Color.air.error) : AnyShapeStyle(.tint))
                
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

import UIKit
import UIComponents
import WalletContext
import WalletCore

final class TokenTradeSlippageVC: TradeValueSheetVC {
    init(slippage: BigInt, onCommit: @escaping (BigInt) -> Void) {
        super.init(configuration: .init(
            title: lang("Slippage"), unit: "%", unitFont: .roundedNative(ofSize: 32, weight: .heavy),
            fractionDigits: SLIPPAGE_DECIMALS, range: BigInt(1)...MAX_SLIPPAGE_VALUE,
            description: lang("Slippage is the difference between the expected and actual trade price caused by price changes during execution."),
            inputAccessibilityLabel: lang("Slippage") + ", %", accessibilityPrefix: "tokenTrade.slippage"
        ), value: slippage, slider: TokenTradeSlippageSlider(), onCommit: onCommit)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

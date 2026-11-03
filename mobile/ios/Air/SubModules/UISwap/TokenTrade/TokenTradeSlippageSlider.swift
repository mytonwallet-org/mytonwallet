import UIKit
import UIComponents
import WalletContext

final class TokenTradeSlippageSlider: TradePresetSlider {
    init() {
        super.init(scale: TokenTradeSlippageScale.shared, value: 5) {
            formatBigIntText(BigInt(Int(($0 * 10).rounded())), tokenDecimals: SLIPPAGE_DECIMALS) + "%"
        }
        accessibilityLabel = lang("Slippage")
        accessibilityIdentifier = "tokenTrade.slippage.slider"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

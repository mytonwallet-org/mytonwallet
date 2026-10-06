import SwiftUI
import UIComponents
import WalletContext

struct SwapWarning: View {
    
    var displayImpactWarning: Double?
    
    var body: some View {
        if let impact = displayImpactWarning {
            WarningView(
                header: Self.title(impact: impact),
                text: Self.message
            )
            .contentTransition(.numericText())
        }
    }

    static func title(impact: Double) -> String {
        L10n.theExchangeRateIsBelowMarketValue(value: "\(impact.formatted(.number.precision(.fractionLength(0..<1)).locale(.forNumberFormatters)))%")
    }

    static var message: String {
        lang("We do not recommend to perform an exchange, try to specify a lower amount.")
    }
}

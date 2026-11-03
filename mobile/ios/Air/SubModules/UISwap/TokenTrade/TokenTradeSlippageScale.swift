import Foundation
import UIComponents
import WalletContext

enum TokenTradeSlippageScale {
    static let shared = TradeSliderScale(minimum: 0.1, maximum: 50,
        presets: SWAP_SLIPPAGE_PRESETS.map { $0.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS) },
        roundValue: { $0 > 5 ? $0.rounded() : ($0 * 10).rounded() / 10 },
        stepValue: { value, increasing in
            let step = value > 5 || (increasing && value == 5) ? 1.0 : 0.1
            return ((value + (increasing ? step : -step)) * 10).rounded() / 10
        })
    static let presets = shared.presets
    static let stops = shared.stops
    static let positions = shared.positions
    static func position(for value: Double) -> Double { shared.position(for: value) }
    static func value(at position: Double) -> Double { shared.value(at: position) }
    static func selection(at position: Double, trackWidth: Double, capturedPreset: Int? = nil) -> TradeSliderScale.Selection {
        shared.selection(at: position, trackWidth: trackWidth, capturedPreset: capturedPreset)
    }
}

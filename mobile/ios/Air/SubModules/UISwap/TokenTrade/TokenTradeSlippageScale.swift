import Foundation
import WalletContext

enum TokenTradeSlippageScale {
    static let presets = SWAP_SLIPPAGE_PRESETS.map { $0.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS) }
    static let stops = [0.1] + presets + [50]
    // Presets are evenly spaced; the short end segments keep Min/Max separate from their dots.
    static let positions = [0.0] + presets.indices.map { 0.06 + Double($0) * 0.88 / Double(presets.count - 1) } + [1.0]

    struct Selection {
        let value: Double
        let presetIndex: Int?
    }

    static func position(for value: Double) -> Double {
        interpolate(min(50, max(0.1, value)), from: stops, to: positions)
    }

    static func value(at position: Double) -> Double {
        interpolate(min(1, max(0, position)), from: positions, to: stops)
    }

    static func selection(at position: Double, trackWidth: Double, capturedPreset: Int? = nil) -> Selection {
        let position = min(1, max(0, position))
        let width = max(1, trackWidth)
        let nearest = presets.indices.min { abs(positions[$0 + 1] - position) < abs(positions[$1 + 1] - position) }!
        let index = capturedPreset ?? nearest
        let anchor = positions[index + 1]
        // Hysteresis prevents repeated capture/release feedback at a preset's boundary.
        let radius = min(capturedPreset == nil ? 6.0 : 10.0, min(anchor, 1 - anchor) * width * 0.45)
        if abs(anchor - position) * width <= radius {
            return Selection(value: presets[index], presetIndex: index)
        }
        if capturedPreset != nil {
            return selection(at: position, trackWidth: width)
        }
        let value = value(at: position)
        return Selection(value: value > 5 ? value.rounded() : (value * 10).rounded() / 10, presetIndex: nil)
    }

    private static func interpolate(_ value: Double, from: [Double], to: [Double]) -> Double {
        let upper = from.indices.dropFirst().first { value <= from[$0] } ?? (from.count - 1)
        let lower = upper - 1
        let progress = (value - from[lower]) / (from[upper] - from[lower])
        return to[lower] + progress * (to[upper] - to[lower])
    }
}

import Foundation

/// Piecewise scale and sticky presets shared by percentage and leverage controls.
public struct TradeSliderScale {
    public struct Selection {
        public let value: Double
        public let presetIndex: Int?
    }
    public let minimum: Double
    public let maximum: Double
    public let presets: [Double]
    public let stops: [Double]
    public let positions: [Double]
    private let roundValue: (Double) -> Double
    private let stepValue: (Double, Bool) -> Double

    public init(minimum: Double, maximum: Double, presets: [Double],
                roundValue: @escaping (Double) -> Double, stepValue: @escaping (Double, Bool) -> Double) {
        self.minimum = minimum
        self.maximum = maximum
        self.presets = Array(Set(presets.filter { $0 > minimum && $0 < maximum })).sorted()
        self.stops = [minimum] + self.presets + [maximum]
        let count = self.presets.count
        self.positions = [0] + self.presets.indices.map { count == 1 ? 0.5 : 0.06 + Double($0) * 0.88 / Double(count - 1) } + [1]
        self.roundValue = roundValue
        self.stepValue = stepValue
    }

    public func position(for value: Double) -> Double {
        interpolate(min(maximum, max(minimum, value)), from: stops, to: positions)
    }

    public func value(at position: Double) -> Double {
        interpolate(min(1, max(0, position)), from: positions, to: stops)
    }

    public func adjustedValue(_ value: Double, increasing: Bool) -> Double {
        min(maximum, max(minimum, stepValue(value, increasing)))
    }

    public func selection(at position: Double, trackWidth: Double, capturedPreset: Int? = nil) -> Selection {
        let position = min(1, max(0, position))
        let width = max(1, trackWidth)
        if let nearest = presets.indices.min(by: { abs(positions[$0 + 1] - position) < abs(positions[$1 + 1] - position) }) {
            let index = capturedPreset.flatMap { presets.indices.contains($0) ? $0 : nil } ?? nearest
            let anchor = positions[index + 1]
            // A wider release radius avoids repeated haptics at a preset's boundary.
            let radius = min(capturedPreset == nil ? 6.0 : 10.0, min(anchor, 1 - anchor) * width * 0.45)
            if abs(anchor - position) * width <= radius {
                return Selection(value: presets[index], presetIndex: index)
            }
            if capturedPreset != nil { return selection(at: position, trackWidth: width) }
        }
        return Selection(value: min(maximum, max(minimum, roundValue(value(at: position)))), presetIndex: nil)
    }

    private func interpolate(_ value: Double, from: [Double], to: [Double]) -> Double {
        let upper = from.indices.dropFirst().first { value <= from[$0] } ?? (from.count - 1)
        let lower = upper - 1
        guard from[upper] != from[lower] else { return to[lower] }
        let progress = (value - from[lower]) / (from[upper] - from[lower])
        return to[lower] + progress * (to[upper] - to[lower])
    }
}

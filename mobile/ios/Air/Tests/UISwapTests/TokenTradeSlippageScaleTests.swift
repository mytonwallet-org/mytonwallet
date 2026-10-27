import Testing
@testable import UISwap

@Suite("Token trade slippage scale")
struct TokenTradeSlippageScaleTests {
    @Test(arguments: [0.1, 0.2, 0.5, 1, 3, 5, 5.5, 10, 25.7, 50])
    func `manual decimal values round trip without drag rounding`(value: Double) {
        #expect(abs(TokenTradeSlippageScale.value(at: TokenTradeSlippageScale.position(for: value)) - value) < 0.000001)
    }

    @Test func `preset dots are evenly spaced and inset from the endpoints`() {
        let positions = TokenTradeSlippageScale.presets.map { TokenTradeSlippageScale.position(for: $0) }
        #expect(TokenTradeSlippageScale.presets == [0.2, 0.5, 1, 2, 5, 10])
        #expect(positions.first! > 0)
        #expect(positions.last! < 1)
        let spacing = positions[1] - positions[0]
        for (a, b) in zip(positions, positions.dropFirst()) {
            #expect(abs(b - a - spacing) < 0.000001)
        }
        #expect(TokenTradeSlippageScale.position(for: 0.1) == 0)
        #expect(TokenTradeSlippageScale.position(for: 50) == 1)
    }

    @Test func `values interpolate between adjacent anchors`() {
        for index in 0..<(TokenTradeSlippageScale.stops.count - 1) {
            let midpoint = (TokenTradeSlippageScale.positions[index] + TokenTradeSlippageScale.positions[index + 1]) / 2
            let expected = (TokenTradeSlippageScale.stops[index] + TokenTradeSlippageScale.stops[index + 1]) / 2
            #expect(abs(TokenTradeSlippageScale.value(at: midpoint) - expected) < 0.000001)
        }
    }

    @Test(arguments: [220.0, 288.0, 420.0])
    func `dragging captures each preset and releases beyond its magnetic area`(width: Double) {
        for index in TokenTradeSlippageScale.presets.indices {
            let position = TokenTradeSlippageScale.positions[index + 1]
            for offset in [-5.0, 5.0] {
                let selection = TokenTradeSlippageScale.selection(at: position + offset / width, trackWidth: width)
                #expect(selection.presetIndex == index)
                #expect(selection.value == TokenTradeSlippageScale.presets[index])
            }
            let released = TokenTradeSlippageScale.selection(at: position + 12 / width, trackWidth: width, capturedPreset: index)
            #expect(released.presetIndex != index)
        }
    }

    @Test func `captured presets tolerate movement across the entry threshold`() {
        let anchor = TokenTradeSlippageScale.position(for: 2)
        #expect(TokenTradeSlippageScale.selection(at: anchor + 8 / 288, trackWidth: 288).presetIndex == nil)
        #expect(TokenTradeSlippageScale.selection(at: anchor + 8 / 288, trackWidth: 288, capturedPreset: 3).presetIndex == 3)
        #expect(TokenTradeSlippageScale.selection(at: anchor + 11 / 288, trackWidth: 288, capturedPreset: 3).presetIndex == nil)
    }

    @Test(arguments: [220.0, 288.0, 420.0])
    func `continuous drags stay monotonic with whole percentages above five`(width: Double) {
        for forward in [true, false] {
            var previous = forward ? 0.1 : 50.0
            var captured: Int?
            for index in 0...2000 {
                let position = Double(forward ? index : 2000 - index) / 2000
                let selection = TokenTradeSlippageScale.selection(at: position, trackWidth: width, capturedPreset: captured)
                #expect(forward ? selection.value >= previous : selection.value <= previous)
                if selection.value > 5 { #expect(selection.value == selection.value.rounded()) }
                captured = selection.presetIndex
                previous = selection.value
            }
            #expect(previous == (forward ? 50 : 0.1))
        }
    }

    @Test func `out of range positions clamp to min and max`() {
        #expect(TokenTradeSlippageScale.selection(at: -1, trackWidth: 288).value == 0.1)
        #expect(TokenTradeSlippageScale.selection(at: 2, trackWidth: 288).value == 50)
    }
}

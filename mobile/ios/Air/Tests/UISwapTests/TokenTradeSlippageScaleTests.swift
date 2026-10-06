import Testing
@testable import UISwap

@Suite("Token trade slippage scale")
struct TokenTradeSlippageScaleTests {
    @Test(arguments: [0.1, 0.5, 1, 3, 5, 10, 25, 50])
    func `slider positions preserve supported values`(value: Double) {
        #expect(TokenTradeSlippageScale.value(at: TokenTradeSlippageScale.position(for: value)) == value)
    }

    @Test func `common slippage values occupy most of the track`() {
        #expect(TokenTradeSlippageScale.position(for: 5) > 0.6)
        #expect(TokenTradeSlippageScale.position(for: 5) < 0.8)
        #expect(TokenTradeSlippageScale.value(at: 0) == 0.1)
        #expect(TokenTradeSlippageScale.value(at: 1) == 50)
        let values = (0...100).map { TokenTradeSlippageScale.value(at: Double($0) / 100) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test(arguments: [240.0, 340.0, 520.0])
    func `dragging snaps near presets and releases beyond the stop`(width: Double) {
        #expect(TokenTradeSlippageScale.snappedValue(at: 7 / width, trackWidth: width) == 0.1)
        for stop in TokenTradeSlippageScale.stops.dropFirst().dropLast() {
            let position = TokenTradeSlippageScale.position(for: stop)
            for offset in [-7.0, 7.0] {
                #expect(TokenTradeSlippageScale.snappedValue(at: position + offset / width, trackWidth: width) == stop)
            }
            #expect(TokenTradeSlippageScale.snappedValue(at: position + 24 / width, trackWidth: width) > stop)
        }
        let values = (0...1000).map { TokenTradeSlippageScale.snappedValue(at: Double($0) / 1000, trackWidth: width) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.first == 0.1)
        #expect(values.last == 50)
    }
}

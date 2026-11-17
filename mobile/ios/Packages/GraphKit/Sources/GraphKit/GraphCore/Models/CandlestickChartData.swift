import Foundation

/// One OHLC period. `date` is the start of the period, in absolute time.
public struct Candlestick: Equatable {
    public let date: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(date: Date, open: Double, high: Double, low: Double, close: Double) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

/// A single series of non-overlapping candles. Missing periods remain gaps on the time axis.
public struct CandlestickChartData {
    public enum ValidationError: Error, Equatable {
        case invalidInterval
        case invalidCandle(index: Int)
        case overlappingCandles(index: Int)
    }

    public let candles: [Candlestick]
    public let interval: TimeInterval

    public init(candles: [Candlestick], interval: TimeInterval) throws {
        guard interval.isFinite, interval > 0 else { throw ValidationError.invalidInterval }
        for (index, candle) in candles.enumerated() {
            let timestamp = candle.date.timeIntervalSince1970
            guard timestamp.isFinite, (timestamp + interval).isFinite, timestamp + interval > timestamp,
                  [candle.open, candle.high, candle.low, candle.close].allSatisfy(\.isFinite),
                  candle.low <= min(candle.open, candle.close),
                  candle.high >= max(candle.open, candle.close),
                  (candle.high - candle.low).isFinite else {
                throw ValidationError.invalidCandle(index: index)
            }
            if index > 0, timestamp < candles[index - 1].date.timeIntervalSince1970 + interval {
                throw ValidationError.overlappingCandles(index: index)
            }
        }
        self.candles = candles
        self.interval = interval
    }

    var horizontalRange: ClosedRange<CGFloat> {
        guard let first = candles.first, let last = candles.last else { return 0...1 }
        return CGFloat(first.date.timeIntervalSince1970)...CGFloat(last.date.timeIntervalSince1970 + interval)
    }

    func center(at index: Int) -> CGFloat {
        CGFloat(candles[index].date.timeIntervalSince1970 + interval / 2)
    }

    func visibleIndices(in range: ClosedRange<CGFloat>) -> [Int] {
        candles.indices.filter {
            let start = CGFloat(candles[$0].date.timeIntervalSince1970)
            return start < range.upperBound && start + CGFloat(interval) > range.lowerBound
        }
    }

    func verticalRange(in range: ClosedRange<CGFloat>) -> ClosedRange<CGFloat>? {
        let visible = visibleIndices(in: range)
        guard let low = visible.map({ candles[$0].low }).min(),
              let high = visible.map({ candles[$0].high }).max() else { return nil }
        let magnitude = max(abs(low), abs(high))
        let padding = magnitude == 0 ? 0.00000001 : max((high - low) * 0.08, magnitude * 0.001)
        let lower = CGFloat(low - padding)
        let upper = CGFloat(high + padding)
        let distance = upper - lower
        guard lower.isFinite, upper.isFinite, distance.isFinite, distance > 0 else { return nil }
        return lower...upper
    }

    func closestIndex(to timestamp: CGFloat, in range: ClosedRange<CGFloat>) -> Int? {
        visibleIndices(in: range).min { abs(center(at: $0) - timestamp) < abs(center(at: $1) - timestamp) }
    }
}

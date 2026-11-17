import Testing
import UIKit
@testable import GraphKit

@Suite("Candlestick charts")
@MainActor
struct CandlestickChartTests {
    private func candle(_ time: TimeInterval = 0, open: Double = 3, high: Double = 5, low: Double = 2, close: Double = 4) -> Candlestick {
        Candlestick(date: Date(timeIntervalSince1970: time), open: open, high: high, low: low, close: close)
    }

    @Test func rejectsInvalidOHLCAndIntervals() {
        for interval in [0, -1, .infinity, .nan] as [Double] {
            #expect(throws: CandlestickChartData.ValidationError.invalidInterval) {
                try CandlestickChartData(candles: [], interval: interval)
            }
        }
        for invalid in [candle(high: 2), candle(low: 4), candle(open: .nan), candle(close: .infinity)] {
            #expect(throws: CandlestickChartData.ValidationError.invalidCandle(index: 0)) {
                try CandlestickChartData(candles: [invalid], interval: 60)
            }
        }
    }

    @Test func rejectsDuplicateReversedAndOverlappingPeriods() {
        for second in [0, -60, 30] as [Double] {
            #expect(throws: CandlestickChartData.ValidationError.overlappingCandles(index: 1)) {
                try CandlestickChartData(candles: [candle(), candle(second)], interval: 60)
            }
        }
    }

    @Test func fitsEntireWicksAndKeepsMissingPeriodsEmpty() throws {
        let data = try CandlestickChartData(candles: [candle(), candle(180, high: 500)], interval: 60)
        #expect(data.horizontalRange == 0...240)
        let firstRange = try #require(data.verticalRange(in: 0...60))
        #expect(firstRange.lowerBound < 2)
        #expect(firstRange.upperBound > 5)
        #expect(firstRange.upperBound < 10)
        #expect(data.visibleIndices(in: 60...180).isEmpty)
        #expect(data.verticalRange(in: 60...180) == nil)
        #expect(data.closestIndex(to: 100, in: 60...180) == nil)
        #expect(data.visibleIndices(in: 30...190) == [0, 1])
    }

    @Test func flatAndSingleCandleHaveNonzeroRanges() throws {
        for value in [0, 1e-11, 1e-100, 0.00000012, 3.25, -2] {
            let data = try CandlestickChartData(candles: [candle(open: value, high: value, low: value, close: value)], interval: 60)
            #expect(data.horizontalRange == 0...60)
            let range = try #require(data.verticalRange(in: data.horizontalRange))
            #expect(range.lowerBound < value)
            #expect(range.upperBound > value)
            #expect(range.distance.isFinite)
            if value != 0 {
                #expect(range.distance < abs(value) * 0.01)
            }
        }
    }

    @Test func selectionShowsOrderedOHLCAndRangeChangeDismissesIt() throws {
        let data = try CandlestickChartData(candles: [candle(), candle(60, close: 2.5)], interval: 60)
        let controller = makeController(data)
        var details: ChartDetailsViewModel?
        var isVisible = false
        controller.setDetailsViewModel = { model, _, _ in details = model }
        controller.setDetailsChartVisibleClosure = { visible, _ in isVisible = visible }
        controller.detailsValueTextProvider = { "\($0.rawValue) USD" }
        controller.chartInteractionDidBegin(point: CGPoint(x: 0.9, y: 0.5))
        let selected = try #require(details)
        #expect(selected.values.map(\.title) == ["Open", "High", "Low", "Close"])
        #expect(selected.values.map(\.value) == ["3.0 USD", "5.0 USD", "2.0 USD", "2.5 USD"])
        #expect(!selected.showArrow)
        #expect(selected.title.contains(controller.strings.formattedSingleDateTitle(data.candles[1].date, includesTime: false)))
        #expect(selected.title.contains(controller.strings.formattedAxisTime(data.candles[1].date)))
        #expect(isVisible)
        controller.updateChartRange(0...0.5, animated: false)
        #expect(!isVisible)
        controller.chartInteractionDidBegin(point: CGPoint(x: 1, y: 0.5))
        #expect(details?.values.last?.value == "4.0 USD")
    }

    @Test func keepsTinyPriceMovementVisible() throws {
        let data = try CandlestickChartData(candles: [candle(open: 1e-11, high: 2e-11, low: 1e-11, close: 2e-11)], interval: 60)
        let range = try #require(data.verticalRange(in: data.horizontalRange))
        #expect(range.distance < 2e-11)
        let controller = makeController(data)
        let renderer = try #require(controller.mainChartRenderers.compactMap { $0 as? CandlestickChartRenderer }.first)
        let top = renderer.transform(toChartCoordinateVertical: 2e-11, chartFrame: controller.chartFrame())
        let bottom = renderer.transform(toChartCoordinateVertical: 1e-11, chartFrame: controller.chartFrame())
        #expect(bottom - top > 100)
        let details = controller.chartDetailsViewModel(closestDate: data.candles[0].date, pointIndex: 0, loading: false)
        #expect(details.values[0].value != "0")
        #expect(details.values[0].value != details.values[3].value)
    }

    @Test func rejectsOverflowingPaddedRanges() throws {
        let maximum = Double.greatestFiniteMagnitude
        for values in [[maximum], [-maximum], [-maximum * 0.6, maximum * 0.6], [-maximum * 0.5, maximum * 0.5]] {
            let candles = values.enumerated().map { index, value in
                candle(Double(index) * 60, open: value, high: value, low: value, close: value)
            }
            let data = try CandlestickChartData(candles: candles, interval: 60)
            #expect(data.verticalRange(in: data.horizontalRange) == nil)
            let controller = makeController(data)
            let renderers = (controller.mainChartRenderers + controller.navigationRenderers).compactMap { $0 as? CandlestickChartRenderer }
            #expect(renderers.allSatisfy { !$0.isEnabled })
        }
    }

    @Test func boundsAxisCalculationsAtFloatingPointExtremes() throws {
        let controller = makeController(try CandlestickChartData(candles: [candle()], interval: 60))
        for height in [1, 240] as [CGFloat] {
            controller.chartFrame = { CGRect(x: 0, y: 0, width: 320, height: height) }
            let ranges: [ClosedRange<CGFloat>] = [
                0...1e307,
                0...(CGFloat.leastNonzeroMagnitude * 2),
                1e300...CGFloat(1e300).nextUp,
                1e308...CGFloat.greatestFiniteMagnitude,
                -CGFloat.infinity...CGFloat.infinity,
            ]
            for range in ranges {
                let (limits, labels) = controller.verticalLimitsLabels(verticalRange: range)
                #expect(limits.lowerBound.isFinite)
                #expect(limits.upperBound.isFinite)
                #expect(limits.distance.isFinite && limits.distance > 0)
                #expect(labels.allSatisfy { $0.value.isFinite })
            }
        }
    }

    @Test func supportsAccessibleSelectionAndRangeChanges() throws {
        let data = try CandlestickChartData(candles: [candle(), candle(180, close: 2.5), candle(240, close: 3.5)], interval: 60)
        let controller = CandlestickChartController(data: data)
        controller.detailsValueTextProvider = { "\($0.rawValue) USD" }
        let section = ChartStackSection()
        section.frame = CGRect(x: 0, y: 0, width: 352, height: 360)
        section.layoutIfNeeded()
        section.setup(controller: controller, displayRange: false, zoomToEnding: false)
        let chart = try #require(section.subviews.flatMap(\.subviews).compactMap { $0 as? ChartView }.first)
        let renderer = try #require(controller.mainChartRenderers.compactMap { $0 as? CandlestickChartRenderer }.first)
        #expect(chart.isAccessibilityElement)
        #expect(chart.accessibilityTraits.contains(.adjustable))
        #expect(chart.accessibilityLabel == "Candlestick chart")

        chart.accessibilityElementDidBecomeFocused()
        #expect(renderer.selectedIndex == 0)
        chart.accessibilityDecrement()
        #expect(renderer.selectedIndex == 0)
        chart.accessibilityIncrement()
        #expect(renderer.selectedIndex == 1)
        let details = controller.chartDetailsViewModel(closestDate: data.candles[1].date, pointIndex: 1, loading: false)
        #expect(chart.accessibilityValue == "\(details.title), Open: 3.0 USD, High: 5.0 USD, Low: 2.0 USD, Close: 2.5 USD")
        chart.accessibilityIncrement()
        chart.accessibilityIncrement()
        #expect(renderer.selectedIndex == 2)
        chart.accessibilityDecrement()
        #expect(renderer.selectedIndex == 1)

        controller.cancelChartInteraction()
        controller.chartInteractionDidBegin(point: CGPoint(x: 0.9, y: 0.5))
        #expect(chart.accessibilityValue?.contains("Close: 3.5 USD") == true)
        controller.updateChartRange(0...0.2, animated: false)
        #expect(chart.accessibilityValue?.contains("Close: 4.0 USD") == true)
        chart.accessibilityIncrement()
        #expect(renderer.selectedIndex == 0)

        controller.updateChartRange(0.2...0.6, animated: false)
        #expect(chart.accessibilityValue == "No candles in the selected range")
        chart.accessibilityIncrement()
        chart.accessibilityDecrement()
        #expect(renderer.selectedIndex == nil)

        section.setup(controller: CandlestickChartController(data: try CandlestickChartData(candles: [], interval: 60)), displayRange: false, zoomToEnding: false)
        chart.accessibilityElementDidBecomeFocused()
        chart.accessibilityIncrement()
        #expect(chart.accessibilityValue == "No candles in the selected range")
        chart.accessibilityProvider = nil
        #expect(!chart.isAccessibilityElement)
        #expect(!chart.accessibilityTraits.contains(.adjustable))
        #expect(chart.accessibilityValue == nil)
    }

    @Test func clampsRangeAndSafelyHandlesEmptySeries() throws {
        let controller = makeController(try CandlestickChartData(candles: [], interval: 60))
        controller.updateChartRange(-1...2, animated: false)
        #expect(controller.currentChartHorizontalRangeFraction == 0...1)
        var didSelect = false
        controller.setDetailsViewModel = { _, _, _ in didSelect = true }
        controller.chartInteractionDidBegin(point: CGPoint(x: 0.5, y: 0.5))
        #expect(!didSelect)
        let single = makeController(try CandlestickChartData(candles: [candle()], interval: 60))
        single.updateChartRange(1...1, animated: false)
        #expect(single.currentChartHorizontalRangeFraction == 0...1)
    }

    @Test func rendersRisingFallingWicksAndDoji() throws {
        let data = try CandlestickChartData(candles: [
            candle(open: 2, high: 9, low: 1, close: 6),
            candle(60, open: 8, high: 9, low: 2, close: 3),
            candle(120, open: 5, high: 5, low: 5, close: 5),
        ], interval: 60)
        let renderer = CandlestickChartRenderer(data: data, risingColor: .green, fallingColor: .red)
        renderer.setup(horizontalRange: 0...180, animated: false)
        renderer.setup(verticalRange: 0...10, animated: false)
        var pixels = [UInt8](repeating: 0, count: 300 * 200 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 300, height: 200, bitsPerComponent: 8,
                                    bytesPerRow: 300 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
            context.translateBy(x: 0, y: frame.height)
            context.scaleBy(x: 1, y: -1)
            renderer.render(context: context, bounds: frame, chartFrame: frame)
        }
        func channel(_ x: Int, _ y: Int, _ channel: Int) -> UInt8 { pixels[(y * 300 + x) * 4 + channel] }
        #expect(channel(50, 120, 1) > 200) // Rising body.
        #expect(channel(150, 90, 0) > 200) // Falling body.
        #expect(channel(49, 30, 3) > 0) // Upper wick, outside body.
        #expect(channel(250, 99, 3) > 0) // Zero-height candle stays visible.
        #expect(channel(75, 120, 3) == 0) // Space between candles.
    }

    private func makeController(_ data: CandlestickChartData) -> CandlestickChartController {
        let controller = CandlestickChartController(data: data)
        controller.chartFrame = { CGRect(x: 16, y: 40, width: 320, height: 240) }
        controller.cartViewBounds = { CGRect(x: 0, y: 0, width: 352, height: 315) }
        controller.initializeChart()
        return controller
    }
}

import UIKit

final class CandlestickChartRenderer: BaseChartRenderer {
    let data: CandlestickChartData
    let risingColor: UIColor
    let fallingColor: UIColor
    var selectedIndex: Int? {
        didSet { setNeedsDisplay() }
    }

    init(data: CandlestickChartData, risingColor: UIColor, fallingColor: UIColor) {
        self.data = data
        self.risingColor = risingColor
        self.fallingColor = fallingColor
        super.init()
    }

    override func render(context: CGContext, bounds: CGRect, chartFrame: CGRect) {
        guard isEnabled, chartFrame.width > 0, chartFrame.height > 0,
              horizontalRange.current.distance > 0, verticalRange.current.distance > 0 else { return }
        let width = max(1, min(18, CGFloat(data.interval) / horizontalRange.current.distance * chartFrame.width * 0.7))
        context.saveGState()
        context.clip(to: chartFrame)
        for index in data.visibleIndices(in: horizontalRange.current) {
            let candle = data.candles[index]
            let x = transform(toChartCoordinateHorizontal: data.center(at: index), chartFrame: chartFrame)
            let high = transform(toChartCoordinateVertical: CGFloat(candle.high), chartFrame: chartFrame)
            let low = transform(toChartCoordinateVertical: CGFloat(candle.low), chartFrame: chartFrame)
            let open = transform(toChartCoordinateVertical: CGFloat(candle.open), chartFrame: chartFrame)
            let close = transform(toChartCoordinateVertical: CGFloat(candle.close), chartFrame: chartFrame)
            guard [x, high, low, open, close].allSatisfy(\.isFinite) else { continue }
            let color = candle.close >= candle.open ? risingColor : fallingColor
            context.setFillColor(color.cgColor)
            context.setAlpha(chartAlphaAnimator.current * (selectedIndex == nil || selectedIndex == index ? 1 : 0.35))
            context.fill(CGRect(x: x - 0.5, y: high, width: 1, height: max(1, low - high)))
            let height = max(1, abs(open - close))
            context.fill(CGRect(x: x - width / 2, y: (open + close - height) / 2, width: width, height: height))
        }
        context.restoreGState()
    }
}

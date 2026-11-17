import UIKit

/// An OHLC chart hosted by `ChartContainerView`, with the standard range selector and details popover.
public final class CandlestickChartController: BaseLinesChartController {
    public let data: CandlestickChartData
    private let candlesRenderer: CandlestickChartRenderer
    private let previewRenderer: CandlestickChartRenderer
    private let horizontalScalesRenderer = HorizontalScalesRenderer()
    private let verticalScalesRenderer = VerticalScalesRenderer()
    private let selectionRenderer = VerticalLinesRenderer()
    private var previousStride = -1
    private let valueFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 9
        return formatter
    }()

    public init(
        data: CandlestickChartData,
        risingColor: UIColor = .systemGreen,
        fallingColor: UIColor = .systemRed
    ) {
        self.data = data
        candlesRenderer = CandlestickChartRenderer(data: data, risingColor: risingColor, fallingColor: fallingColor)
        previewRenderer = CandlestickChartRenderer(data: data, risingColor: risingColor, fallingColor: fallingColor)
        let fields: [(String, KeyPath<Candlestick, Double>)] = [
            ("Open", \.open), ("High", \.high), ("Low", \.low), ("Close", \.close),
        ]
        super.init(chartsCollection: ChartsCollection(
            axisValues: data.candles.map(\.date),
            chartValues: fields.map { name, keyPath in
                ChartsCollection.Chart(color: risingColor, name: name, values: data.candles.map { $0[keyPath: keyPath] })
            }
        ))
        isZoomable = false
        minimumSelectedChartRange = min(1, max(0.01, CGFloat(data.interval) / data.horizontalRange.distance))
    }

    public override var mainChartRenderers: [ChartViewRenderer] {
        [verticalScalesRenderer, candlesRenderer, horizontalScalesRenderer, selectionRenderer]
    }

    public override var navigationRenderers: [ChartViewRenderer] { [previewRenderer] }
    public override var drawChartVisibity: Bool { false }
    public override var currentHorizontalRange: ClosedRange<CGFloat> { candlesRenderer.horizontalRange.end }

    public override var currentChartHorizontalRangeFraction: ClosedRange<CGFloat> {
        let total = data.horizontalRange
        return ((currentHorizontalRange.lowerBound - total.lowerBound) / total.distance)...((currentHorizontalRange.upperBound - total.lowerBound) / total.distance)
    }

    public override func initializeChart() {
        previewRenderer.setup(horizontalRange: data.horizontalRange, animated: false)
        let verticalRange = data.verticalRange(in: data.horizontalRange)
        previewRenderer.isEnabled = verticalRange != nil
        previewRenderer.setup(verticalRange: verticalRange ?? 0...1, animated: false)
        updateChartRange(0...1, animated: false)
    }

    public override func updateChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool = true) {
        guard rangeFraction.lowerBound.isFinite, rangeFraction.upperBound.isFinite else { return }
        let total = data.horizontalRange
        let minimum = minimumSelectedChartRange
        let lower = min(max(0, rangeFraction.lowerBound), 1 - minimum)
        let upper = min(1, max(lower + minimum, rangeFraction.upperBound))
        let range = (total.lowerBound + total.distance * lower)...(total.lowerBound + total.distance * upper)
        cancelChartInteraction()
        initialChartRange = range
        for renderer in [candlesRenderer, horizontalScalesRenderer, verticalScalesRenderer, selectionRenderer] as [BaseChartRenderer] {
            renderer.setup(horizontalRange: range, animated: false)
        }
        if data.candles.count == 1, let candle = data.candles.first {
            let text = data.interval < .day ? strings.formattedAxisTime(candle.date) : strings.formattedAxisDate(candle.date)
            horizontalScalesRenderer.setup(labels: [LinesChartLabel(value: data.center(at: 0), text: text)], animated: animated)
        } else if let (stride, labels) = horizontalLimitsLabels(horizontalRange: range, scaleType: .day, prevoiusHorizontalStrideInterval: previousStride) {
            previousStride = stride
            horizontalScalesRenderer.setup(labels: labels, animated: animated)
        }
        let verticalRange = data.verticalRange(in: range)
        candlesRenderer.isEnabled = verticalRange != nil
        if let verticalRange {
            let (limits, labels) = verticalLimitsLabels(verticalRange: verticalRange)
            verticalScalesRenderer.setup(verticalLimitsLabels: labels, animated: animated)
            for renderer in [candlesRenderer, verticalScalesRenderer, selectionRenderer] as [BaseChartRenderer] {
                renderer.setup(verticalRange: limits, animated: animated)
            }
            verticalScalesRenderer.setVisible(true, animated: animated)
        } else {
            verticalScalesRenderer.setVisible(false, animated: animated)
        }
        setChartTitleClosure?(data.candles.isEmpty ? "" : strings.formattedRangeTitle(
            from: Date(timeIntervalSince1970: Double(range.lowerBound)),
            to: Date(timeIntervalSince1970: Double(range.upperBound))
        ), animated)
        chartRangeUpdatedClosure?(currentChartHorizontalRangeFraction, animated)
    }

    public override func chartInteractionDidBegin(point: CGPoint, manual: Bool = true) {
        let range = currentHorizontalRange
        guard point.x.isFinite, chartFrame().width > 0,
              let index = data.closestIndex(to: range.lowerBound + range.distance * point.x, in: range) else { return }
        if manual && !isChartInteracting && candlesRenderer.selectedIndex != nil {
            cancelChartInteraction()
            return
        }
        let wasSelected = isChartInteractionBegun
        let changed = candlesRenderer.selectedIndex != index
        super.chartInteractionDidBegin(point: point, manual: manual)
        candlesRenderer.selectedIndex = index
        selectionRenderer.values = [data.center(at: index)]
        setDetailsViewModel?(chartDetailsViewModel(closestDate: data.candles[index].date, pointIndex: index, loading: false), wasSelected, wasSelected && changed)
        setDetailsViewPositionClosure?((data.center(at: index) - range.lowerBound) / range.distance * chartFrame().width + chartFrame().minX)
        setDetailsChartVisibleClosure?(true, true)
    }

    override func chartDetailsViewModel(closestDate: Date, pointIndex: Int, loading: Bool) -> ChartDetailsViewModel {
        let candle = data.candles[pointIndex]
        let color = candle.close >= candle.open ? candlesRenderer.risingColor : candlesRenderer.fallingColor
        let values = actualChartsCollection.chartValues.enumerated().map { index, field in
            let value = field.values[pointIndex]
            let item = ChartDetailsItemContext(
                id: field.name.lowercased(), index: index, role: .series, prefix: nil, title: field.name,
                rawValue: value, formattedValue: valueFormatter.string(from: NSNumber(value: value)) ?? String(value),
                color: color, isVisible: true
            )
            return ChartDetailsViewModel.Value(id: item.id, prefix: nil, title: item.title,
                                               value: detailsValueTextProvider?(item) ?? item.formattedValue, color: color, visible: true)
        }
        let dateTitle = strings.formattedSingleDateTitle(closestDate, includesTime: false)
        let title = data.interval < .day ? "\(dateTitle), \(strings.formattedAxisTime(closestDate))" : dateTitle
        return ChartDetailsViewModel(
            title: title,
            showArrow: false, showPrefixes: false, isLoading: false, values: values, totalValue: nil,
            tapAction: {}, hideAction: { [weak self] in self?.cancelChartInteraction() }
        )
    }

    public override func cancelChartInteraction() {
        super.cancelChartInteraction()
        candlesRenderer.selectedIndex = nil
        selectionRenderer.values = []
        setDetailsChartVisibleClosure?(false, true)
    }

    public override func didTapZoomOut() { updateChartRange(0...1) }
    public override func didTapZoomIn(date: Date, pointIndex: Int) {}
    public override func updateChartsVisibility(visibility: [Bool], animated: Bool) {}

    override func applyHidesVerticalAxisLabels() {
        verticalScalesRenderer.drawLabels = !hidesVerticalAxisLabels
    }

    public override func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        super.apply(theme: theme, strings: strings, animated: animated)
        horizontalScalesRenderer.labelsColor = theme.chartLabelsColor
        verticalScalesRenderer.labelsColor = theme.chartLabelsColor
        verticalScalesRenderer.axisXColor = theme.chartStrongLinesColor
        verticalScalesRenderer.horizontalLinesColor = theme.chartHelperLinesColor
        selectionRenderer.linesColor = theme.chartStrongLinesColor
    }
}

extension CandlestickChartController: ChartAccessibilityProvider {
    var chartAccessibilityLabel: String { "Candlestick chart" }

    var chartAccessibilityValue: String {
        guard let index = candlesRenderer.selectedIndex ?? data.visibleIndices(in: currentHorizontalRange).first else {
            return "No candles in the selected range"
        }
        let details = chartDetailsViewModel(closestDate: data.candles[index].date, pointIndex: index, loading: false)
        return ([details.title] + details.values.map { "\($0.title): \($0.value)" }).joined(separator: ", ")
    }

    func selectAccessibilityCandle(offset: Int) {
        let range = currentHorizontalRange
        let visible = data.visibleIndices(in: range)
        guard !visible.isEmpty else { return }
        let current = candlesRenderer.selectedIndex.flatMap { visible.firstIndex(of: $0) } ?? 0
        let index = visible[min(visible.count - 1, max(0, current + offset))]
        let point = CGPoint(x: (data.center(at: index) - range.lowerBound) / range.distance, y: 0.5)
        chartInteractionDidBegin(point: point, manual: false)
        chartInteractionDidEnd()
    }
}

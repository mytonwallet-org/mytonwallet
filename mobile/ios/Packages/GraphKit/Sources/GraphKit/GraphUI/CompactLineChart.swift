import UIKit

public struct CompactLineChartPoint: Equatable, Sendable {
    public let timestamp: TimeInterval
    public let value: Double

    public init(timestamp: TimeInterval, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

public struct CompactLineChartSelection: Equatable, Sendable {
    public let point: CompactLineChartPoint
    public let index: Int

    public init(point: CompactLineChartPoint, index: Int) {
        self.point = point
        self.index = index
    }
}

public struct CompactLineChartStyle {
    public var lineColor: UIColor
    public var backgroundColor: UIColor
    public var rangeTintColor: UIColor
    public var rangeCropImage: UIImage?
    public var fillTopAlpha: CGFloat
    public var fillOpacity: CGFloat
    public var lineAlphaAfterSelection: CGFloat

    public init(
        lineColor: UIColor,
        backgroundColor: UIColor,
        rangeTintColor: UIColor,
        rangeCropImage: UIImage?,
        fillTopAlpha: CGFloat = 0.2,
        fillOpacity: CGFloat = 1,
        lineAlphaAfterSelection: CGFloat = 0.25
    ) {
        self.lineColor = lineColor
        self.backgroundColor = backgroundColor
        self.rangeTintColor = rangeTintColor
        self.rangeCropImage = rangeCropImage
        self.fillTopAlpha = fillTopAlpha
        self.fillOpacity = fillOpacity
        self.lineAlphaAfterSelection = lineAlphaAfterSelection
    }
}

public final class CompactLineChartView: UIView {
    fileprivate let chartView = ChartView()
    fileprivate var colorAppearanceDidChange: (() -> Void)?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        chartView.chartInsets = .zero
        addSubview(chartView)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.colorAppearanceDidChange?()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        chartView.frame = bounds
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard #unavailable(iOS 17.0),
              traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        colorAppearanceDidChange?()
    }

    public func snapshotFrame(padding: CGFloat = 0) -> CGRect {
        layoutIfNeeded()
        return chartView.chartFrame.insetBy(dx: -padding, dy: -padding)
    }

    public func snapshotImage(padding: CGFloat = 0) -> UIImage {
        let originalAlpha = alpha
        let originalIsHidden = isHidden
        alpha = 1
        isHidden = false
        defer {
            alpha = originalAlpha
            isHidden = originalIsHidden
        }

        layoutIfNeeded()
        chartView.setNeedsDisplay()
        chartView.layer.displayIfNeeded()

        let imageBounds = snapshotFrame(padding: padding)
        guard imageBounds.width > 0, imageBounds.height > 0 else { return UIImage() }
        return UIGraphicsImageRenderer(bounds: imageBounds).image { context in
            layer.render(in: context.cgContext)
        }
    }
}

public final class CompactLineChartRangeView: UIView {
    fileprivate let rangeView = RangeChartView()
    private let horizontalInteractionBlocker = HorizontalInteractionBlockerGestureRecognizer()

    public var horizontalInteractionBlockingGestureRecognizer: UIGestureRecognizer {
        horizontalInteractionBlocker
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(rangeView)
        horizontalInteractionBlocker.shouldBlockTouch = { [weak self] point in
            guard let self else { return false }
            return self.rangeView.isEnabled && self.bounds.contains(point)
        }
        addGestureRecognizer(horizontalInteractionBlocker)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        rangeView.frame = bounds
    }

    public func setRange(_ range: ClosedRange<CGFloat>, animated: Bool) {
        rangeView.setRange(range, animated: animated)
    }
}

private final class CompactLineSelectionRenderer: BaseChartRenderer {
    var coordinate: CGPoint? {
        didSet { setNeedsDisplay() }
    }
    var color: UIColor = .tintColor {
        didSet { setNeedsDisplay() }
    }
    var backgroundColor: UIColor = .systemBackground {
        didSet { setNeedsDisplay() }
    }

    override func render(context: CGContext, bounds: CGRect, chartFrame: CGRect) {
        guard isEnabled, let coordinate else { return }
        let chartAlpha = chartAlphaAnimator.current
        guard chartAlpha > 0 else { return }
        let point = transform(toChartCoordinate: coordinate, chartFrame: chartFrame)

        context.saveGState()
        context.setAlpha(chartAlpha)
        defer { context.restoreGState() }

        if point.x < chartFrame.maxX - 0.5 {
            context.saveGState()
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [5, 3])
            context.move(to: point)
            context.addLine(to: CGPoint(x: point.x, y: chartFrame.minY + 8))
            context.move(to: point)
            context.addLine(to: CGPoint(x: point.x, y: chartFrame.maxY - 8))
            context.replacePathWithStrokedPath()
            context.clip()

            let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(
                    gradient,
                    start: point,
                    end: CGPoint(x: point.x, y: chartFrame.minY),
                    options: []
                )
                context.drawLinearGradient(
                    gradient,
                    start: point,
                    end: CGPoint(x: point.x, y: chartFrame.maxY),
                    options: []
                )
            }
            context.restoreGState()
        }

        context.setFillColor(backgroundColor.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
    }
}

@MainActor
public final class CompactLineChart {
    public let mainView = CompactLineChartView()
    public let previewView = CompactLineChartView()
    public let rangeView = CompactLineChartRangeView()

    public var selectionDidChange: ((CompactLineChartSelection?) -> Void)?
    public var rangeDidChange: ((ClosedRange<CGFloat>) -> Void)?

    private let mainRenderer = LinesChartRenderer()
    private let previewRenderer = LinesChartRenderer()
    private let rangeRenderer = LinesChartRenderer()
    private let selectionRenderer = CompactLineSelectionRenderer()
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private var points: [CompactLineChartPoint] = []
    private var previewPoints: [CompactLineChartPoint] = []
    private var selectedRange: ClosedRange<CGFloat> = 0...1
    private var visibleIndices: ClosedRange<Int> = 0...0
    private var selectedIndex: Int?
    private var style: CompactLineChartStyle?

    public init() {
        mainRenderer.lineWidth = 2
        mainRenderer.interpolation = .cubicBezier
        mainRenderer.optimizationLevel = BaseConstants.linesChartOptimizationLevel
        previewRenderer.lineWidth = 1
        previewRenderer.interpolation = .cubicBezier
        previewRenderer.optimizationLevel = BaseConstants.previewLinesChartOptimizationLevel
        rangeRenderer.lineWidth = 1
        rangeRenderer.interpolation = .cubicBezier
        rangeRenderer.optimizationLevel = BaseConstants.previewLinesChartOptimizationLevel

        mainView.chartView.chartInsets = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 4)
        mainView.chartView.renderers = [mainRenderer, selectionRenderer]
        previewView.chartView.chartInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        previewView.chartView.renderers = [previewRenderer]
        previewView.isUserInteractionEnabled = false
        rangeView.rangeView.chartView.renderers = [rangeRenderer]
        rangeView.rangeView.chartView.chartInsets = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)
        rangeView.rangeView.minimumRangeDistance = 0.05

        mainView.colorAppearanceDidChange = { [weak self] in
            self?.refreshStyle()
        }

        mainView.chartView.minimumPressDuration = 0
        mainView.chartView.userDidSelectCoordinateClosure = { [weak self] point in
            self?.select(at: point.x)
        }
        mainView.chartView.userDidDeselectCoordinateClosure = { [weak self] in
            self?.finishSelection()
        }
        rangeView.rangeView.rangeDidChangeClosure = { [weak self] range in
            guard let self else { return }
            self.setRange(range, animated: false, updateRangeView: false)
            self.rangeDidChange?(range)
        }
    }

    public func setData(
        _ points: [CompactLineChartPoint],
        previewPoints: [CompactLineChartPoint]? = nil
    ) {
        self.points = points
            .filter { $0.timestamp.isFinite && $0.value.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        self.previewPoints = (previewPoints ?? points)
            .filter { $0.timestamp.isFinite && $0.value.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        selectedRange = 0...1
        rangeView.setRange(selectedRange, animated: false)

        let lineColor = style?.lineColor ?? .tintColor
        mainRenderer.setLines(lines: [LinesChartRenderer.LineData(
            color: lineColor,
            points: self.points.map { CGPoint(x: $0.timestamp, y: $0.value) }
        )], animated: false)
        let previewLines = [LinesChartRenderer.LineData(
            color: lineColor,
            points: self.previewPoints.map { CGPoint(x: $0.timestamp, y: $0.value) }
        )]
        previewRenderer.setLines(lines: previewLines, animated: false)
        rangeRenderer.setLines(lines: previewLines, animated: false)

        guard !self.points.isEmpty else {
            visibleIndices = 0...0
            setup(renderers: [mainRenderer, previewRenderer, rangeRenderer, selectionRenderer], horizontalRange: 0...1, verticalRange: 0...1)
            selectionRenderer.coordinate = nil
            selectedIndex = nil
            return
        }

        let totalHorizontalRange = previewHorizontalRange()
        let totalVerticalRange = previewVerticalRange()
        for renderer in [previewRenderer, rangeRenderer] {
            renderer.setup(horizontalRange: totalHorizontalRange, animated: false)
            renderer.setup(verticalRange: totalVerticalRange, animated: false)
        }
        setRange(selectedRange, animated: false, updateRangeView: false)
    }

    public func setRange(_ range: ClosedRange<CGFloat>, animated: Bool) {
        setRange(range, animated: animated, updateRangeView: true)
    }

    public func apply(style: CompactLineChartStyle) {
        self.style = style
        refreshStyle()
    }

    private func refreshStyle() {
        guard let style else { return }
        let resolvedLineColor = style.lineColor.resolvedColor(with: mainView.traitCollection)
        let resolvedBackgroundColor = style.backgroundColor.resolvedColor(with: mainView.traitCollection)
        let fillGradient = LinesChartRenderer.FillGradient(
            top: resolvedLineColor.withAlphaComponent(style.fillTopAlpha * style.fillOpacity),
            bottom: resolvedLineColor.withAlphaComponent(0),
            locationRange: 0.4...1
        )

        mainRenderer.fillGradient = fillGradient
        mainRenderer.lineAlphaAfterSelection = style.lineAlphaAfterSelection
        previewRenderer.fillGradient = fillGradient
        rangeRenderer.fillGradient = fillGradient
        selectionRenderer.color = resolvedLineColor
        selectionRenderer.backgroundColor = resolvedBackgroundColor

        if !points.isEmpty {
            let mainLines = [LinesChartRenderer.LineData(
                color: resolvedLineColor,
                points: visibleIndices.map { CGPoint(x: points[$0].timestamp, y: points[$0].value) }
            )]
            let previewLines = [LinesChartRenderer.LineData(
                color: resolvedLineColor,
                points: previewPoints.map { CGPoint(x: $0.timestamp, y: $0.value) }
            )]
            mainRenderer.setLines(lines: mainLines, animated: false)
            previewRenderer.setLines(lines: previewLines, animated: false)
            rangeRenderer.setLines(lines: previewLines, animated: false)
        }

        let rangeTheme = ChartTheme(
            chartTitleColor: resolvedLineColor,
            actionButtonColor: resolvedLineColor,
            chartBackgroundColor: resolvedBackgroundColor,
            chartLabelsColor: resolvedLineColor,
            chartHelperLinesColor: .clear,
            chartStrongLinesColor: .clear,
            barChartStrongLinesColor: .clear,
            chartDetailsTextColor: resolvedLineColor,
            chartDetailsArrowColor: resolvedLineColor,
            chartDetailsViewColor: resolvedBackgroundColor,
            rangeViewFrameColor: .clear,
            rangeViewTintColor: style.rangeTintColor,
            rangeViewMarkerColor: resolvedBackgroundColor,
            rangeCropImage: style.rangeCropImage
        )
        rangeView.rangeView.apply(theme: rangeTheme, strings: .defaultStrings, animated: false)
    }

    private func setRange(_ range: ClosedRange<CGFloat>, animated: Bool, updateRangeView: Bool) {
        selectedRange = max(0, min(range.lowerBound, 1))...max(0, min(range.upperBound, 1))
        if updateRangeView {
            rangeView.setRange(selectedRange, animated: animated)
        }
        guard !points.isEmpty else { return }

        let segmentsCount = CGFloat(points.count - 1)
        let lowerIndex = max(0, min(points.count - 1, Int(floor(selectedRange.lowerBound * segmentsCount))))
        let upperIndex = max(lowerIndex, min(points.count - 1, Int(ceil(selectedRange.upperBound * segmentsCount))))
        visibleIndices = lowerIndex...upperIndex

        let horizontalRange = horizontalRange(for: visibleIndices)
        let verticalRange = verticalRange(for: visibleIndices)
        mainRenderer.setLines(lines: [LinesChartRenderer.LineData(
            color: resolvedLineColor,
            points: visibleIndices.map { CGPoint(x: points[$0].timestamp, y: points[$0].value) }
        )], animated: false)
        setup(renderers: [mainRenderer, selectionRenderer], horizontalRange: horizontalRange, verticalRange: verticalRange, animated: animated)
        select(index: upperIndex, notifies: false)
        selectionDidChange?(nil)
    }

    private func select(at horizontalFraction: CGFloat) {
        guard !points.isEmpty else { return }
        let horizontalRange = mainRenderer.horizontalRange.current
        let targetTimestamp = horizontalRange.lowerBound + horizontalRange.distance * max(0, min(horizontalFraction, 1))
        let closestIndex = visibleIndices.min { lhs, rhs in
            abs(points[lhs].timestamp - targetTimestamp) < abs(points[rhs].timestamp - targetTimestamp)
        } ?? visibleIndices.upperBound
        select(index: closestIndex, notifies: true)
    }

    private func select(index: Int, notifies: Bool) {
        guard points.indices.contains(index) else { return }
        if notifies, selectedIndex != index {
            feedbackGenerator.selectionChanged()
        }
        selectedIndex = index
        let point = points[index]
        mainRenderer.selectedX = point.timestamp
        selectionRenderer.coordinate = CGPoint(x: point.timestamp, y: point.value)
        if notifies {
            selectionDidChange?(CompactLineChartSelection(point: point, index: index))
        }
    }

    private func finishSelection() {
        guard !points.isEmpty else { return }
        select(index: visibleIndices.upperBound, notifies: false)
        selectionDidChange?(nil)
    }

    private func horizontalRange<C: BidirectionalCollection>(for indices: C) -> ClosedRange<CGFloat> where C.Element == Int {
        horizontalRange(
            lower: indices.first.map { points[$0].timestamp },
            upper: indices.last.map { points[$0].timestamp }
        )
    }

    private func verticalRange<C: Collection>(for indices: C) -> ClosedRange<CGFloat> where C.Element == Int {
        paddedRange(values: indices.map { CGFloat(points[$0].value) })
    }

    private func previewHorizontalRange() -> ClosedRange<CGFloat> {
        horizontalRange(lower: previewPoints.first?.timestamp, upper: previewPoints.last?.timestamp)
    }

    private func previewVerticalRange() -> ClosedRange<CGFloat> {
        paddedRange(values: previewPoints.map { CGFloat($0.value) })
    }

    private func horizontalRange(lower: TimeInterval?, upper: TimeInterval?) -> ClosedRange<CGFloat> {
        guard let lower, let upper else { return 0...1 }
        let lowerValue = CGFloat(lower)
        let upperValue = CGFloat(upper)
        return lowerValue == upperValue ? lowerValue...(lowerValue + 1) : lowerValue...upperValue
    }

    private func paddedRange(values: [CGFloat]) -> ClosedRange<CGFloat> {
        guard let lower = values.min(), let upper = values.max() else { return 0...1 }
        let padding = lower == upper ? max(abs(lower) * 0.1, 1) : (upper - lower) * 0.1
        return (lower - padding)...(upper + padding)
    }

    private var resolvedLineColor: UIColor {
        (style?.lineColor ?? .tintColor).resolvedColor(with: mainView.traitCollection)
    }

    private func setup(
        renderers: [BaseChartRenderer],
        horizontalRange: ClosedRange<CGFloat>,
        verticalRange: ClosedRange<CGFloat>,
        animated: Bool = false
    ) {
        for renderer in renderers {
            renderer.setup(horizontalRange: horizontalRange, animated: animated)
            renderer.setup(verticalRange: verticalRange, animated: animated)
        }
    }
}

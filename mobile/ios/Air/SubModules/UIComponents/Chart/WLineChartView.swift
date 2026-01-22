//
//  WLineChartView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/3/24.
//

import UIKit
import WalletContext
import DGCharts

public class WLineChartView: LineChartView {
    
    private let onHighlightChange: ((_ highlight: Highlight?) -> Void)?
    public init(popupDateFormatter: ((Double) -> String)? = nil,
                popupValueFormatter: ((String) -> String)? = nil,
                onHighlightChange: ((_ highlight: Highlight?) -> Void)? = nil) {
        self.onHighlightChange = onHighlightChange
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        chartDescription.enabled = false
        xAxis.setLabelCount(4, force: false)
        xAxis.drawLabelsEnabled = false
        xAxis.labelPosition = .bottom
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = false
        leftAxis.enabled = false
        rightAxis.enabled = false
        scaleXEnabled = false
        scaleYEnabled = false
        dragYEnabled = false
        drawGridBackgroundEnabled = false
        drawBordersEnabled = false
        noDataText = ""
        doubleTapToZoomEnabled = false
        pinchZoomEnabled = false
        legend.enabled = false
        highlightPerTapEnabled = false
        marker = ChartMarker(chartView: self, popupDateFormatter: popupDateFormatter, popupValueFormatter: popupValueFormatter)
        renderer = CustomLineChartRenderer(dataProvider: self,
                                           animator: chartAnimator,
                                           viewPortHandler: viewPortHandler)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress))
        longPressGesture.minimumPressDuration = 0
        addGestureRecognizer(longPressGesture)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func onLongPress(gestureRecognizer: UILongPressGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed:
            let point = gestureRecognizer.location(in: gestureRecognizer.view)
            guard let highlight = getHighlightByTouchPoint(point) else { return }
            if highlighted.first?.x != highlight.x {
                Haptics.play(.chartSelection)
            }
            highlightValue(highlight)
            onHighlightChange?(highlight)
        case .ended, .cancelled, .failed:
            highlightLastValue()
            onHighlightChange?(nil)
        default:
            break
        }
    }
    
    func highlightLastValue() {
        guard let data = data,
              let lastDataSet = data.dataSets.first,
              let lastEntry = lastDataSet.entryForIndex(lastDataSet.entryCount - 1) else { return }
        
        let highlight = Highlight(x: lastEntry.x, y: lastEntry.y, dataSetIndex: 0)
        highlightValue(highlight)
    }

}

class ChartMarker: Marker {
    fileprivate var topLabel: String?
    fileprivate var bottomLabel: String?
    fileprivate var size = CGSize()
    fileprivate var _topLabelSize: CGSize = .zero
    fileprivate var _topDrawAttributes = [NSAttributedString.Key: Any]()
    fileprivate var _bottomLabelSize: CGSize = .zero
    fileprivate var _bottomDrawAttributes = [NSAttributedString.Key: Any]()
    
    private let chartView: LineChartView
    private let popupDateFormatter: ((Double) -> String)?
    private let popupValueFormatter: ((String) -> String)?
    init(chartView: LineChartView, popupDateFormatter: ((Double) -> String)?, popupValueFormatter: ((String) -> String)?) {
        self.chartView = chartView
        self.popupDateFormatter = popupDateFormatter
        self.popupValueFormatter = popupValueFormatter
    }
    
    var offset: CGPoint = .zero
    
    func offsetForDrawing(atPoint: CGPoint) -> CGPoint {
        .zero
    }
    func refreshContent(entry: DGCharts.ChartDataEntry, highlight: DGCharts.Highlight) {
    }

    func draw(context: CGContext, point: CGPoint) {
        UIColor.clear.setStroke()
        
        let outerView = UIBezierPath(ovalIn: CGRect(
            x: point.x - 4,
            y: point.y - 4,
            width: 8,
            height: 8))
        
        let innerView = UIBezierPath(ovalIn: CGRect(
            x: point.x - 3,
            y: point.y - 3,
            width: 6,
            height: 6))
        
        WTheme.background.setFill()
        outerView.fill()
        outerView.stroke()
        
        WTheme.tint.setFill()
        innerView.fill()
        innerView.stroke()
    }
}

class CustomLineChartRenderer: LineChartRenderer {
    
    override func drawHighlightLines(context: CGContext, point: CGPoint, set: any LineScatterCandleRadarChartDataSetProtocol) {
        if set.isVerticalHighlightIndicatorEnabled && point.x < viewPortHandler.contentRight {
            context.setLineWidth(set.highlightLineWidth)
            
            let dashPattern: [CGFloat] = [5.0, 3.0]
            context.setLineDash(phase: 0, lengths: dashPattern)
            
            let colors = [WTheme.tint.cgColor, UIColor.clear.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
            
            let topPoint = CGPoint(x: point.x, y: viewPortHandler.contentTop + 8)
            let startPoint = CGPoint(x: point.x, y: point.y)
            let bottomPoint = CGPoint(x: point.x, y: viewPortHandler.contentBottom - 8)
            
            context.saveGState()
            
            context.move(to: startPoint)
            context.addLine(to: topPoint)
            context.move(to: startPoint)
            context.addLine(to: bottomPoint)
            context.replacePathWithStrokedPath()
            context.clip()
            
            context.drawLinearGradient(gradient, start: startPoint, end: bottomPoint, options: [])
            context.drawLinearGradient(gradient, start: startPoint, end: topPoint, options: [])

            context.restoreGState()
        }
    }
    
    internal var _xBounds = XBounds() // Reusable XBounds object
    
    @objc open override func drawCubicBezier(context: CGContext, dataSet: LineChartDataSetProtocol) {
        guard let dataProvider = dataProvider as? LineChartView else { return }
        
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        
        let phaseY = animator.phaseY
        
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
        
        // Determine the highlight position
        let highlightIndex = dataProvider.highlighted.first?.x ?? -1
        
        // get the color that is specified for this position from the DataSet
        let drawingColor = dataSet.colors.first!
        
        let intensity = dataSet.cubicIntensity
        
        // the path for the cubic-spline
        let cubicPath1 = CGMutablePath()
        let cubicPath2 = CGMutablePath()
        
        let valueToPixelMatrix = trans.valueToPixelMatrix
        
        if _xBounds.range >= 1
        {
            var prevDx: CGFloat = 0.0
            var prevDy: CGFloat = 0.0
            var curDx: CGFloat = 0.0
            var curDy: CGFloat = 0.0
            
            // Take an extra point from the left, and an extra from the right.
            // That's because we need 4 points for a cubic bezier (cubic=4), otherwise we get lines moving and doing weird stuff on the edges of the chart.
            // So in the starting `prev` and `cur`, go -2, -1
            
            let firstIndex = _xBounds.min + 1
            
            var prevPrev: ChartDataEntry! = nil
            var prev: ChartDataEntry! = dataSet.entryForIndex(max(firstIndex - 2, 0))
            var cur: ChartDataEntry! = dataSet.entryForIndex(max(firstIndex - 1, 0))
            var next: ChartDataEntry! = cur
            var nextIndex: Int = -1
            
            if cur == nil { return }
            
            // let the spline start
            cubicPath1.move(to: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y * phaseY)), transform: valueToPixelMatrix)
            
            for j in _xBounds.dropFirst()  // same as firstIndex
            {
                prevPrev = prev
                prev = cur
                cur = nextIndex == j ? next : dataSet.entryForIndex(j)
                
                nextIndex = j + 1 < dataSet.entryCount ? j + 1 : j
                next = dataSet.entryForIndex(nextIndex)
                
                if next == nil { break }
                
                let isHighlighted = highlightIndex == -1 || cur.x <= highlightIndex
                if !isHighlighted && prev.x <= highlightIndex {
                    cubicPath2.move(to: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y * phaseY)), transform: valueToPixelMatrix)
                }

                prevDx = CGFloat(cur.x - prevPrev.x) * intensity
                prevDy = CGFloat(cur.y - prevPrev.y) * intensity
                curDx = CGFloat(next.x - prev.x) * intensity
                curDy = CGFloat(next.y - prev.y) * intensity
                
                let path = isHighlighted ? cubicPath1 : cubicPath2
                path.addCurve(
                    to: CGPoint(
                        x: CGFloat(cur.x),
                        y: CGFloat(cur.y) * CGFloat(phaseY)),
                    control1: CGPoint(
                        x: CGFloat(prev.x) + prevDx,
                        y: (CGFloat(prev.y) + prevDy) * CGFloat(phaseY)),
                    control2: CGPoint(
                        x: CGFloat(cur.x) - curDx,
                        y: (CGFloat(cur.y) - curDy) * CGFloat(phaseY)),
                    transform: valueToPixelMatrix)
            }
        }
        
        context.saveGState()
        defer { context.restoreGState() }
        
        if dataSet.isDrawFilledEnabled
        {
            let fillPath = cubicPath1.mutableCopy()
            drawCubicFill(context: context, dataSet: dataSet, spline: fillPath!, matrix: valueToPixelMatrix, bounds: _xBounds)
        }
        
        if dataSet.isDrawLineWithGradientEnabled
        {
            drawGradientLine(context: context, dataSet: dataSet, spline: cubicPath1, matrix: valueToPixelMatrix)
            drawGradientLine(context: context, dataSet: dataSet, spline: cubicPath2, matrix: valueToPixelMatrix)
        }
        else
        {
            drawLine(context: context, spline: cubicPath1, drawingColor: drawingColor, lineWidth: dataSet.lineWidth)
            drawLine(context: context, spline: cubicPath2, drawingColor: drawingColor.withAlphaComponent(0.25), lineWidth: dataSet.lineWidth)
        }
    }
    
    private func drawLine(
        context: CGContext,
        spline: CGMutablePath,
        drawingColor: NSUIColor,
        lineWidth: CGFloat)
    {
        context.beginPath()
        context.addPath(spline)
        context.setStrokeColor(drawingColor.cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }
    
    func drawGradientLine(context: CGContext, dataSet: LineChartDataSetProtocol, spline: CGPath, matrix: CGAffineTransform)
    {
        guard let gradientPositions = dataSet.gradientPositions else
        {
            assertionFailure("Must set `gradientPositions if `dataSet.isDrawLineWithGradientEnabled` is true")
            return
        }
        
        // `insetBy` is applied since bounding box
        // doesn't take into account line width
        // so that peaks are trimmed since
        // gradient start and gradient end calculated wrong
        let boundingBox = spline.boundingBox
            .insetBy(dx: -dataSet.lineWidth / 2, dy: -dataSet.lineWidth / 2)
        
        guard !boundingBox.isNull, !boundingBox.isInfinite, !boundingBox.isEmpty else {
            return
        }
        
        let gradientStart = CGPoint(x: 0, y: boundingBox.minY)
        let gradientEnd = CGPoint(x: 0, y: boundingBox.maxY)
        let gradientColorComponents: [CGFloat] = dataSet.colors
            .reversed()
            .reduce(into: []) { (components, color) in
                guard let (r, g, b, a) = color.nsuirgba else {
                    return
                }
                components += [r, g, b, a]
            }
        let gradientLocations: [CGFloat] = gradientPositions.reversed()
            .map { (position) in
                let location = CGPoint(x: boundingBox.minX, y: position)
                    .applying(matrix)
                let normalizedLocation = (location.y - boundingBox.minY)
                / (boundingBox.maxY - boundingBox.minY)
                return normalizedLocation.clamped(to: 0...1)
            }
        
        let baseColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorSpace: baseColorSpace,
            colorComponents: gradientColorComponents,
            locations: gradientLocations,
            count: gradientLocations.count) else {
            return
        }
        
        context.saveGState()
        defer { context.restoreGState() }
        
        context.beginPath()
        context.addPath(spline)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])
    }
    
    open override func drawCubicFill(
        context: CGContext,
        dataSet: LineChartDataSetProtocol,
        spline: CGMutablePath,
        matrix: CGAffineTransform,
        bounds: XBounds)
    {
        guard
            let dataProvider = dataProvider
        else { return }
        
        if bounds.range <= 0
        {
            return
        }

        if bounds.range <= 0 {
            return
        }
        
        let fillMin = dataSet.fillFormatter?.getFillLinePosition(dataSet: dataSet, dataProvider: dataProvider) ?? 0.0
        
        var pt1 = CGPoint(x: CGFloat((dataProvider as? LineChartView)?.highlighted.first?.x ?? dataSet.entryForIndex(bounds.min + bounds.range)?.x ?? 0.0), y: fillMin)
        var pt2 = CGPoint(x: CGFloat(dataSet.entryForIndex(bounds.min)?.x ?? 0.0), y: fillMin)
        pt1 = pt1.applying(matrix)
        pt2 = pt2.applying(matrix)
        
        spline.addLine(to: pt1)
        spline.addLine(to: pt2)
        spline.closeSubpath()
        
        if dataSet.fill != nil
        {
            drawFilledPath(context: context, path: spline, fill: dataSet.fill!, fillAlpha: dataSet.fillAlpha)
        }
        else
        {
            drawFilledPath(context: context, path: spline, fillColor: dataSet.fillColor, fillAlpha: dataSet.fillAlpha)
        }
    }
}

extension NSUIColor
{
    var nsuirgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        
        return (red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Comparable
{
    func clamped(to range: ClosedRange<Self>) -> Self
    {
        if self > range.upperBound
        {
            return range.upperBound
        }
        else if self < range.lowerBound
        {
            return range.lowerBound
        }
        else
        {
            return self
        }
    }
}

public extension WLineChartView {
    func asImage(padding: CGFloat) -> UIImage {
        let orgAlpha = alpha
        let orgIsHidden = isHidden
        alpha = 1
        isHidden = false
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(x: viewPortHandler.contentLeft - padding,
                                                              y: viewPortHandler.contentTop - padding,
                                                              width: viewPortHandler.contentWidth + padding * 2,
                                                              height: viewPortHandler.contentHeight + padding * 2))
        let img = renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
        alpha = orgAlpha
        isHidden = orgIsHidden
        return img
    }
}

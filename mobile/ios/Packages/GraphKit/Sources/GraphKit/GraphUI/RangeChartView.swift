//
//  RangeChartView.swift
//  GraphTest
//
//  Created by Andrei Salavei on 3/11/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//
import UIKit

private enum Constants {
    static let cropIndicatorLineWidth: CGFloat = 1
    static let markerSelectionRange: CGFloat = 25
    static let defaultMinimumRangeDistance: CGFloat = 0.1
    static let titntAreaWidth: CGFloat = 10
    static let horizontalContentMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 5
    static let singlePointIndicatorWidth: CGFloat = 4
    static let limitedRangeBorderWidth: CGFloat = 2
    static let limitedRangeBorderDashPattern: [NSNumber] = [4, 3]
    static let limitedRangeIconSize: CGFloat = 14
    static let limitedRangeMinimumWidthForIcon: CGFloat = 28
}

class RangeChartView: UIControl {
    private enum Marker {
        case lower
        case upper
        case center
    }
    public var lowerBound: CGFloat = 0 {
        didSet {
            setNeedsLayout()
        }
    }
    public var upperBound: CGFloat = 1 {
        didSet {
            setNeedsLayout()
        }
    }
    public var selectionColor: UIColor = .blue
    public var defaultColor: UIColor = .lightGray
    
    public var minimumRangeDistance: CGFloat = Constants.defaultMinimumRangeDistance
    
    private let lowerBoundTintView = UIView()
    private let upperBoundTintView = UIView()
    private let cropFrameView = UIImageView()
    private let limitedRangeOverlayView = UIControl()
    private let limitedRangeLockImageView = UIImageView()
    private let limitedRangeBorderLayer = CAShapeLayer()
    
    private var selectedMarker: Marker?
    private var selectedMarkerHorizontalOffset: CGFloat = 0
    private var selectedMarkerInitialLocation: CGPoint?
    private var isBoundCropHighlighted: Bool = false
    private var isRangePagingEnabled: Bool = false
    private var selectionDisplayMode: ChartRangeSelectionDisplayMode = .range
    private var selectionPointFraction: CGFloat?
    private var appliedTheme: ChartTheme?
    private var limitedRangeFraction: CGFloat?
    private var limitedRangeTapAction: (() -> Void)?
    
    private var targetTapLocation: CGPoint?
    
    private var minimumSelectableFraction: CGFloat {
        limitedRangeFraction ?? 0
    }

    public let chartView = ChartView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layoutMargins = UIEdgeInsets(top: Constants.cropIndicatorLineWidth,
                                     left: Constants.horizontalContentMargin,
                                     bottom: Constants.cropIndicatorLineWidth,
                                     right: Constants.horizontalContentMargin)
        
        self.setup()
    }
    
    func setup() {
        isMultipleTouchEnabled = false
        
        chartView.chartInsets = .zero
        chartView.backgroundColor = .clear
        
        addSubview(chartView)
        addSubview(lowerBoundTintView)
        addSubview(upperBoundTintView)
        addSubview(limitedRangeOverlayView)
        addSubview(cropFrameView)
        cropFrameView.isUserInteractionEnabled = false
        chartView.isUserInteractionEnabled = false
        lowerBoundTintView.isUserInteractionEnabled = false
        upperBoundTintView.isUserInteractionEnabled = false
        
        chartView.layer.cornerRadius = 5
        upperBoundTintView.layer.cornerRadius = 5
        lowerBoundTintView.layer.cornerRadius = 5
        
        chartView.layer.masksToBounds = true
        upperBoundTintView.layer.masksToBounds = true
        lowerBoundTintView.layer.masksToBounds = true
        lowerBoundTintView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        upperBoundTintView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

        limitedRangeOverlayView.isHidden = true
        limitedRangeOverlayView.clipsToBounds = true
        limitedRangeOverlayView.layer.cornerRadius = Constants.cornerRadius
        limitedRangeOverlayView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        limitedRangeOverlayView.addTarget(self, action: #selector(limitedRangePressed), for: .touchUpInside)
        limitedRangeOverlayView.addSubview(limitedRangeLockImageView)

        limitedRangeBorderLayer.fillColor = nil
        limitedRangeBorderLayer.lineWidth = Constants.limitedRangeBorderWidth
        limitedRangeBorderLayer.lineDashPattern = Constants.limitedRangeBorderDashPattern
        limitedRangeOverlayView.layer.addSublayer(limitedRangeBorderLayer)

        limitedRangeLockImageView.contentMode = .scaleAspectFit
        limitedRangeLockImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Constants.limitedRangeIconSize,
            weight: .medium
        )
        limitedRangeLockImageView.image = UIImage(systemName: "lock.fill")
        
        layoutViews()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.setup()
    }
    
    public var rangeDidChangeClosure: ((ClosedRange<CGFloat>) -> Void)?
    public var touchedOutsideClosure: (() -> Void)?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }    
    
    func setRangePaging(enabled: Bool, minimumSize: CGFloat) {
        isRangePagingEnabled = enabled
        minimumRangeDistance = minimumSize
    }
    
    func setRange(_ range: ClosedRange<CGFloat>, animated: Bool) {
        UIView.perform(animated: animated) {
            self.lowerBound = range.lowerBound
            self.upperBound = range.upperBound
            self.layoutIfNeeded()
        }
    }

    func applySelection(
        range: ClosedRange<CGFloat>,
        displayMode: ChartRangeSelectionDisplayMode,
        pointFraction: CGFloat?,
        animated: Bool
    ) {
        selectionDisplayMode = displayMode
        selectionPointFraction = pointFraction
        updateSelectionAppearance(animated: animated)
        UIView.perform(animated: animated) {
            self.lowerBound = range.lowerBound
            self.upperBound = range.upperBound
            self.layoutIfNeeded()
        }
    }

    func setLimitedRange(
        fraction: CGFloat?,
        tapAction: (() -> Void)?,
        animated: Bool
    ) {
        let previousLowerBound = lowerBound
        let previousUpperBound = upperBound
        let previousSelectionPointFraction = selectionPointFraction
        limitedRangeFraction = fraction.map { crop(0, $0, 1) }.flatMap { fraction in
            guard fraction > 0.0, fraction < 1.0 else {
                return nil
            }
            return fraction
        }
        limitedRangeTapAction = tapAction
        limitedRangeOverlayView.isUserInteractionEnabled = tapAction != nil
        clampSelectionToAvailableHistory()
        setNeedsLayout()

        UIView.perform(animated: animated) {
            self.layoutIfNeeded()
        }
        
        if previousLowerBound != lowerBound
            || previousUpperBound != upperBound
            || previousSelectionPointFraction != selectionPointFraction {
            rangeDidChangeClosure?(lowerBound...upperBound)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layoutViews()
    }
    
    override var isEnabled: Bool {
        get {
            return super.isEnabled
        }
        set {
            if newValue == false {
                selectedMarker = nil
            }
            super.isEnabled = newValue
        }
    }
    
    // MARK: - Touches
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled else { return }
        guard let point = touches.first?.location(in: self) else { return }

        if selectionDisplayMode == .singlePoint {
            let indicatorX = locationInView(for: selectionPointFraction ?? upperBound)
            if abs(indicatorX - point.x) < Constants.markerSelectionRange {
                selectedMarker = .center
                selectedMarkerHorizontalOffset = point.x - indicatorX
                selectedMarkerInitialLocation = point
                isBoundCropHighlighted = true
            } else if contentFrame.contains(point) {
                targetTapLocation = point
                selectedMarkerHorizontalOffset = 0.0
                selectedMarker = nil
                selectedMarkerInitialLocation = nil
            } else {
                touchedOutsideClosure?()
            }
            return
        }
        
        if abs(locationInView(for: upperBound) - point.x + Constants.markerSelectionRange / 2) < Constants.markerSelectionRange {
            selectedMarker = .upper
            selectedMarkerHorizontalOffset = point.x - locationInView(for: upperBound)
            selectedMarkerInitialLocation = point
            isBoundCropHighlighted = true
        } else if abs(locationInView(for: lowerBound) - point.x - Constants.markerSelectionRange / 2) < Constants.markerSelectionRange {
            selectedMarker = .lower
            selectedMarkerHorizontalOffset = point.x - locationInView(for: lowerBound)
            selectedMarkerInitialLocation = point
            isBoundCropHighlighted = true
        } else if point.x > locationInView(for: lowerBound) && point.x < locationInView(for: upperBound) {
            selectedMarker = .center
            selectedMarkerHorizontalOffset = point.x - locationInView(for: lowerBound)
            selectedMarkerInitialLocation = point
            isBoundCropHighlighted = true
        } else {
            targetTapLocation = point
            selectedMarkerHorizontalOffset = cropFrameView.frame.width / 2.0
            selectedMarker = nil
            selectedMarkerInitialLocation = nil
            return
        }
        
        sendActions(for: .touchDown)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled else { return }
        guard let selectedMarker = selectedMarker else { return }
        guard let point = touches.first?.location(in: self) else { return }
        
        let horizontalPosition = point.x - selectedMarkerHorizontalOffset
        let fraction = fractionFor(offsetX: horizontalPosition)
        updateMarkerOffset(selectedMarker, fraction: fraction)
        
        if let initialPosition = selectedMarkerInitialLocation, abs(initialPosition.x - point.x) > 3.0 {
            self._isTracking = true
        }
        
        targetTapLocation = nil
        
        sendActions(for: .valueChanged)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled else { return }
        if let point = targetTapLocation {
            let horizontalPosition = point.x - selectedMarkerHorizontalOffset
            let fraction = fractionFor(offsetX: horizontalPosition)
            updateMarkerOffset(.center, fraction: fraction)
            
            sendActions(for: .touchUpInside)
            
            self.targetTapLocation = nil
            return
        }
        guard let selectedMarker = selectedMarker else {
            touchedOutsideClosure?()
            return
        }
        guard let point = touches.first?.location(in: self) else { return }
        
        let horizontalPosition = point.x - selectedMarkerHorizontalOffset
        let fraction = fractionFor(offsetX: horizontalPosition)
        updateMarkerOffset(selectedMarker, fraction: fraction)
        
        self.selectedMarker = nil
        self.selectedMarkerInitialLocation = nil
        self.isBoundCropHighlighted = false
        if bounds.contains(point) {
            sendActions(for: .touchUpInside)
        } else {
            sendActions(for: .touchUpOutside)
        }
        rangeDidChangeClosure?(lowerBound...upperBound)
        
        self._isTracking = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.targetTapLocation = nil
        self.selectedMarker = nil
        self.selectedMarkerInitialLocation = nil
        self.isBoundCropHighlighted = false
        self._isTracking = false
        sendActions(for: .touchCancel)
    }
    
    private var _isTracking: Bool = false
    override var isTracking: Bool {
        return self._isTracking
    }

    @objc private func limitedRangePressed() {
        limitedRangeTapAction?()
    }
}

private extension RangeChartView {
    var contentFrame: CGRect {
        return CGRect(x: layoutMargins.right,
                      y: layoutMargins.top,
                      width: (bounds.width - layoutMargins.right - layoutMargins.left),
                      height: bounds.height - layoutMargins.top - layoutMargins.bottom)
    }
    
    func locationInView(for fraction: CGFloat) -> CGFloat {
        return contentFrame.minX + contentFrame.width * fraction
    }
    
    func locationInView(for fraction: Double) -> CGFloat {
        return locationInView(for: CGFloat(fraction))
    }
    
    func fractionFor(offsetX: CGFloat) -> CGFloat {
        guard contentFrame.width > 0 else {
            return 0
        }
        
        return crop(0, CGFloat((offsetX - contentFrame.minX ) / contentFrame.width), 1)
    }
    
    private func updateMarkerOffset(_ marker: Marker, fraction: CGFloat, notifyDelegate: Bool = true) {
        let fractionToCount: CGFloat
        if isRangePagingEnabled {
            guard let minValue = stride(from: CGFloat(0.0), through: CGFloat(1.0), by: minimumRangeDistance).min(by: { abs($0 - fraction) < abs($1 - fraction) }) else { return }
            fractionToCount = minValue
        } else {
            fractionToCount = fraction
        }

        let minimumSelectableFraction = self.minimumSelectableFraction
        switch marker {
        case .lower:
            lowerBound = max(minimumSelectableFraction, min(fractionToCount, upperBound - minimumRangeDistance))
        case .upper:
            upperBound = max(fractionToCount, lowerBound + minimumRangeDistance)
        case .center:
            if selectionDisplayMode == .singlePoint {
                let minimumUpperBound = min(1, max(minimumRangeDistance, minimumSelectableFraction + minimumRangeDistance))
                let clampedUpperBound = max(minimumUpperBound, fractionToCount)
                upperBound = clampedUpperBound
                lowerBound = max(minimumSelectableFraction, clampedUpperBound - minimumRangeDistance)
                selectionPointFraction = upperBound
            } else {
                let distance = upperBound - lowerBound
                lowerBound = max(minimumSelectableFraction, min(fractionToCount, 1 - distance))
                upperBound = lowerBound + distance
            }
        }
        if notifyDelegate {
            rangeDidChangeClosure?(lowerBound...upperBound)
        }
        UIView.animate(withDuration: isRangePagingEnabled ? 0.1 : 0) {
            self.layoutIfNeeded()
        }
    }
    
    // MARK: - Layout
    
    func layoutViews() {
        let cropFrame: CGRect
        if selectionDisplayMode == .singlePoint {
            let indicatorX = locationInView(for: selectionPointFraction ?? upperBound)
            cropFrame = CGRect(
                x: indicatorX - Constants.singlePointIndicatorWidth / 2.0,
                y: contentFrame.minY - Constants.cropIndicatorLineWidth,
                width: Constants.singlePointIndicatorWidth,
                height: contentFrame.height + Constants.cropIndicatorLineWidth * 2
            )
        } else {
            cropFrame = CGRect(
                x: locationInView(for: lowerBound),
                y: contentFrame.minY - Constants.cropIndicatorLineWidth,
                width: locationInView(for: upperBound) - locationInView(for: lowerBound),
                height: contentFrame.height + Constants.cropIndicatorLineWidth * 2
            )
        }
        cropFrameView.frame = cropFrame
        
        if chartView.frame != contentFrame {
            chartView.frame = contentFrame
        }

        if selectionDisplayMode == .singlePoint {
            lowerBoundTintView.frame = CGRect(
                x: contentFrame.minX,
                y: contentFrame.minY,
                width: max(0, cropFrame.minX - contentFrame.minX),
                height: contentFrame.height
            )
            
            upperBoundTintView.frame = CGRect(
                x: cropFrame.maxX,
                y: contentFrame.minY,
                width: max(0, contentFrame.maxX - cropFrame.maxX),
                height: contentFrame.height
            )
        } else {
            lowerBoundTintView.frame = CGRect(x: contentFrame.minX,
                                              y: contentFrame.minY,
                                              width: max(0, locationInView(for: lowerBound) - contentFrame.minX + Constants.titntAreaWidth),
                                              height: contentFrame.height)
            
            upperBoundTintView.frame = CGRect(x: locationInView(for: upperBound) - Constants.titntAreaWidth,
                                              y: contentFrame.minY,
                                              width: max(0, contentFrame.maxX - locationInView(for: upperBound) + Constants.titntAreaWidth),
                                              height: contentFrame.height)
        }

        updateLimitedRangeView()
    }

    func updateSelectionAppearance(animated: Bool) {
        guard let theme = appliedTheme else {
            return
        }

        let updates = {
            switch self.selectionDisplayMode {
            case .range:
                self.cropFrameView.backgroundColor = .clear
                self.cropFrameView.layer.cornerRadius = Constants.cornerRadius
                self.cropFrameView.setImage(theme.rangeCropImage, animated: false)
            case .singlePoint:
                self.cropFrameView.image = nil
                self.cropFrameView.backgroundColor = theme.actionButtonColor
                self.cropFrameView.layer.cornerRadius = Constants.singlePointIndicatorWidth / 2.0
            }
            self.layoutIfNeeded()
        }

        UIView.perform(animated: animated, animations: updates)
    }

    func updateLimitedRangeView() {
        guard let limitedRangeFraction else {
            limitedRangeOverlayView.isHidden = true
            limitedRangeBorderLayer.isHidden = true
            return
        }

        let limitedWidth = max(0, locationInView(for: limitedRangeFraction) - contentFrame.minX)
        guard limitedWidth > 0.5 else {
            limitedRangeOverlayView.isHidden = true
            limitedRangeBorderLayer.isHidden = true
            return
        }

        let overlayFrame = CGRect(
            x: contentFrame.minX,
            y: contentFrame.minY,
            width: limitedWidth,
            height: contentFrame.height
        )
        limitedRangeOverlayView.isHidden = false
        limitedRangeOverlayView.frame = overlayFrame

        let borderX = max(
            Constants.limitedRangeBorderWidth / 2.0,
            overlayFrame.width - Constants.limitedRangeBorderWidth / 2.0
        )
        let borderPath = UIBezierPath()
        borderPath.move(to: CGPoint(x: borderX, y: 0.0))
        borderPath.addLine(to: CGPoint(x: borderX, y: overlayFrame.height))
        limitedRangeBorderLayer.isHidden = false
        limitedRangeBorderLayer.frame = limitedRangeOverlayView.bounds
        limitedRangeBorderLayer.path = borderPath.cgPath

        let iconSize = CGSize(width: Constants.limitedRangeIconSize, height: Constants.limitedRangeIconSize)
        limitedRangeLockImageView.frame = CGRect(
            x: floor((overlayFrame.width - iconSize.width) / 2.0),
            y: floor((overlayFrame.height - iconSize.height) / 2.0),
            width: iconSize.width,
            height: iconSize.height
        )
        limitedRangeLockImageView.isHidden = overlayFrame.width < Constants.limitedRangeMinimumWidthForIcon
    }

    func limitedRangePalette(for theme: ChartTheme) -> (stroke: UIColor, overlay: UIColor) {
        let isDarkBackground = theme.chartBackgroundColor.perceivedBrightness < 0.65
        let stroke = isDarkBackground
            ? UIColor(red: 191.0 / 255.0, green: 192.0 / 255.0, blue: 194.0 / 255.0, alpha: 1.0)
            : UIColor(red: 97.0 / 255.0, green: 103.0 / 255.0, blue: 112.0 / 255.0, alpha: 1.0)
        return (stroke, stroke.withAlphaComponent(0.08))
    }
    
    func clampSelectionToAvailableHistory() {
        let minimumSelectableFraction = self.minimumSelectableFraction
        guard minimumSelectableFraction > 0 else {
            return
        }

        switch selectionDisplayMode {
        case .singlePoint:
            let minimumUpperBound = min(1, max(minimumRangeDistance, minimumSelectableFraction + minimumRangeDistance))
            if upperBound < minimumUpperBound || lowerBound < minimumSelectableFraction {
                upperBound = max(upperBound, minimumUpperBound)
                lowerBound = max(minimumSelectableFraction, upperBound - minimumRangeDistance)
                selectionPointFraction = upperBound
            }
        case .range:
            guard lowerBound < minimumSelectableFraction else {
                return
            }

            let distance = max(minimumRangeDistance, upperBound - lowerBound)
            if distance >= 1 - minimumSelectableFraction {
                lowerBound = minimumSelectableFraction
                upperBound = 1
            } else {
                lowerBound = minimumSelectableFraction
                upperBound = minimumSelectableFraction + distance
            }
        }
    }
}

extension RangeChartView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        appliedTheme = theme
        let limitedRangePalette = limitedRangePalette(for: theme)
        let closure = {
            self.lowerBoundTintView.backgroundColor = theme.rangeViewTintColor
            self.upperBoundTintView.backgroundColor = theme.rangeViewTintColor
            self.limitedRangeOverlayView.backgroundColor = limitedRangePalette.overlay
            self.limitedRangeBorderLayer.strokeColor = limitedRangePalette.stroke.cgColor
            self.limitedRangeLockImageView.tintColor = limitedRangePalette.stroke
        }
        updateSelectionAppearance(animated: animated)
        
        if animated {
            UIView.animate(withDuration: .defaultDuration, animations: closure)
        } else {
            closure()
        }
    }
}

private extension UIColor {
    var perceivedBrightness: CGFloat {
        var white: CGFloat = 0.0
        if getWhite(&white, alpha: nil) {
            return white
        }

        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return 1.0
        }

        return (red * 0.299) + (green * 0.587) + (blue * 0.114)
    }
}

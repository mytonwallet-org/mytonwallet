import Foundation
import UIKit

public enum ChartType {
    case lines
    case twoAxis
    case pie
    case area
    case absoluteArea
    case bars
    case step
    case twoAxisStep
    case hourlyStep
    case twoAxisHourlyStep
    case twoAxis5MinStep
    case currency
    case stars
}

private func makeRangeCropImage(frameColor: UIColor, markerColor: UIColor) -> UIImage? {
    UIGraphicsImageRenderer(size: CGSize(width: 114.0, height: 42.0)).image { rendererContext in
        let context = rendererContext.cgContext
        let bounds = CGRect(origin: .zero, size: CGSize(width: 114.0, height: 42.0))

        context.clear(bounds)
        context.setFillColor(frameColor.cgColor)

        var path = UIBezierPath(
            roundedRect: CGRect(x: 0.0, y: 0.0, width: 11.0, height: 42.0),
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: CGSize(width: 6.0, height: 6.0)
        )
        context.addPath(path.cgPath)
        context.fillPath()

        path = UIBezierPath(
            roundedRect: CGRect(x: 103.0, y: 0.0, width: 11.0, height: 42.0),
            byRoundingCorners: [.topRight, .bottomRight],
            cornerRadii: CGSize(width: 6.0, height: 6.0)
        )
        context.addPath(path.cgPath)
        context.fillPath()

        context.setFillColor(frameColor.cgColor)
        context.fill(CGRect(x: 7.0, y: 0.0, width: 4.0, height: 1.0))
        context.fill(CGRect(x: 7.0, y: 41.0, width: 4.0, height: 1.0))
        context.fill(CGRect(x: 100.0, y: 0.0, width: 4.0, height: 1.0))
        context.fill(CGRect(x: 100.0, y: 41.0, width: 4.0, height: 1.0))
        context.fill(CGRect(x: 11.0, y: 0.0, width: 92.0, height: 1.0))
        context.fill(CGRect(x: 11.0, y: 41.0, width: 92.0, height: 1.0))

        context.setLineCap(.round)
        context.setLineWidth(1.5)
        context.setStrokeColor(markerColor.cgColor)
        context.move(to: CGPoint(x: 7.0, y: 17.0))
        context.addLine(to: CGPoint(x: 4.0, y: 21.0))
        context.addLine(to: CGPoint(x: 7.0, y: 25.0))
        context.strokePath()

        context.move(to: CGPoint(x: 107.0, y: 17.0))
        context.addLine(to: CGPoint(x: 110.0, y: 21.0))
        context.addLine(to: CGPoint(x: 107.0, y: 25.0))
        context.strokePath()
    }.resizableImage(
        withCapInsets: UIEdgeInsets(top: 15.0, left: 11.0, bottom: 15.0, right: 11.0),
        resizingMode: .stretch
    )
}

public extension ChartTheme {
    static func extractedTheme(for userInterfaceStyle: UIUserInterfaceStyle) -> ChartTheme {
        switch userInterfaceStyle {
        case .dark:
            return .extractedNightTheme
        default:
            return .extractedDayTheme
        }
    }

    static var extractedDayTheme: ChartTheme {
        let frameColor = UIColor(red: 192.0 / 255.0, green: 209.0 / 255.0, blue: 225.0 / 255.0, alpha: 1.0)
        let markerColor = UIColor.white
        return ChartTheme(
            chartTitleColor: UIColor(red: 34.0 / 255.0, green: 34.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0),
            actionButtonColor: UIColor(red: 16.0 / 255.0, green: 139.0 / 255.0, blue: 227.0 / 255.0, alpha: 1.0),
            chartBackgroundColor: .white,
            chartLabelsColor: UIColor(red: 37.0 / 255.0, green: 37.0 / 255.0, blue: 41.0 / 255.0, alpha: 0.6),
            chartHelperLinesColor: UIColor(red: 24.0 / 255.0, green: 45.0 / 255.0, blue: 59.0 / 255.0, alpha: 0.1),
            chartStrongLinesColor: UIColor(red: 24.0 / 255.0, green: 45.0 / 255.0, blue: 59.0 / 255.0, alpha: 0.1),
            barChartStrongLinesColor: UIColor(red: 24.0 / 255.0, green: 45.0 / 255.0, blue: 59.0 / 255.0, alpha: 0.1),
            chartDetailsTextColor: UIColor(red: 34.0 / 255.0, green: 34.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0),
            chartDetailsArrowColor: UIColor(red: 210.0 / 255.0, green: 213.0 / 255.0, blue: 215.0 / 255.0, alpha: 1.0),
            chartDetailsViewColor: .white,
            rangeViewFrameColor: frameColor,
            rangeViewTintColor: UIColor(red: 226.0 / 255.0, green: 238.0 / 255.0, blue: 249.0 / 255.0, alpha: 0.6),
            rangeViewMarkerColor: markerColor,
            rangeCropImage: makeRangeCropImage(frameColor: frameColor, markerColor: markerColor)
        )
    }

    static var extractedNightTheme: ChartTheme {
        let frameColor = UIColor(red: 86.0 / 255.0, green: 98.0 / 255.0, blue: 109.0 / 255.0, alpha: 1.0)
        let markerColor = UIColor.white
        return ChartTheme(
            chartTitleColor: .white,
            actionButtonColor: UIColor(red: 72.0 / 255.0, green: 170.0 / 255.0, blue: 240.0 / 255.0, alpha: 1.0),
            chartBackgroundColor: UIColor(red: 36.0 / 255.0, green: 47.0 / 255.0, blue: 62.0 / 255.0, alpha: 1.0),
            chartLabelsColor: UIColor(red: 163.0 / 255.0, green: 177.0 / 255.0, blue: 194.0 / 255.0, alpha: 0.6),
            chartHelperLinesColor: UIColor(white: 1.0, alpha: 0.1),
            chartStrongLinesColor: UIColor(white: 1.0, alpha: 0.1),
            barChartStrongLinesColor: UIColor(white: 1.0, alpha: 0.1),
            chartDetailsTextColor: .white,
            chartDetailsArrowColor: UIColor(red: 210.0 / 255.0, green: 213.0 / 255.0, blue: 215.0 / 255.0, alpha: 1.0),
            chartDetailsViewColor: UIColor(red: 28.0 / 255.0, green: 37.0 / 255.0, blue: 51.0 / 255.0, alpha: 1.0),
            rangeViewFrameColor: frameColor,
            rangeViewTintColor: UIColor(red: 48.0 / 255.0, green: 66.0 / 255.0, blue: 89.0 / 255.0, alpha: 0.6),
            rangeViewMarkerColor: markerColor,
            rangeCropImage: makeRangeCropImage(frameColor: frameColor, markerColor: markerColor)
        )
    }
}

public func createChartController(
    _ data: String,
    type: ChartType,
    rate: Double = 1.0,
    getDetailsData: ((Date, @escaping (String?) -> Void) -> Void)? = nil
) -> BaseChartController? {
    var resultController: BaseChartController?
    guard let chartData = data.data(using: .utf8) else {
        return nil
    }

    ChartsDataManager.readChart(data: chartData, extraCopiesCount: 0, sync: true) { collection in
        let controller: BaseChartController
        switch type {
        case .lines:
            controller = GeneralLinesChartController(chartsCollection: collection)
            controller.isZoomable = false
        case .twoAxis:
            controller = TwoAxisLinesChartController(chartsCollection: collection)
            controller.isZoomable = false
        case .pie:
            controller = PercentPieChartController(chartsCollection: collection, initiallyZoomed: true)
        case .area:
            controller = PercentPieChartController(chartsCollection: collection, initiallyZoomed: false)
        case .absoluteArea:
            controller = StackedBarsChartController(chartsCollection: collection, smoothEdges: true)
            controller.isZoomable = false
        case .bars:
            controller = StackedBarsChartController(chartsCollection: collection)
            controller.isZoomable = false
        case .currency:
            controller = StackedBarsChartController(chartsCollection: collection, currency: .ton, drawCurrency: nil, rate: rate)
            controller.isZoomable = false
        case .stars:
            controller = StackedBarsChartController(chartsCollection: collection, currency: .xtr, drawCurrency: nil, rate: rate)
            controller.isZoomable = false
        case .step:
            controller = StepBarsChartController(chartsCollection: collection)
        case .twoAxisStep:
            controller = TwoAxisStepBarsChartController(chartsCollection: collection)
        case .hourlyStep:
            controller = StepBarsChartController(chartsCollection: collection, hourly: true)
            controller.isZoomable = false
        case .twoAxisHourlyStep:
            let stepController = TwoAxisStepBarsChartController(chartsCollection: collection)
            stepController.hourly = true
            controller = stepController
            controller.isZoomable = false
        case .twoAxis5MinStep:
            let stepController = TwoAxisStepBarsChartController(chartsCollection: collection)
            stepController.min5 = true
            controller = stepController
            controller.isZoomable = false
        }

        if let getDetailsData {
            controller.getDetailsData = { date, completion in
                getDetailsData(date) { detailsData in
                    guard
                        let detailsData,
                        let detailsBytes = detailsData.data(using: .utf8)
                    else {
                        completion(nil)
                        return
                    }

                    ChartsDataManager.readChart(data: detailsBytes, extraCopiesCount: 0, sync: true) { detailsCollection in
                        DispatchQueue.main.async {
                            completion(detailsCollection)
                        }
                    } failure: { _ in
                        completion(nil)
                    }
                }
            }
        }

        resultController = controller
    } failure: { _ in
        resultController = nil
    }

    return resultController
}

private final class HorizontalInteractionBlockerGestureRecognizer: UIGestureRecognizer {
    var shouldBlockTouch: ((CGPoint) -> Bool)?
    private var firstLocation = CGPoint.zero

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func reset() {
        super.reset()
        firstLocation = .zero
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible,
              touches.count == 1,
              let touch = touches.first,
              let view
        else {
            state = .failed
            return
        }

        let point = touch.location(in: view)
        guard shouldBlockTouch?(point) == true else {
            state = .failed
            return
        }

        firstLocation = point
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }

        let point = touch.location(in: view)
        let translation = CGPoint(x: point.x - firstLocation.x, y: point.y - firstLocation.y)
        let absTranslationX = abs(translation.x)
        let absTranslationY = abs(translation.y)
        let totalMovement = hypot(absTranslationX, absTranslationY)

        if state == .began || state == .changed {
            state = .changed
            return
        }

        if totalMovement > 10.0 {
            if absTranslationX >= absTranslationY {
                state = .began
            } else {
                state = .failed
            }
        } else if absTranslationY > 2.0 && absTranslationY > absTranslationX * 2.0 {
            state = .failed
        } else if absTranslationX > 2.0 && absTranslationX > absTranslationY * 2.0 {
            state = .began
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed:
            state = .ended
        case .possible:
            state = .failed
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed:
            state = .cancelled
        default:
            state = .failed
        }
    }
}

public final class ChartContainerView: UIView {
    private let chartView = ChartStackSection()
    private let horizontalInteractionBlockerGestureRecognizer = HorizontalInteractionBlockerGestureRecognizer()
    private var controller: BaseChartController?
    private var displayRange = true
    private var limitedRangeFraction: CGFloat?
    private var limitedRangeTapAction: (() -> Void)?
    private var currentStrings: ChartStrings = .defaultStrings
    private var currentTheme: ChartTheme?
    private var currentThemeProvider: ((UITraitCollection) -> ChartTheme)?
    private var followsSystemTheme = true
    public var zoomStateChanged: ((Bool) -> Void)? {
        didSet {
            chartView.zoomStateUpdated = zoomStateChanged
        }
    }

    private var currentExtractedTheme: ChartTheme {
        ChartTheme.extractedTheme(for: traitCollection.userInterfaceStyle)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(chartView)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.handleColorAppearanceChange()
            }
        }
        horizontalInteractionBlockerGestureRecognizer.shouldBlockTouch = { [weak self] point in
            guard let self else {
                return false
            }

            return self.chartView.blocksBackSwipe(at: point, mainChartLeftSafeInset: 30.0)
        }
        addGestureRecognizer(horizontalInteractionBlockerGestureRecognizer)
        chartView.zoomStateUpdated = { [weak self] isPieVisible in
            self?.zoomStateChanged?(isPieVisible)
        }
        apply(animated: false)
        backgroundColor = .clear
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        chartView.frame = bounds
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #available(iOS 17.0, *) {
            return
        }

        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else {
            return
        }

        handleColorAppearanceChange()
    }

    public override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0.0 ? bounds.width : UIScreen.main.bounds.width
        return CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight(for: width))
    }

    public func apply(strings: ChartStrings = .defaultStrings, animated: Bool = false) {
        followsSystemTheme = true
        currentStrings = strings
        currentThemeProvider = nil
        currentTheme = currentExtractedTheme
        chartView.apply(theme: currentExtractedTheme, strings: strings, animated: animated)
    }

    public func apply(theme: ChartTheme = .extractedDayTheme, strings: ChartStrings = .defaultStrings, animated: Bool = false) {
        followsSystemTheme = false
        currentStrings = strings
        currentThemeProvider = nil
        currentTheme = theme
        chartView.apply(theme: theme, strings: strings, animated: animated)
    }

    public func apply(
        themeProvider: @escaping (UITraitCollection) -> ChartTheme,
        strings: ChartStrings = .defaultStrings,
        animated: Bool = false
    ) {
        followsSystemTheme = false
        currentStrings = strings
        currentThemeProvider = themeProvider
        let theme = themeProvider(traitCollection)
        currentTheme = theme
        chartView.apply(theme: theme, strings: strings, animated: animated)
    }

    public func setup(controller: BaseChartController, noInitialZoom: Bool = false) {
        self.controller = controller

        var displayRange = true
        var zoomToEnding = true
        if let controller = controller as? StepBarsChartController {
            displayRange = !controller.hourly
        }
        if noInitialZoom {
            zoomToEnding = false
        }
        self.displayRange = displayRange

        chartView.setup(controller: controller, displayRange: displayRange, zoomToEnding: zoomToEnding)
        chartView.setLimitedRange(fraction: limitedRangeFraction, tapAction: limitedRangeTapAction, animated: false)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    public func setLimitedRange(
        fraction: CGFloat?,
        tapAction: (() -> Void)?,
        animated: Bool = false
    ) {
        limitedRangeFraction = fraction
        limitedRangeTapAction = tapAction
        chartView.setLimitedRange(fraction: fraction, tapAction: tapAction, animated: animated)
    }

    public func preferredHeight(for width: CGFloat) -> CGFloat {
        ChartStackSection.preferredHeight(for: width, controller: controller, displayRange: displayRange)
    }

    public func resetInteraction() {
        chartView.resetDetailsView()
    }

    public func blocksBackSwipe(at point: CGPoint, mainChartLeftSafeInset: CGFloat = 30.0) -> Bool {
        chartView.blocksBackSwipe(at: point, mainChartLeftSafeInset: mainChartLeftSafeInset)
    }

    public var horizontalInteractionBlockingGestureRecognizer: UIGestureRecognizer {
        horizontalInteractionBlockerGestureRecognizer
    }

    public func setPieVisible(_ visible: Bool, animated: Bool = true) {
        guard let pieController = controller as? PercentPieChartController else {
            return
        }

        if visible {
            pieController.showPieForCurrentRange(animated: animated)
        } else if pieController.isPieVisible {
            pieController.didTapZoomOut()
        }
    }

    private func handleColorAppearanceChange() {
        let theme: ChartTheme
        if followsSystemTheme {
            theme = currentExtractedTheme
        } else if let currentThemeProvider {
            theme = currentThemeProvider(traitCollection)
        } else if let currentTheme {
            theme = currentTheme
        } else {
            theme = currentExtractedTheme
        }

        currentTheme = theme
        chartView.apply(theme: theme, strings: currentStrings, animated: false)
    }
}

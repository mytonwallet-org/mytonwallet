//
//  ChartStackSection.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/13/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import UIKit

private enum Constants {
    static let mainChartHeight: CGFloat = 310.0
    static let rangeHeight: CGFloat = 42.0
    static let rangeOriginY: CGFloat = 310.0
    static let visibilityOriginYWithRange: CGFloat = 368.0
    static let visibilityOriginYWithoutRange: CGFloat = 326.0
    static let minimumHeightWithRange: CGFloat = 352.0
    static let minimumHeightWithoutRange: CGFloat = 310.0
    static let defaultHeight: CGFloat = 480.0
    static let headerButtonHeight: CGFloat = 38.0
    static let headerButtonWidth: CGFloat = 112.0
    static let headerHorizontalInset: CGFloat = 16.0
    static let headerVerticalInset: CGFloat = 5.0
    static let headerSpacing: CGFloat = 8.0
    static let headerTitleHeight: CGFloat = 28.0
    static let visibilityBottomInset: CGFloat = 16.0
}

private class ChartHeaderButton: UIButton {

    init(title: String, image: UIImage? = nil) {
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { _ in
            AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .regular)])
        }
        if let image {
            config.image = image
            config.imagePlacement = .leading
            config.imagePadding = 6
        }
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Constants.headerHorizontalInset,
            bottom: 0, trailing: Constants.headerHorizontalInset
        )
        config.baseForegroundColor = UIColor.systemBlue
        configuration = config
        adjustsImageWhenHighlighted = false
        isExclusiveTouch = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height = Constants.headerButtonHeight
        return size
    }
}

class ChartStackSection: UIView, ChartThemeContainer {
    private let chartView = ChartView()
    private let rangeView = RangeChartView()
    private let visibilityView = ChartVisibilityView()
    private let sectionContainerView = UIView()
    
    private let titleLabel = UILabel()
    private var backButton: ChartHeaderButton!
    private var todayButton: ChartHeaderButton!
    
    private var controller: BaseChartController?
    private var theme: ChartTheme?
    private var strings: ChartStrings?
    
    var zoomStateUpdated: ((Bool) -> Void)?
    
    private var displayRange: Bool = true
    
    var visibilityBottomInset: CGFloat = Constants.visibilityBottomInset {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    
    private let hapticFeedback = HapticFeedback()

    static func preferredHeight(
        for width: CGFloat,
        controller: BaseChartController?,
        displayRange: Bool,
        visibilityBottomInset: CGFloat = Constants.visibilityBottomInset
    ) -> CGFloat {
        let resolvedWidth = max(0.0, width)
        let minimumHeight = displayRange ? Constants.minimumHeightWithRange : Constants.minimumHeightWithoutRange

        guard let controller, controller.drawChartVisibity else {
            return minimumHeight
        }

        let items = controller.actualChartsCollection.chartValues.map { value in
            ChartVisibilityItem(title: value.name, color: value.color)
        }
        let visibilityHeight = calculateVisiblityHeight(
            width: resolvedWidth,
            items: items,
            bottomInset: visibilityBottomInset
        )
        guard visibilityHeight > 0.0 else {
            return minimumHeight
        }

        let visibilityOriginY = displayRange ? Constants.visibilityOriginYWithRange : Constants.visibilityOriginYWithoutRange
        return visibilityOriginY + visibilityHeight
    }
    
    init() {        
        backButton = ChartHeaderButton(
            title: "Zoom Out",
            image: UIImage(
                systemName: "minus.magnifyingglass",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            )?.withRenderingMode(.alwaysTemplate)
        )
        todayButton = ChartHeaderButton(title: "Today")

        super.init(frame: CGRect())

        self.addSubview(sectionContainerView)
        sectionContainerView.addSubview(chartView)
        chartView.detailsSuperview = sectionContainerView
        sectionContainerView.addSubview(rangeView)
        sectionContainerView.addSubview(visibilityView)
        sectionContainerView.addSubview(titleLabel)
        sectionContainerView.addSubview(backButton)
        sectionContainerView.addSubview(todayButton)

        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.numberOfLines = 1

        visibilityView.clipsToBounds = true

        backButton.addTarget(self, action: #selector(self.didTapBackButton), for: .touchUpInside)
        todayButton.addTarget(self, action: #selector(self.didTapTodayButton), for: .touchUpInside)

        backButton.setVisible(false, animated: false)
        todayButton.setVisible(false, animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        visibilityView.clipsToBounds = true
        backButton.isExclusiveTouch = true
        todayButton.isExclusiveTouch = true
        
        backButton.setVisible(false, animated: false)
        todayButton.setVisible(false, animated: false)
    }
    
    public func resetDetailsView() {
        controller?.cancelChartInteraction()
    }

    func setLimitedRange(fraction: CGFloat?, tapAction: (() -> Void)?, animated: Bool) {
        rangeView.setLimitedRange(fraction: fraction, tapAction: tapAction, animated: animated)
    }

    func blocksBackSwipe(at point: CGPoint, mainChartLeftSafeInset: CGFloat) -> Bool {
        guard bounds.contains(point) else {
            return false
        }

        if displayRange, rangeView.frame.contains(point) {
            return true
        }

        guard chartView.frame.contains(point) else {
            return false
        }

        return point.x > chartView.frame.minX + mainChartLeftSafeInset
    }
    
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.theme = theme
        self.strings = strings
        
        self.backButton.configuration?.title = strings.zoomOut
        self.todayButton.configuration?.title = strings.today
        
        UIView.perform(animated: animated && self.isVisibleInWindow) {            
            self.sectionContainerView.backgroundColor = theme.chartBackgroundColor
            self.rangeView.backgroundColor = theme.chartBackgroundColor
            self.visibilityView.backgroundColor = theme.chartBackgroundColor
            
            self.backButton.configuration?.baseForegroundColor = theme.actionButtonColor
            self.todayButton.configuration?.baseForegroundColor = theme.actionButtonColor
        }
        
        if rangeView.isVisibleInWindow || chartView.isVisibleInWindow {
            chartView.loadDetailsViewIfNeeded()
            chartView.apply(theme: theme, strings: strings, animated: animated && chartView.isVisibleInWindow)
            controller?.apply(theme: theme, strings: strings, animated: animated)
            rangeView.apply(theme: theme, strings: strings, animated: animated && rangeView.isVisibleInWindow)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval.random(in: 0...0.1)) {
                self.chartView.loadDetailsViewIfNeeded()
                
                self.controller?.apply(theme: theme, strings: strings, animated: false)
                self.chartView.apply(theme: theme, strings: strings, animated: false)
                self.rangeView.apply(theme: theme, strings: strings, animated: false)
            }
        }
        
        self.titleLabel.setTextColor(theme.chartTitleColor, animated: animated && titleLabel.isVisibleInWindow)
        updateHeaderControls(animated: animated)
    }
    
    @objc private func didTapBackButton() {
        self.controller?.didTapZoomOut()
    }

    @objc private func didTapTodayButton() {
        self.controller?.didTapToday()
    }
    
    func setBackButtonVisible(_ visible: Bool, animated: Bool) {
        backButton.setVisible(visible, animated: animated)
        layoutIfNeeded(animated: animated)
    }

    func updateHeaderControls(animated: Bool) {
        guard let controller = self.controller else {
            todayButton.alpha = 0.0
            todayButton.isEnabled = false
            todayButton.isUserInteractionEnabled = false
            setNeedsLayout()
            return
        }

        let isVisible = controller.showsTodayButton
        let isEnabled = controller.isTodayButtonEnabled
        let targetAlpha = isVisible ? 1.0 : 0.0

        todayButton.isEnabled = isVisible && isEnabled
        todayButton.isUserInteractionEnabled = isVisible && isEnabled
        if todayButton.alpha != targetAlpha {
            UIView.perform(animated: animated && todayButton.isVisibleInWindow) {
                self.todayButton.alpha = targetAlpha
            }
        }
        setNeedsLayout()
    }
    
    func updateToolViews(animated: Bool) {
        guard let controller = self.controller else {
            return
        }
        
        rangeView.applySelection(
            range: controller.navigationSelectionRangeFraction,
            displayMode: controller.rangeSelectionDisplayMode,
            pointFraction: controller.selectedRangePointFraction,
            animated: animated
        )
        rangeView.setRangePaging(enabled: controller.isChartRangePagingEnabled,
                                 minimumSize: controller.minimumSelectedChartRange)
        visibilityView.setVisible(controller.drawChartVisibity, animated: animated)
        if controller.drawChartVisibity {
            visibilityView.isExpanded = true
            visibilityView.items = controller.actualChartsCollection.chartValues.map { value in
                return ChartVisibilityItem(title: value.name, color: value.color)
            }
            visibilityView.setItemsSelection(controller.actualChartVisibility)
            visibilityView.setNeedsLayout()
            visibilityView.layoutIfNeeded()
        } else {
            visibilityView.isExpanded = false
        }
        updateHeaderControls(animated: animated)
        superview?.invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
        superview?.superview?.layoutIfNeeded(animated: animated)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let bounds = self.bounds
        let sectionHeight = max(
            bounds.height,
            Self.preferredHeight(
                for: bounds.width,
                controller: controller,
                displayRange: displayRange,
                visibilityBottomInset: visibilityBottomInset
            )
        )
        let visibilityOriginY = displayRange ? Constants.visibilityOriginYWithRange : Constants.visibilityOriginYWithoutRange
        let visibilityHeight = max(0.0, sectionHeight - visibilityOriginY)

        self.sectionContainerView.frame = CGRect(origin: CGPoint(), size: CGSize(width: bounds.width, height: sectionHeight))
        self.chartView.frame = CGRect(origin: CGPoint(), size: CGSize(width: bounds.width, height: Constants.mainChartHeight))
        
        self.rangeView.isHidden = !self.displayRange
        
        self.rangeView.frame = CGRect(origin: CGPoint(x: 0.0, y: Constants.rangeOriginY), size: CGSize(width: bounds.width, height: Constants.rangeHeight))
        self.visibilityView.frame = CGRect(origin: CGPoint(x: 0.0, y: visibilityOriginY), size: CGSize(width: bounds.width, height: visibilityHeight))
        
        backButton.frame = .init(origin: .zero, size: backButton.intrinsicContentSize)
        
        var todayButtonFrame = CGRect(origin: .zero, size: todayButton.intrinsicContentSize)
        todayButtonFrame.origin.x = bounds.width - todayButtonFrame.width
        todayButton.frame = todayButtonFrame
        
        layoutTitleLabel(in: bounds)
        
        self.chartView.setNeedsDisplay()
    }
    
    func setup(controller: BaseChartController, displayRange: Bool = true, zoomToEnding: Bool) {
        self.controller = controller
        self.displayRange = displayRange
        
        if let theme = self.theme, let strings = self.strings {
            controller.apply(theme: theme, strings: strings, animated: false)
        }
        
        self.chartView.renderers = controller.mainChartRenderers
        self.chartView.userDidSelectCoordinateClosure = { [unowned self] point in
            self.controller?.chartInteractionDidBegin(point: point)
        }
        self.chartView.userDidDeselectCoordinateClosure = { [unowned self] in
            self.controller?.chartInteractionDidEnd()
        }
        controller.cartViewBounds = { [unowned self] in
            return self.chartView.bounds
        }
        controller.chartFrame = { [unowned self] in
            return self.chartView.chartFrame
        }
        controller.setDetailsViewModel = { [unowned self] viewModel, animated, feedback in
            self.chartView.setDetailsViewModel(viewModel: viewModel, animated: animated)
            if feedback {
                self.hapticFeedback.tap()
            }
        }
        controller.setDetailsChartVisibleClosure = { [unowned self] visible, animated in
            self.chartView.setDetailsChartVisible(visible, animated: animated)
        }
        controller.setDetailsViewPositionClosure = { [unowned self] position in
            self.chartView.detailsViewPosition = position
        }
        controller.setChartTitleClosure = { [unowned self] title, animated in
            if self.titleLabel.setText(title, animated: animated) {
                setNeedsLayout()
            }
        }
        controller.setBackButtonVisibilityClosure = { [unowned self] visible, animated in
            self.setNeedsLayout()
            self.setBackButtonVisible(visible, animated: animated)
            self.updateToolViews(animated: animated)
            self.zoomStateUpdated?(visible)
        }
        controller.refreshChartToolsClosure = { [unowned self] animated in
            self.updateToolViews(animated: animated)
        }
        
        self.rangeView.chartView.renderers = controller.navigationRenderers
        self.rangeView.rangeDidChangeClosure = { range in
            controller.updateChartRange(range)
        }
        self.rangeView.touchedOutsideClosure = {
            controller.cancelChartInteraction()
        }
        controller.chartRangeUpdatedClosure = { [unowned self] (_, animated) in
            self.rangeView.applySelection(
                range: controller.navigationSelectionRangeFraction,
                displayMode: controller.rangeSelectionDisplayMode,
                pointFraction: controller.selectedRangePointFraction,
                animated: animated
            )
            self.updateHeaderControls(animated: animated)
        }
        controller.chartRangePagingClosure = { [unowned self] (isEnabled, pageSize) in
            self.rangeView.setRangePaging(enabled: isEnabled, minimumSize: pageSize)
        }

        self.visibilityView.selectionCallbackClosure = { [unowned self] visibility in
            self.controller?.updateChartsVisibility(visibility: visibility, animated: true)
        }
        
        controller.initializeChart()
        updateToolViews(animated: false)

        if controller.rangeSelectionDisplayMode == .range {
            let range: ClosedRange<CGFloat> = displayRange && zoomToEnding ? 0.8 ... 1.0 : 0.0 ... 1.0
            rangeView.setRange(range, animated: false)
            controller.updateChartRange(range, animated: false)
        }
        
        self.setNeedsLayout()
    }

    func resetRange(animated: Bool) {
        guard controller?.rangeSelectionDisplayMode == .range else { return }
        rangeView.resetRange(animated: animated)
    }

    func expandRange(lowerBound: CGFloat = 0, animated: Bool = false) {
        guard controller?.rangeSelectionDisplayMode == .range else { return }
        let range = lowerBound...CGFloat(1)
        rangeView.setRange(range, animated: animated)
        controller?.updateChartRange(range, animated: false)
    }
    
    private func layoutTitleLabel(in bounds: CGRect) {
        let hasBackButton = backButton.alpha > 0.0
        let hasTodayButton = todayButton.alpha > 0.0

        if !hasBackButton && hasTodayButton {
            titleLabel.textAlignment = .left
            titleLabel.frame = CGRect(
                x: Constants.headerHorizontalInset,
                y: Constants.headerVerticalInset,
                width: max(0.0, todayButton.frame.minX - Constants.headerSpacing - Constants.headerHorizontalInset),
                height: Constants.headerTitleHeight
            )
            return
        }

        let minX = hasBackButton ? backButton.frame.maxX : Constants.headerHorizontalInset
        let maxX = hasTodayButton ? todayButton.frame.minX : bounds.width - Constants.headerHorizontalInset
        let availableWidth = max(0.0, maxX - minX)
        let textWidth = min(titleLabel.intrinsicContentSize.width, availableWidth)
        let idealX = bounds.midX - textWidth / 2
        let labelX = max(minX, min(idealX, maxX - textWidth))
        titleLabel.textAlignment = .center
        titleLabel.frame = CGRect(
            x: labelX,
            y: Constants.headerVerticalInset,
            width: textWidth,
            height: Constants.headerTitleHeight
        )
    }
}

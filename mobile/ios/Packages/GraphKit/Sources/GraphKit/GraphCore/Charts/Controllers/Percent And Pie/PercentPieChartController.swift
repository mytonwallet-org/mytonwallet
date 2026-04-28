//
//  PercentPieChartController.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/7/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

enum PercentConstants {
    static let percentValueFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.positiveSuffix = "%"
        return formatter
    }()
}

public class PercentPieChartController: BaseChartController {
    let percentController: PercentChartComponentController
    let pieController: PieChartComponentController
    let transitionRenderer: PercentPieAnimationRenderer
    private var rememberedPercentHorizontalRange: ClosedRange<CGFloat>?
    public var keepsFullRangePreviewWhenZoomed = false

    public override var detailsValueTextProvider: ChartDetailsValueTextProvider? {
        didSet {
            percentController.detailsValueTextProvider = detailsValueTextProvider
            pieController.detailsValueTextProvider = detailsValueTextProvider
        }
    }

    public override var detailsRowSortOrder: ChartDetailsRowSortOrder {
        didSet {
            percentController.detailsRowSortOrder = detailsRowSortOrder
            pieController.detailsRowSortOrder = detailsRowSortOrder
        }
    }

    public override var hidesZeroDetailsRows: Bool {
        didSet {
            percentController.hidesZeroDetailsRows = hidesZeroDetailsRows
            pieController.hidesZeroDetailsRows = hidesZeroDetailsRows
        }
    }
    
    var initiallyZoomed = false
    public convenience init(chartsCollection: ChartsCollection, initiallyZoomed: Bool) {
        self.init(chartsCollection: chartsCollection)
        self.initiallyZoomed = initiallyZoomed
    }
    
    override public init(chartsCollection: ChartsCollection)  {
        transitionRenderer = PercentPieAnimationRenderer()
        percentController = PercentChartComponentController(isZoomed: false,
                                                            mainPecentChartRenderer: PecentChartRenderer(),
                                                            horizontalScalesRenderer: HorizontalScalesRenderer(),
                                                            verticalScalesRenderer: VerticalScalesRenderer(),
                                                            verticalLineRenderer: VerticalLinesRenderer(),
                                                            previewPercentChartRenderer: PecentChartRenderer())
        pieController = PieChartComponentController(isZoomed: true,
                                                    pieChartRenderer: PieChartRenderer(),
                                                    previewBarChartRenderer: BarChartRenderer())
        
        super.init(chartsCollection: chartsCollection)
        
        [percentController, pieController].forEach { controller in
            controller.chartFrame = { [unowned self] in self.chartFrame() }
            controller.cartViewBounds = { [unowned self] in self.cartViewBounds() }
            controller.zoomInOnDateClosure = { [unowned self] date in
                self.didTapZoomIn(date: date, pointIndex: 0)
            }
            controller.setChartTitleClosure = { [unowned self] (title, animated) in
                self.setChartTitleClosure?(title, animated)
            }
            controller.setDetailsViewPositionClosure = { [unowned self] (position) in
                self.setDetailsViewPositionClosure?(position)
            }
            controller.setDetailsChartVisibleClosure = { [unowned self] (visible, animated) in
                self.setDetailsChartVisibleClosure?(visible, animated)
            }
            controller.setDetailsViewModel = { [unowned self] (viewModel, animated, feedback) in
                self.setDetailsViewModel?(viewModel, animated, feedback)
            }
            controller.updatePreviewRangeClosure = { [unowned self] (fraction, animated) in
                self.chartRangeUpdatedClosure?(fraction, animated)
            }
            controller.chartRangePagingClosure = { [unowned self] (isEnabled, pageSize) in
                self.setChartRangePagingEnabled(isEnabled: isEnabled, minimumSelectionSize: pageSize)
            }
        }
        transitionRenderer.isEnabled = false
    }
    
    public override var mainChartRenderers: [ChartViewRenderer] {
        return [percentController.mainPecentChartRenderer,
                transitionRenderer,
                percentController.horizontalScalesRenderer,
                percentController.verticalScalesRenderer,
                percentController.verticalLineRenderer,
                pieController.pieChartRenderer,
//                performanceRenderer
        ]
    }
    
    public override var navigationRenderers: [ChartViewRenderer] {
        return [percentController.previewPercentChartRenderer,
                pieController.previewBarChartRenderer]
    }

    public override func initializeChart() {
        percentController.initialize(chartsCollection: initialChartsCollection,
                                     initialDate: Date(),
                                     totalHorizontalRange: BaseConstants.defaultRange,
                                     totalVerticalRange: BaseConstants.defaultRange)
        switchToChart(chartsCollection: percentController.chartsCollection, isZoomed: false, animated: false)
        rememberedPercentHorizontalRange = percentController.currentHorizontalMainChartRange
    
        if let lastDate = initialChartsCollection.axisValues.last, self.initiallyZoomed {
            TimeInterval.animationDurationMultipler = 0.00001
            self.didTapZoomIn(date: lastDate, animated: false)
            TimeInterval.animationDurationMultipler = 1.0
        }
    }

    private func preparePieController(for date: Date) -> ChartsCollection? {
        let currentCollection = percentController.chartsCollection
        guard let (foundDate, _) = percentController.findClosestDateTo(dateToFind: date) else {
            return nil
        }
        let selectedRange = CGFloat(foundDate.timeIntervalSince1970 - .day)...CGFloat(foundDate.timeIntervalSince1970)
        pieController.initialize(
            chartsCollection: currentCollection,
            initialDate: date,
            totalHorizontalRange: 0...1,
            totalVerticalRange: 0...1
        )
        pieController.initialHorizontalRange = selectedRange
        return currentCollection
    }
    
    func switchToChart(chartsCollection: ChartsCollection, isZoomed: Bool, animated: Bool) {
        if animated {
            TimeInterval.setDefaultDuration(.expandAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + .expandAnimationDuration) {
                TimeInterval.setDefaultDuration(.osXDuration)
            }
        }

        super.isZoomed = isZoomed
        if isZoomed {
            let toHorizontalRange = pieController.initialHorizontalRange

            pieController.updateChartsVisibility(visibility: percentController.chartVisibility, animated: false)
            pieController.pieChartRenderer.setup(horizontalRange: percentController.currentHorizontalMainChartRange, animated: false)
            pieController.previewBarChartRenderer.setup(horizontalRange: percentController.currentPreviewHorizontalRange, animated: false)
            pieController.pieChartRenderer.setVisible(false, animated: false)
            pieController.previewBarChartRenderer.setVisible(true, animated: false)

            pieController.willAppear(animated: animated)
            percentController.willDisappear(animated: animated)

            pieController.pieChartRenderer.drawPie = false
            percentController.mainPecentChartRenderer.isEnabled = false
            
            setupTransitionRenderer()
            
            percentController.setupMainChart(horizontalRange: toHorizontalRange, animated: animated)
            percentController.previewPercentChartRenderer.setup(horizontalRange: toHorizontalRange, animated: animated)
            percentController.setConponentsVisible(visible: false, animated: animated)
            
            transitionRenderer.animate(fromDataToPie: true, animated: animated) { [weak self] in
                self?.pieController.pieChartRenderer.drawPie = true
                self?.percentController.mainPecentChartRenderer.isEnabled = true
            }
            if !animated {
                pieController.pieChartRenderer.drawPie = true
                percentController.mainPecentChartRenderer.isEnabled = true
                transitionRenderer.isEnabled = false
            }
            applyZoomedPreviewMode(animated: animated)
        } else {
            if !pieController.chartsCollection.isBlank {
                let fromHorizontalRange = pieController.currentHorizontalMainChartRange
                let toHorizontalRange = percentController.initialHorizontalRange

                pieController.pieChartRenderer.setup(horizontalRange: toHorizontalRange, animated: animated)
                pieController.previewBarChartRenderer.setup(horizontalRange: toHorizontalRange, animated: animated)
                pieController.pieChartRenderer.setVisible(false, animated: animated)
                pieController.previewBarChartRenderer.setVisible(false, animated: animated)
                
                percentController.updateChartsVisibility(visibility: pieController.chartVisibility, animated: false)
                percentController.setupMainChart(horizontalRange: fromHorizontalRange, animated: false)
                percentController.previewPercentChartRenderer.setup(horizontalRange: fromHorizontalRange, animated: false)
                percentController.setConponentsVisible(visible: false, animated: false)
            }
            
            percentController.willAppear(animated: animated)
            pieController.willDisappear(animated: animated)
            
            if animated {
                pieController.pieChartRenderer.drawPie = false
                percentController.mainPecentChartRenderer.isEnabled = false
                
                setupTransitionRenderer()

                transitionRenderer.animate(fromDataToPie: false, animated: true) {
                    self.pieController.pieChartRenderer.drawPie = true
                    self.percentController.mainPecentChartRenderer.isEnabled = true
                }
            }
        }
        
        self.setBackButtonVisibilityClosure?(isZoomed, animated)
    }
    
    func setupTransitionRenderer() {
        transitionRenderer.setup(verticalRange: percentController.currentVerticalMainChartRange, animated: false)
        transitionRenderer.setup(horizontalRange: percentController.currentHorizontalMainChartRange, animated: false)
        transitionRenderer.visiblePieComponents = pieController.visiblePieDataWithCurrentPreviewRange
        transitionRenderer.visiblePercentageData = percentController.currentlyVisiblePercentageData
    }
    
    public override func updateChartsVisibility(visibility: [Bool], animated: Bool) {
        if isZoomed {
            pieController.updateChartsVisibility(visibility: visibility, animated: animated)
        } else {
            percentController.updateChartsVisibility(visibility: visibility, animated: animated)
        }
    }
    
    var visibleChartValues: [ChartsCollection.Chart] {
        let visibility = isZoomed ? pieController.chartVisibility : percentController.chartVisibility
        let collection = isZoomed ? pieController.chartsCollection : percentController.chartsCollection
        let visibleCharts: [ChartsCollection.Chart] = visibility.enumerated().compactMap { args in
            args.element ? collection.chartValues[args.offset] : nil
        }
        return visibleCharts
    }

    public override var actualChartVisibility: [Bool] {
        return isZoomed ? pieController.chartVisibility : percentController.chartVisibility
    }
    
    public override var actualChartsCollection: ChartsCollection {
        let collection = isZoomed ? pieController.chartsCollection : percentController.chartsCollection
        
        if collection.isBlank {
            return self.initialChartsCollection
        }
        return collection
    }
    
    public override func chartInteractionDidBegin(point: CGPoint, manual: Bool = true) {
        if isZoomed {
            pieController.chartInteractionDidBegin(point: point, manual: manual)
        } else {
            percentController.chartInteractionDidBegin(point: point, manual: manual)
        }
    }
    
    public override func chartInteractionDidEnd() {
        if isZoomed {
            pieController.chartInteractionDidEnd()
        } else {
            percentController.chartInteractionDidEnd()
        }
    }
    
    public override var drawChartVisibity: Bool {
        return true
    }
    
    public override var currentChartHorizontalRangeFraction: ClosedRange<CGFloat> {
        if isZoomed {
            return pieController.currentChartHorizontalRangeFraction
        } else {
            return percentController.currentChartHorizontalRangeFraction
        }
    }

    public override var navigationSelectionRangeFraction: ClosedRange<CGFloat> {
        guard isZoomed, keepsFullRangePreviewWhenZoomed else {
            return currentChartHorizontalRangeFraction
        }

        let selectedFraction = fullRangeFraction(for: pieController.currentHorizontalMainChartRange.upperBound)
        let lowerBound = max(0.0, selectedFraction - minimumSelectedChartRange)
        return lowerBound...selectedFraction
    }

    public override var showsTodayButton: Bool {
        true
    }

    public override var isTodayButtonEnabled: Bool {
        guard !initialChartsCollection.axisValues.isEmpty else {
            return false
        }
        guard isZoomed else {
            return true
        }
        return !isDisplayingLatestPoint
    }
    
    public override func cancelChartInteraction() {
        if isZoomed {
            return pieController.hideDetailsView(animated: true)
        } else {
            return percentController.hideDetailsView(animated: true)
        }
    }
    
    func didTapZoomIn(date: Date, animated: Bool) {
        guard !isZoomed, isZoomable else { return }
        cancelChartInteraction()
        rememberedPercentHorizontalRange = percentController.currentHorizontalMainChartRange
        guard let newCollection = preparePieController(for: date) else {
            return
        }
        switchToChart(chartsCollection: newCollection, isZoomed: true, animated: animated)
    }
    
    public override func didTapZoomIn(date: Date, pointIndex: Int) {
        self.didTapZoomIn(date: date, animated: true)
    }

    public var isPieVisible: Bool {
        return isZoomed
    }

    public func showPieForCurrentRange(animated: Bool = true) {
        guard !isZoomed else {
            return
        }

        cancelChartInteraction()
        let currentRange = percentController.currentHorizontalMainChartRange
        rememberedPercentHorizontalRange = currentRange
        let targetDate = Date(timeIntervalSince1970: TimeInterval(currentRange.upperBound))
        guard let newCollection = preparePieController(for: targetDate) else {
            return
        }
        switchToChart(chartsCollection: newCollection, isZoomed: true, animated: animated)
    }
    
    public override func didTapZoomOut() {
        self.pieController.deselectSegment(completion: { [weak self] in
            guard let self = self else { return }
            if let rememberedPercentHorizontalRange = self.rememberedPercentHorizontalRange {
                self.percentController.initialHorizontalRange = rememberedPercentHorizontalRange
            }
            self.switchToChart(chartsCollection: self.percentController.chartsCollection, isZoomed: false, animated: true)
        })
    }

    public override func didTapToday() {
        guard let lastDate = initialChartsCollection.axisValues.last else {
            return
        }

        if isZoomed {
            guard !isDisplayingLatestPoint else {
                return
            }
            cancelChartInteraction()
            updateChartRange(latestSelectionRangeFraction, animated: true)
        } else {
            didTapZoomIn(date: lastDate, animated: true)
        }
    }
    
    public override func updateChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool = true) {
        if isZoomed {
            pieController.chartRangeFractionDidUpdated(rangeFraction)
            chartRangeUpdatedClosure?(navigationSelectionRangeFraction, animated)
            return
        } else {
            percentController.chartRangeFractionDidUpdated(rangeFraction)
            rememberedPercentHorizontalRange = percentController.currentHorizontalMainChartRange
            return
        }
    }

    public override var rangeSelectionDisplayMode: ChartRangeSelectionDisplayMode {
        isZoomed ? .singlePoint : .range
    }

    public override var selectedRangePointFraction: CGFloat? {
        guard isZoomed else {
            return nil
        }
        if keepsFullRangePreviewWhenZoomed {
            return fullRangeFraction(for: pieController.currentHorizontalMainChartRange.upperBound)
        }
        return pieController.currentChartHorizontalRangeFraction.upperBound
    }
    
    public override func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        super.apply(theme: theme, strings: strings, animated: animated)
        
        pieController.apply(theme: theme, strings: strings, animated: animated)
        percentController.apply(theme: theme, strings: strings, animated: animated)
        transitionRenderer.backgroundColor = theme.chartBackgroundColor
    }
}

private extension PercentPieChartController {
    var isDisplayingLatestPoint: Bool {
        navigationSelectionRangeFraction.upperBound >= 0.999_999
    }

    var latestSelectionRangeFraction: ClosedRange<CGFloat> {
        let selectionLength: CGFloat
        if isZoomed {
            selectionLength = max(minimumSelectedChartRange, pieController.currentChartHorizontalRangeFraction.distance)
        } else {
            let itemCount = max(1, initialChartsCollection.axisValues.count)
            selectionLength = max(minimumSelectedChartRange, 1.0 / CGFloat(itemCount))
        }
        return max(0.0, 1.0 - selectionLength)...1.0
    }

    func fullRangeFraction(for timestamp: CGFloat) -> CGFloat {
        let totalRange = percentController.totalHorizontalRange
        guard totalRange.distance > 0 else {
            return 1.0
        }
        return crop(0.0, (timestamp - totalRange.lowerBound) / totalRange.distance, 1.0)
    }

    func applyZoomedPreviewMode(animated: Bool) {
        guard isZoomed, keepsFullRangePreviewWhenZoomed else {
            return
        }

        percentController.previewPercentChartRenderer.setup(verticalRange: percentController.totalVerticalRange, animated: animated)
        percentController.previewPercentChartRenderer.setup(horizontalRange: percentController.totalHorizontalRange, animated: animated)
        percentController.previewPercentChartRenderer.setVisible(true, animated: animated)
        pieController.previewBarChartRenderer.setVisible(false, animated: animated)
    }
}

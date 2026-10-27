//
//  PieChartComponentController.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/14/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

class PieChartComponentController: GeneralChartComponentController {
    let pieChartRenderer: PieChartRenderer
    let previewBarChartRenderer: BarChartRenderer
    var barWidth: CGFloat = 1
    private(set) var selectedPointIndex: Int?

    var selectedDate: Date? {
        selectedPointIndex.map { chartsCollection.axisValues[$0] }
    }
    
    var chartBars: BarChartRenderer.BarsData = .blank
    
    init(isZoomed: Bool,
         pieChartRenderer: PieChartRenderer,
         previewBarChartRenderer: BarChartRenderer) {
        self.pieChartRenderer = pieChartRenderer
        self.previewBarChartRenderer = previewBarChartRenderer
        super.init(isZoomed: isZoomed)
    }
    
    override func initialize(chartsCollection: ChartsCollection, initialDate: Date, totalHorizontalRange _: ClosedRange<CGFloat>, totalVerticalRange _: ClosedRange<CGFloat>) {
        let (width, chartBars, totalHorizontalRange, _) = BarChartRenderer.BarsData.initialComponents(chartsCollection: chartsCollection)
        self.barWidth = width
        self.chartBars = chartBars
        super.initialize(chartsCollection: chartsCollection,
                         initialDate: initialDate,
                         totalHorizontalRange: totalHorizontalRange,
                         totalVerticalRange: BaseConstants.defaultRange)
        
        self.previewBarChartRenderer.bars = chartBars
        self.previewBarChartRenderer.fillToTop = true
        
        pieChartRenderer.valuesFormatter = PercentConstants.percentValueFormatter
        pieChartRenderer.setup(horizontalRange: initialHorizontalRange, animated: false)
        previewBarChartRenderer.setup(verticalRange: initialVerticalRange, animated: false)
        previewBarChartRenderer.setup(horizontalRange: initialHorizontalRange, animated: false)
        
        pieChartRenderer.updatePercentageData(pieDataAtSelectedPoint, animated: false)
        pieChartRenderer.selectSegmentAt(at: nil, animated: false)
    }

    override func setupInitialChartRange(initialDate: Date) {
        updateSelectedPoint(for: initialDate)
        initialVerticalRange = totalVerticalRange
    }

    private func updateSelectedPoint(for date: Date) {
        guard let (selectedDate, index) = findClosestDateTo(dateToFind: date) else {
            selectedPointIndex = nil
            return
        }
        selectedPointIndex = index
        let upperBound = CGFloat(selectedDate.timeIntervalSince1970)
        let lowerBound = index > 0 ? CGFloat(chartsCollection.axisValues[index - 1].timeIntervalSince1970) : upperBound - barWidth
        initialHorizontalRange = lowerBound...upperBound
    }

    private var pieDataAtSelectedPoint: [PieChartRenderer.PieComponent] {
        chartsCollection.chartValues.map { chart in
            PieChartRenderer.PieComponent(color: chart.color, value: selectedPointIndex.map { CGFloat(chart.values[$0]) } ?? 0)
        }
    }
    
    var visiblePieDataAtSelectedPoint: [PieChartRenderer.PieComponent] {
        let currentData = pieDataAtSelectedPoint
        return chartVisibility.enumerated().compactMap { $0.element ? currentData[$0.offset] : nil }
    }
    
    override func willAppear(animated: Bool) {
        pieChartRenderer.setup(horizontalRange: initialHorizontalRange, animated: animated)
        pieChartRenderer.setVisible(true, animated: animated)
        
        previewBarChartRenderer.setup(verticalRange: totalVerticalRange, animated: animated)
        previewBarChartRenderer.setup(horizontalRange: totalHorizontalRange, animated: animated)
        previewBarChartRenderer.setVisible(true, animated: animated)
        
        updatePreviewRangeClosure?(currentChartHorizontalRangeFraction, animated)
        pieChartRenderer.updatePercentageData(pieDataAtSelectedPoint, animated: false)
        
        super.willAppear(animated: animated)
    }
    
    override func setupChartRangePaging() {
        let valuesCount = chartsCollection.axisValues.count
        guard valuesCount > 0 else { return }
        chartRangePagingClosure?(true, 1.0 / CGFloat(valuesCount))
    }
    
    override func chartRangeDidUpdated(_ updatedRange: ClosedRange<CGFloat>) {
        selectDate(Date(timeIntervalSince1970: TimeInterval(updatedRange.upperBound)), animated: true)
    }

    func selectDate(_ date: Date, animated: Bool) {
        updateSelectedPoint(for: date)
        pieChartRenderer.setup(horizontalRange: initialHorizontalRange, animated: animated)
        pieChartRenderer.updatePercentageData(pieDataAtSelectedPoint, animated: animated)
        updateChartRangeTitle(animated: animated)
        updateSelectedDataLabelIfNeeded()
    }
    
    public override func updateChartsVisibility(visibility: [Bool], animated: Bool) {
        super.updateChartsVisibility(visibility: visibility, animated: animated)
        for (index, isVisible) in visibility.enumerated() {
            pieChartRenderer.setComponentVisible(isVisible, at: index, animated: animated)
            previewBarChartRenderer.setComponentVisible(isVisible, at: index, animated: animated)
        }
        if let segment = pieChartRenderer.selectedSegment {
            if !visibility[segment] {
                pieChartRenderer.selectSegmentAt(at: nil, animated: true)
            }
        }
        updateSelectedDataLabelIfNeeded()
    }
    
    func deselectSegment(completion: @escaping () -> Void) {
        if pieChartRenderer.hasSelectedSegments {
            hideDetailsView(animated: true)
            pieChartRenderer.selectSegmentAt(at: nil, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + .defaultDuration / 2) {
                completion()
            }
        } else {
            completion()
        }
    }
    
    func updateSelectedDataLabelIfNeeded() {
        if let segment = pieChartRenderer.selectedSegment {
            self.setDetailsChartVisibleClosure?(true, true)
            self.setDetailsViewModel?(chartDetailsViewModel(segmentInde: segment), false, false)
            self.setDetailsViewPositionClosure?(chartFrame().width / 4)
        } else {
            self.setDetailsChartVisibleClosure?(false, true)
        }
    }
    
    func chartDetailsViewModel(segmentInde: Int) -> ChartDetailsViewModel {
        let pieItem = pieDataAtSelectedPoint[segmentInde]
        let title = chartsCollection.chartValues[segmentInde].name
        let item = ChartDetailsItemContext(
            id: "series-\(segmentInde)",
            index: segmentInde,
            role: .series,
            prefix: nil,
            title: title,
            rawValue: Double(pieItem.value),
            formattedValue: BaseConstants.detailsNumberFormatter.string(from: pieItem.value) ?? "",
            color: pieItem.color,
            isVisible: true
        )
        let values = makeDetailsValues(from: [item])
        let viewModel = ChartDetailsViewModel(title: "",
                                              showArrow: false,
                                              showPrefixes: false,
                                              isLoading: false,
                                              values: values,
                                              totalValue: nil,
                                              tapAction: nil,
                                              hideAction: { [weak self] in
                                                self?.deselectSegment(completion: {})
        })
        return viewModel
    }
    
    override var currentMainRangeRenderer: BaseChartRenderer {
        return pieChartRenderer
    }
    
    override var currentPreviewRangeRenderer: BaseChartRenderer {
        return previewBarChartRenderer
    }

    public override func chartInteractionDidBegin(point: CGPoint, manual: Bool = true) {
        if let segment = pieChartRenderer.selectedItemIndex(at: point) {
            pieChartRenderer.selectSegmentAt(at: segment, animated: true)
            updateSelectedDataLabelIfNeeded()
        }
    }
    
    override func hideDetailsView(animated: Bool) {
        pieChartRenderer.selectSegmentAt(at: nil, animated: animated)
        updateSelectedDataLabelIfNeeded()
    }
    
    override func updateChartRangeTitle(animated: Bool) {
        guard let selectedDate else { return }
        let string = strings.formattedSingleDateTitle(selectedDate, includesTime: barWidth < CGFloat(TimeInterval.day))
        self.setChartTitleClosure?(string, animated)
    }
}

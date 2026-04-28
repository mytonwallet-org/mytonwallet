//
//  BaseChartController.swift
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


enum BaseConstants {
    static let defaultRange: ClosedRange<CGFloat> = 0...1
    static let minimumAxisYLabelsDistance: CGFloat = 85
    static let monthDayDateFormatter = DateFormatter.utc(format: "MMM d")
    static let timeDateFormatter = DateFormatter.utc(format: "HH:mm")
    static let headerFullRangeFormatter: DateFormatter = {
        let formatter = DateFormatter.utc()
        formatter.calendar = Calendar.utc
        formatter.dateStyle = .long
        return formatter
    }()
    static let headerMediumRangeFormatter: DateFormatter = {
        let formatter = DateFormatter.utc()
        formatter.dateStyle = .medium
        return formatter
    }()
    static let headerFullZoomedFormatter: DateFormatter = {
        let formatter = DateFormatter.utc()
        formatter.dateStyle = .full
        return formatter
    }()

    static let verticalBaseAnchors: [CGFloat] = [8, 5, 2.5, 2, 1]
    static let defaultVerticalBaseAnchor: CGFloat = 1

    static let mainChartLineWidth: CGFloat = 2
    static let previewChartLineWidth: CGFloat = 1

    static let previewLinesChartOptimizationLevel: CGFloat = 1.5
    static let linesChartOptimizationLevel: CGFloat = 1.0
    static let barsChartOptimizationLevel: CGFloat = 0.75

    static let defaultRangePresetLength = TimeInterval.day * 60
    
    static let chartNumberFormatter: ScalesNumberFormatter = {
        let numberFormatter = ScalesNumberFormatter()
        numberFormatter.allowsFloats = true
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = true
        numberFormatter.groupingSeparator = " "
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    static let tonNumberFormatter: NumberFormatter = {
        let numberFormatter = TonNumberFormatter()
        numberFormatter.allowsFloats = true
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = true
        numberFormatter.groupingSeparator = " "
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    static let starNumberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.allowsFloats = true
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = true
        numberFormatter.groupingSeparator = " "
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    static let detailsNumberFormatter: NumberFormatter = {
        let detailsNumberFormatter = NumberFormatter()
        detailsNumberFormatter.allowsFloats = false
        detailsNumberFormatter.numberStyle = .decimal
        detailsNumberFormatter.usesGroupingSeparator = true
        detailsNumberFormatter.groupingSeparator = " "
        return detailsNumberFormatter
    }()
}

public enum ChartRangeSelectionDisplayMode {
    case range
    case singlePoint
}

public enum ChartDetailsContextKind {
    case point(date: Date, pointIndex: Int)
    case pieSegment(index: Int)
}

public enum ChartDetailsItemRole {
    case series
    case total
}

public enum ChartDetailsRowSortOrder {
    case original
    case descendingValue
}

public struct ChartDetailsItemContext {
    public let id: String
    public let index: Int
    public let role: ChartDetailsItemRole
    public let prefix: String?
    public let title: String
    public let rawValue: Double
    public let formattedValue: String
    public let color: GColor
    public let isVisible: Bool

    public init(
        id: String,
        index: Int,
        role: ChartDetailsItemRole,
        prefix: String?,
        title: String,
        rawValue: Double,
        formattedValue: String,
        color: GColor,
        isVisible: Bool
    ) {
        self.id = id
        self.index = index
        self.role = role
        self.prefix = prefix
        self.title = title
        self.rawValue = rawValue
        self.formattedValue = formattedValue
        self.color = color
        self.isVisible = isVisible
    }
}

public struct ChartDetailsContext {
    public let kind: ChartDetailsContextKind
    public let items: [ChartDetailsItemContext]
    public let totalItem: ChartDetailsItemContext?

    public init(
        kind: ChartDetailsContextKind,
        items: [ChartDetailsItemContext],
        totalItem: ChartDetailsItemContext? = nil
    ) {
        self.kind = kind
        self.items = items
        self.totalItem = totalItem
    }
}

public typealias ChartDetailsValueTextProvider = (ChartDetailsItemContext) -> String?

public class BaseChartController: ChartThemeContainer {
    //let performanceRenderer = PerformanceRenderer()
    var initialChartsCollection: ChartsCollection
    var isZoomed: Bool = false
    public var isZoomable: Bool = true
    public internal(set) var strings: ChartStrings = .defaultStrings

    var chartTitle: String = ""
    
    public init(chartsCollection: ChartsCollection) {
        self.initialChartsCollection = chartsCollection
    }
        
    public var mainChartRenderers: [ChartViewRenderer] {
        fatalError("Abstract")
    }
    
    public var navigationRenderers: [ChartViewRenderer] {
        fatalError("Abstract")
    }
    
    public var cartViewBounds: (() -> CGRect) = { fatalError() }
    public var chartFrame: (() -> CGRect) = { fatalError() }
    
    public func initializeChart() {
        fatalError("Abstract")
    }
    
    public func chartInteractionDidBegin(point: CGPoint, manual: Bool = true) {
        fatalError("Abstract")
    }
    
    public func chartInteractionDidEnd() {
        fatalError("Abstract")
    }
    
    public func cancelChartInteraction() {
        fatalError("Abstract")
    }
    
    public func didTapZoomOut() {
        fatalError("Abstract")
    }
    
    public func updateChartsVisibility(visibility: [Bool], animated: Bool) {
        fatalError("Abstract")
    }
    
    public var currentHorizontalRange: ClosedRange<CGFloat> {
        fatalError("Abstract")
    }
    
    public func height(for width: CGFloat) -> CGFloat {
        var height: CGFloat = 308
        
        let items = actualChartsCollection.chartValues.map { value in
            return ChartVisibilityItem(title: value.name, color: value.color)
        }
        let frames = ChartVisibilityItem.generateItemsFrames(for: width, items: items)
        
        guard let lastFrame = frames.last else { return height }
        
        height += lastFrame.maxY
        
        return height
    }
    
    public var isChartRangePagingEnabled: Bool = false
    public var minimumSelectedChartRange: CGFloat = 0.085
    public var chartRangePagingClosure: ((Bool, CGFloat) -> Void)? // isEnabled, PageSize
    public func setChartRangePagingEnabled(isEnabled: Bool, minimumSelectionSize: CGFloat) {
        isChartRangePagingEnabled = isEnabled
        minimumSelectedChartRange = minimumSelectionSize
        chartRangePagingClosure?(isChartRangePagingEnabled, minimumSelectedChartRange)
    }
    
    public var chartRangeUpdatedClosure: ((ClosedRange<CGFloat>, Bool) -> Void)?
    public var currentChartHorizontalRangeFraction: ClosedRange<CGFloat> {
        fatalError("Abstract")
    }

    public var navigationSelectionRangeFraction: ClosedRange<CGFloat> {
        currentChartHorizontalRangeFraction
    }

    public var rangeSelectionDisplayMode: ChartRangeSelectionDisplayMode {
        .range
    }

    public var selectedRangePointFraction: CGFloat? {
        nil
    }

    public var showsTodayButton: Bool {
        false
    }

    public var isTodayButtonEnabled: Bool {
        false
    }
    
    public func updateChartRange(_ rangeFraction: ClosedRange<CGFloat>, animated: Bool = true) {
        fatalError("Abstract")
    }
    
    public var actualChartVisibility: [Bool] {
        fatalError("Abstract")
    }
    
    public var actualChartsCollection: ChartsCollection {
        fatalError("Abstract")
    }
    
    public var drawChartVisibity: Bool {
        return true
    }

    public var drawChartNavigation: Bool {
        return true
    }
    
    public var setDetailsViewPositionClosure: ((CGFloat) -> Void)?
    public var setDetailsChartVisibleClosure: ((Bool, Bool) -> Void)?
    public var setDetailsViewModel: ((ChartDetailsViewModel, Bool, Bool) -> Void)?
    public var detailsValueTextProvider: ChartDetailsValueTextProvider?
    public var detailsRowSortOrder: ChartDetailsRowSortOrder = .original
    public var hidesZeroDetailsRows = false
    public var getDetailsData: ((Date, @escaping (ChartsCollection?) -> Void) -> Void)?
    public var setChartTitleClosure: ((String, Bool) -> Void)?
    public var setBackButtonVisibilityClosure: ((Bool, Bool) -> Void)?
    public var refreshChartToolsClosure: ((Bool) -> Void)?

    public func didTapZoomIn(date: Date, pointIndex: Int) {
        fatalError("Abstract")
    }

    public func didTapToday() {
    }
    
    public func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.strings = strings
    }
}

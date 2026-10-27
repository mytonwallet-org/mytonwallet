import Foundation
import Testing
import UIKit
@testable import GraphKit

@Suite("Portfolio pie sample selection")
@MainActor
struct PortfolioPieSelectionTests {
    private nonisolated static let densities: [TimeInterval] = [300, 3600, 14400, 86400]
    private let start: TimeInterval = 1_792_238_400

    @Test(arguments: densities)
    func openingPieUsesTheLatestSampleForTitleSlicesAndTooltip(spacing: TimeInterval) throws {
        let fixture = makeFixture(spacing: spacing)
        fixture.controller.showPieForCurrentRange(animated: false)

        try expectSelection(fixture, index: 4, includesTime: spacing < .day)
        #expect(!fixture.controller.isTodayButtonEnabled)
        #expect(fixture.controller.selectedRangePointFraction == 1)
    }

    @Test(arguments: densities, [true, false])
    func minimapSelectionSnapsToSamplesAndUpdatesTheOpenTooltip(spacing: TimeInterval, fullRangePreview: Bool) throws {
        let fixture = makeFixture(spacing: spacing, fullRangePreview: fullRangePreview)
        let controller = fixture.controller
        controller.showPieForCurrentRange(animated: false)
        controller.pieController.pieChartRenderer.selectSegmentAt(at: 0, animated: false)
        controller.setDetailsViewModel = { [weak fixture] model, _, _ in fixture?.tooltip = model }

        if fullRangePreview {
            // The full-range timeline starts at the first point, without the bar preview's leading padding.
            #expect(!controller.isChartRangePagingEnabled)
            #expect(controller.minimumSelectedChartRange == 0)
        }
        for index in [0, 1, 3, 2, 4] {
            let fraction = fullRangePreview ? CGFloat(index) / 4 : CGFloat(index + 1) / 5
            controller.updateChartRange(max(0, fraction - 0.2)...fraction, animated: false)
            try expectSelection(fixture, index: index, includesTime: spacing < .day)
            #expect(fixture.tooltip?.values.first?.value == "USD \(Int(fixture.values[0][index]))")
            #expect(controller.selectedRangePointFraction == fraction)
            #expect(controller.isTodayButtonEnabled == (index != 4))
        }
    }

    @Test
    func draggingBetweenIrregularSamplesUsesTheNearestPoint() throws {
        let offsets: [TimeInterval] = [0, 300, 7200, 84600, 90000]
        let fixture = makeFixture(offsets: offsets)
        let controller = fixture.controller
        controller.showPieForCurrentRange(animated: false)

        for (seconds, expectedIndex) in [(0.0, 0), (290, 1), (7100, 2), (84700, 3), (90000, 4)] {
            let fraction = CGFloat(seconds / 90000)
            controller.updateChartRange(fraction...fraction, animated: false)
            try expectSelection(fixture, index: expectedIndex, includesTime: true)
            #expect(controller.selectedRangePointFraction == CGFloat(offsets[expectedIndex] / 90000))
        }
    }

    @Test
    func todayAndZoomTransitionsKeepTheSelectedSample() throws {
        let fixture = makeFixture()
        let controller = fixture.controller
        controller.showPieForCurrentRange(animated: false)
        controller.updateChartRange(0.5...0.5, animated: false)
        try expectSelection(fixture, index: 2, includesTime: true)

        // Returning to the area chart animates its horizontal range independently of the pie's selected point.
        controller.didTapZoomOut()
        #expect(controller.transitionRenderer.visiblePieComponents.map(\.value) == [70, 30])
        settleAnimations()
        #expect(fixture.title == "range")

        controller.didTapZoomIn(date: fixture.dates[1], animated: false)
        try expectSelection(fixture, index: 1, includesTime: true)
        controller.didTapToday()
        settleAnimations()
        try expectSelection(fixture, index: 4, includesTime: true)
        #expect(!controller.isTodayButtonEnabled)
    }

    @Test
    func zeroSampleStaysZeroAndHiddenAssetsStayHidden() throws {
        let fixture = makeFixture(values: [[90, 80, 0, 60, 10], [10, 20, 0, 40, 90]])
        let controller = fixture.controller
        controller.showPieForCurrentRange(animated: false)
        controller.updateChartRange(0.5...0.5, animated: false)
        try expectSelection(fixture, index: 2, includesTime: true)

        controller.updateChartsVisibility(visibility: [false, true], animated: false)
        controller.didTapToday()
        settleAnimations()
        #expect(controller.pieController.pieChartRenderer.currentlyVisibleData.map(\.value) == [0, 90])
        #expect(controller.pieController.chartDetailsViewModel(segmentInde: 1).values.first?.value == "USD 90")
        #expect(controller.actualChartVisibility == [false, true])
    }

    @Test
    func aSingleSampleCanBeSelected() throws {
        let fixture = makeFixture(offsets: [0], values: [[10], [90]])
        fixture.controller.showPieForCurrentRange(animated: false)
        try expectSelection(fixture, index: 0, includesTime: true)
        fixture.controller.updateChartRange(0...0, animated: false)
        try expectSelection(fixture, index: 0, includesTime: true)
        #expect(!fixture.controller.isTodayButtonEnabled)
    }

    @Test
    func chartViewUpdatesItsHeaderAndMinimapTogether() throws {
        let fixture = makeFixture()
        let controller = fixture.controller
        let view = ChartContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, HH:mm"
        let strings = ChartStrings(
            zoomOut: "All Time", total: "Total", revenueInTon: "", revenueInStars: "", revenueInUsd: "",
            dateTextFormatter: ChartDateTextFormatter(
                rangeTitle: { from, to in "\(formatter.string(from: from)) – \(formatter.string(from: to))" },
                singleDate: { formatter.string(from: $0) },
                singleDateTime: { formatter.string(from: $0) }
            )
        )
        view.apply(theme: .extractedDayTheme, strings: strings, animated: false)
        view.setup(controller: controller, noInitialZoom: true)
        view.layoutIfNeeded()
        view.setPieVisible(true, animated: false)
        let rangeView = try #require(descendants(of: view).compactMap { $0 as? RangeChartView }.first)
        // Offscreen containers defer child theming; apply it synchronously for deterministic captures.
        rangeView.apply(theme: .extractedDayTheme, strings: strings, animated: false)

        for index in [4, 0, 2] {
            let fraction = CGFloat(index) / 4
            // Exercise the callback used by actual minimap gestures and the header update wiring.
            rangeView.rangeDidChangeClosure?(fraction...fraction)
            settleAnimations()
            layoutAndDisplay(view)
            let labels = descendants(of: view).compactMap { ($0 as? UILabel)?.text }
            #expect(labels.contains(formatter.string(from: fixture.dates[index])))
            #expect(controller.selectedRangePointFraction == fraction)
            #expect(rangeView.lowerBound == fraction)
            #expect(rangeView.upperBound == fraction)
            #expect(controller.pieController.pieChartRenderer.currentlyVisibleData.map(\.value) == fixture.values.map { CGFloat($0[index]) })
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
            let png = try #require(image.pngData())
            Attachment.record(Array(png), named: "portfolio-selected-sample-\(index).png")
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func layoutAndDisplay(_ view: UIView) {
        view.layoutIfNeeded()
        view.layer.displayIfNeeded()
        view.subviews.forEach(layoutAndDisplay)
    }

    private final class Fixture {
        let controller: PercentPieChartController
        let dates: [Date]
        let values: [[Double]]
        var title = ""
        var tooltip: ChartDetailsViewModel?

        init(controller: PercentPieChartController, dates: [Date], values: [[Double]]) {
            self.controller = controller
            self.dates = dates
            self.values = values
        }
    }

    private func makeFixture(
        spacing: TimeInterval = 300,
        offsets: [TimeInterval]? = nil,
        values: [[Double]] = [[90, 80, 70, 60, 10], [10, 20, 30, 40, 90]],
        fullRangePreview: Bool = true
    ) -> Fixture {
        let dates = (offsets ?? (0..<5).map { Double($0) * spacing }).map { Date(timeIntervalSince1970: start + $0) }
        let controller = PercentPieChartController(chartsCollection: ChartsCollection(
            axisValues: dates,
            chartValues: values.enumerated().map {
                ChartsCollection.Chart(color: $0.offset == 0 ? .red : .blue, name: "Asset \($0.offset)", values: $0.element)
            }
        ))
        controller.chartFrame = { CGRect(x: 16, y: 0, width: 288, height: 180) }
        controller.cartViewBounds = { CGRect(x: 0, y: 0, width: 320, height: 180) }
        controller.keepsFullRangePreviewWhenZoomed = fullRangePreview
        controller.detailsValueTextProvider = { "USD \(Int($0.rawValue))" }
        controller.apply(theme: .extractedDayTheme, strings: ChartStrings(
            zoomOut: "Zoom Out", total: "Total", revenueInTon: "", revenueInStars: "", revenueInUsd: "",
            dateTextFormatter: ChartDateTextFormatter(
                rangeTitle: { _, _ in "range" },
                singleDate: { "date:\(Int($0.timeIntervalSince1970))" },
                singleDateTime: { "time:\(Int($0.timeIntervalSince1970))" }
            )
        ), animated: false)
        let fixture = Fixture(controller: controller, dates: dates, values: values)
        controller.setChartTitleClosure = { [weak fixture] title, _ in fixture?.title = title }
        controller.initializeChart()
        return fixture
    }

    private func expectSelection(_ fixture: Fixture, index: Int, includesTime: Bool) throws {
        let expectedValues = fixture.values.map { CGFloat($0[index]) }
        let renderedValues = fixture.controller.pieController.pieChartRenderer.currentlyVisibleData.map(\.value)
        #expect(renderedValues == expectedValues)
        #expect(fixture.title == "\(includesTime ? "time" : "date"):\(Int(fixture.dates[index].timeIntervalSince1970))")
        let total = renderedValues.reduce(0, +)
        if total > 0 {
            #expect(renderedValues[0] / total == expectedValues[0] / expectedValues.reduce(0, +))
        }
        for assetIndex in fixture.values.indices {
            let tooltip = fixture.controller.pieController.chartDetailsViewModel(segmentInde: assetIndex)
            #expect(tooltip.values.first?.value == "USD \(Int(fixture.values[assetIndex][index]))")
        }
    }

    private func settleAnimations() {
        for listener in DisplayLinkService.shared.listners.allObjects {
            (listener as? DisplayLinkListner)?.update(delta: .defaultDuration + 1)
        }
    }
}

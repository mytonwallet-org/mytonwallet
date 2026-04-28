import Foundation
import UIKit
import GraphKit

enum PortfolioChartAdapterError: Error {
    case noActiveDatasets
    case unableToCreateController
    case missingSampleData
}

enum PortfolioChartAdapter {
    struct Configuration {
        var maxSeriesCount: Int
        var includeOtherSeries: Bool

        init(maxSeriesCount: Int = 8, includeOtherSeries: Bool = true) {
            self.maxSeriesCount = max(1, maxSeriesCount)
            self.includeOtherSeries = includeOtherSeries
        }
    }

    private struct PortfolioResponse: Decodable {
        let datasets: [Dataset]
        let base: String
        let density: String
    }

    private struct Dataset: Decodable {
        struct Point: Decodable {
            let timestamp: TimeInterval
            let value: Double

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                self.timestamp = try container.decode(TimeInterval.self)
                self.value = try container.decode(Double.self)
            }
        }

        let assetId: Int
        let symbol: String
        let contractAddress: String
        let points: [Point]
        let impact: Double

        var latestValue: Double {
            points.last?.value ?? 0.0
        }

        var hasPositiveValues: Bool {
            points.contains(where: { $0.value > 0.0 })
        }
    }

    private struct Series {
        let id: String
        let name: String
        let color: String
        let values: [Double]
    }

    private static let palette: [String] = [
        "#2E86DE",
        "#10AC84",
        "#FF9F43",
        "#EE5253",
        "#5F27CD",
        "#00C2D1",
        "#F368E0",
        "#576574",
        "#A3CB38",
        "#FF6B6B"
    ]

    static func makeChartJSON(
        from data: Data,
        configuration: Configuration = Configuration(),
        percentageBased: Bool = true
    ) throws -> String {
        let response = try JSONDecoder().decode(PortfolioResponse.self, from: data)
        let activeDatasets = response.datasets
            .filter { $0.impact > 0.0 || $0.hasPositiveValues }
            .sorted {
                if $0.impact == $1.impact {
                    return $0.latestValue > $1.latestValue
                }
                return $0.impact > $1.impact
            }

        guard !activeDatasets.isEmpty else {
            throw PortfolioChartAdapterError.noActiveDatasets
        }

        let selectedCount: Int
        if configuration.includeOtherSeries && activeDatasets.count > configuration.maxSeriesCount {
            selectedCount = max(1, configuration.maxSeriesCount - 1)
        } else {
            selectedCount = min(configuration.maxSeriesCount, activeDatasets.count)
        }

        let selectedDatasets = Array(activeDatasets.prefix(selectedCount))
        let remainingDatasets = Array(activeDatasets.dropFirst(selectedCount))

        let selectedTimestamps = selectedDatasets.flatMap(\.points).map(\.timestamp)
        let remainingTimestamps = remainingDatasets.flatMap(\.points).map(\.timestamp)
        let allTimestamps = Array(Set(selectedTimestamps + remainingTimestamps)).sorted()

        func makeValueMap(for dataset: Dataset) -> [TimeInterval: Double] {
            Dictionary(uniqueKeysWithValues: dataset.points.map { ($0.timestamp, $0.value) })
        }

        let selectedSeries: [Series] = selectedDatasets.enumerated().map { index, dataset in
            let valuesByTimestamp = makeValueMap(for: dataset)
            return Series(
                id: "y\(index)",
                name: dataset.symbol,
                color: palette[index % palette.count],
                values: allTimestamps.map { valuesByTimestamp[$0] ?? 0.0 }
            )
        }

        var series = selectedSeries

        if configuration.includeOtherSeries && !remainingDatasets.isEmpty {
            let remainderMaps = remainingDatasets.map { makeValueMap(for: $0) }
            let otherValues = allTimestamps.map { timestamp in
                remainderMaps.reduce(0.0) { partialResult, map in
                    partialResult + (map[timestamp] ?? 0.0)
                }
            }
            if otherValues.contains(where: { $0 > 0.0 }) {
                series.append(
                    Series(
                        id: "y\(series.count)",
                        name: "Other",
                        color: "#95A5A6",
                        values: otherValues
                    )
                )
            }
        }

        var xColumn: [Any] = ["x"]
        xColumn.append(contentsOf: allTimestamps.map { Int64($0.rounded()) * 1000 as Any })

        let dataColumns: [[Any]] = series.map { series in
            var column: [Any] = [series.id]
            column.append(contentsOf: series.values.map { $0 as Any })
            return column
        }

        let types = Dictionary(uniqueKeysWithValues: series.map { ($0.id, "area") })
            .merging(["x": "x"]) { current, _ in current }
        let names = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.name) })
        let colors = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.color) })

        let chartPayload: [String: Any] = [
            "columns": [xColumn] + dataColumns,
            "types": types,
            "names": names,
            "colors": colors,
            "stacked": true,
            "percentage": percentageBased
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: chartPayload, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: jsonData, as: UTF8.self)
    }

    static func makeChartController(
        from data: Data,
        type: ChartType = .pie,
        configuration: Configuration = Configuration()
    ) throws -> BaseChartController {
        let percentageBased: Bool
        switch type {
        case .pie, .area:
            percentageBased = true
        default:
            percentageBased = false
        }

        let chartJSON = try makeChartJSON(
            from: data,
            configuration: configuration,
            percentageBased: percentageBased
        )
        guard let controller = createChartController(chartJSON, type: type) else {
            throw PortfolioChartAdapterError.unableToCreateController
        }
        return controller
    }

    static func loadSampleData() throws -> Data {
        guard let url = Bundle.main.url(forResource: "portfolio-data", withExtension: "json") else {
            throw PortfolioChartAdapterError.missingSampleData
        }
        return try Data(contentsOf: url)
    }

    static func makeSampleChartController(
        type: ChartType = .pie,
        configuration: Configuration = Configuration()
    ) throws -> BaseChartController {
        try makeChartController(from: loadSampleData(), type: type, configuration: configuration)
    }
}

final class PortfolioCompositionDemoViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let absoluteSectionTitleLabel = UILabel()
    private let absoluteSectionSubtitleLabel = UILabel()
    private let absoluteChartView = ChartContainerView()
    private let comparisonSectionTitleLabel = UILabel()
    private let comparisonSectionSubtitleLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["Pie", "Area"])
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let errorLabel = UILabel()
    private let comparisonChartView = ChartContainerView()
    private var absoluteChartHeight: CGFloat = 480.0
    private var comparisonChartHeight: CGFloat = 480.0
    private var isUpdatingModeControl = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        titleLabel.font = UIFont.systemFont(ofSize: 28.0, weight: .bold)
        titleLabel.text = "Portfolio Composition"
        titleLabel.numberOfLines = 0

        subtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "Same history shown as total value and as share of portfolio."

        absoluteSectionTitleLabel.font = UIFont.systemFont(ofSize: 21.0, weight: .semibold)
        absoluteSectionTitleLabel.numberOfLines = 0
        absoluteSectionTitleLabel.text = "Total Value"

        absoluteSectionSubtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        absoluteSectionSubtitleLabel.textColor = .secondaryLabel
        absoluteSectionSubtitleLabel.numberOfLines = 0
        absoluteSectionSubtitleLabel.text = "Stacked area by account value."

        comparisonSectionTitleLabel.font = UIFont.systemFont(ofSize: 21.0, weight: .semibold)
        comparisonSectionTitleLabel.numberOfLines = 0
        comparisonSectionTitleLabel.text = "Portfolio Share"

        comparisonSectionSubtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        comparisonSectionSubtitleLabel.textColor = .secondaryLabel
        comparisonSectionSubtitleLabel.numberOfLines = 0
        comparisonSectionSubtitleLabel.text = "Pie and percentage area from the same data."

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        errorLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        absoluteChartView.apply(animated: false)

        comparisonChartView.apply(animated: false)
        comparisonChartView.zoomStateChanged = { [weak self] isPieVisible in
            guard let self else {
                return
            }
            self.isUpdatingModeControl = true
            self.modeControl.selectedSegmentIndex = isPieVisible ? 0 : 1
            self.isUpdatingModeControl = false
        }

        view.addSubview(scrollView)
        scrollView.addSubview(titleLabel)
        scrollView.addSubview(subtitleLabel)
        scrollView.addSubview(absoluteSectionTitleLabel)
        scrollView.addSubview(absoluteSectionSubtitleLabel)
        scrollView.addSubview(absoluteChartView)
        scrollView.addSubview(comparisonSectionTitleLabel)
        scrollView.addSubview(comparisonSectionSubtitleLabel)
        scrollView.addSubview(modeControl)
        scrollView.addSubview(comparisonChartView)
        scrollView.addSubview(errorLabel)

        loadCharts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        scrollView.frame = view.bounds

        let insets = view.safeAreaInsets
        let contentWidth = max(320.0, view.bounds.width - 32.0)
        let x = floor((view.bounds.width - contentWidth) / 2.0)

        let titleSize = titleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        titleLabel.frame = CGRect(x: x, y: insets.top + 20.0, width: contentWidth, height: titleSize.height)

        let subtitleSize = subtitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        subtitleLabel.frame = CGRect(x: x, y: titleLabel.frame.maxY + 10.0, width: contentWidth, height: subtitleSize.height)

        let absoluteSectionTitleSize = absoluteSectionTitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        absoluteSectionTitleLabel.frame = CGRect(
            x: x,
            y: subtitleLabel.frame.maxY + 24.0,
            width: contentWidth,
            height: absoluteSectionTitleSize.height
        )

        let absoluteSectionSubtitleSize = absoluteSectionSubtitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        absoluteSectionSubtitleLabel.frame = CGRect(
            x: x,
            y: absoluteSectionTitleLabel.frame.maxY + 8.0,
            width: contentWidth,
            height: absoluteSectionSubtitleSize.height
        )

        absoluteChartHeight = absoluteChartView.preferredHeight(for: contentWidth)
        absoluteChartView.frame = CGRect(
            x: x,
            y: absoluteSectionSubtitleLabel.frame.maxY + 16.0,
            width: contentWidth,
            height: absoluteChartHeight
        )

        let comparisonSectionTitleSize = comparisonSectionTitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        comparisonSectionTitleLabel.frame = CGRect(
            x: x,
            y: absoluteChartView.frame.maxY + 28.0,
            width: contentWidth,
            height: comparisonSectionTitleSize.height
        )

        let comparisonSectionSubtitleSize = comparisonSectionSubtitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        comparisonSectionSubtitleLabel.frame = CGRect(
            x: x,
            y: comparisonSectionTitleLabel.frame.maxY + 8.0,
            width: contentWidth,
            height: comparisonSectionSubtitleSize.height
        )

        modeControl.frame = CGRect(
            x: x,
            y: comparisonSectionSubtitleLabel.frame.maxY + 16.0,
            width: min(220.0, contentWidth),
            height: 32.0
        )

        comparisonChartHeight = comparisonChartView.preferredHeight(for: contentWidth)
        comparisonChartView.frame = CGRect(
            x: x,
            y: modeControl.frame.maxY + 16.0,
            width: contentWidth,
            height: comparisonChartHeight
        )

        let errorSize = errorLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        errorLabel.frame = CGRect(x: x, y: comparisonChartView.frame.maxY + 16.0, width: contentWidth, height: errorSize.height)

        let contentHeight = errorLabel.frame.maxY + 24.0
        scrollView.contentSize = CGSize(width: view.bounds.width, height: contentHeight)
        scrollView.isScrollEnabled = contentHeight > view.bounds.height + 1.0
    }

    @objc private func modeChanged() {
        guard !isUpdatingModeControl else {
            return
        }

        let showsPie = modeControl.selectedSegmentIndex == 0
        comparisonChartView.setPieVisible(showsPie)
    }

    private func loadCharts() {
        var errors: [String] = []

        do {
            let controller = try PortfolioChartAdapter.makeSampleChartController(type: .absoluteArea)
            absoluteChartView.apply(animated: false)
            absoluteChartView.setup(controller: controller)
        } catch {
            errors.append("Unable to load total value chart: \(error)")
        }

        do {
            let controller = try PortfolioChartAdapter.makeSampleChartController(type: .pie)
            (controller as? PercentPieChartController)?.keepsFullRangePreviewWhenZoomed = true
            comparisonChartView.apply(animated: false)
            comparisonChartView.setup(controller: controller)
        } catch {
            errors.append("Unable to load portfolio share chart: \(error)")
        }

        errorLabel.text = errors.joined(separator: "\n")
        errorLabel.isHidden = errors.isEmpty

        view.setNeedsLayout()
    }
}

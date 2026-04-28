import Foundation
import GraphKit
import WalletCore
import WalletContext

enum PortfolioGraphKitAdapterError: Error {
    case noActiveDatasets
}

enum PortfolioGraphKitAdapter {
    struct ChartPresentation: Sendable {
        let json: String
        let limitedHistoryFraction: Double?
        let baseCurrency: MBaseCurrency

        var detailsValueTextProvider: ChartDetailsValueTextProvider {
            { item in
                formatValue(item.rawValue, baseCurrency: baseCurrency)
            }
        }
    }

    struct PreparedCharts: Sendable {
        let hasChartData: Bool
        let totalValuePresentation: ChartPresentation?
        let portfolioSharePresentation: ChartPresentation?

        static let empty = PreparedCharts(
            hasChartData: false,
            totalValuePresentation: nil,
            portfolioSharePresentation: nil
        )
    }

    struct Configuration: Sendable {
        var maxSeriesCount: Int?
        var includeOtherSeries: Bool

        init(maxSeriesCount: Int? = 8, includeOtherSeries: Bool = true) {
            self.maxSeriesCount = maxSeriesCount.map { max(1, $0) }
            self.includeOtherSeries = includeOtherSeries
        }
    }

    private struct DatasetSummary {
        let dataset: ApiPortfolioHistoryDataset
        let latestValue: Double
        let impact: Double
        let hasPositiveValues: Bool

        init(dataset: ApiPortfolioHistoryDataset) {
            self.dataset = dataset
            self.latestValue = dataset.points.last(where: { $0.count >= 2 })?[1] ?? 0
            self.impact = dataset.impact ?? 0
            self.hasPositiveValues = dataset.points.contains(where: { $0.count >= 2 && $0[1] > 0 })
        }
    }

    private struct Series {
        let id: String
        let name: String
        let color: String
        let values: [Double]
    }

    static func makePreparedCharts(
        from response: ApiPortfolioHistoryResponse?,
        configuration: Configuration = Configuration()
    ) -> PreparedCharts {
        guard let response else {
            return .empty
        }

        let chartResponse = makeChartResponse(from: response)
        let hasChartData = chartResponse.points?.isEmpty == false

        return PreparedCharts(
            hasChartData: hasChartData,
            totalValuePresentation: try? makeChartPresentation(
                from: chartResponse,
                configuration: configuration,
                percentageBased: false
            ),
            portfolioSharePresentation: try? makeChartPresentation(
                from: chartResponse,
                configuration: configuration,
                percentageBased: true
            )
        )
    }

    static func makeChartPresentation(
        from response: ApiPortfolioHistoryResponse,
        configuration: Configuration = Configuration(),
        percentageBased: Bool
    ) throws -> ChartPresentation {
        let activeDatasets = (response.datasets ?? [])
            .map(DatasetSummary.init)
            .filter { $0.impact > 0 || $0.hasPositiveValues }
            .sorted {
                if $0.impact == $1.impact {
                    return $0.latestValue > $1.latestValue
                }
                return $0.impact > $1.impact
            }

        guard !activeDatasets.isEmpty else {
            throw PortfolioGraphKitAdapterError.noActiveDatasets
        }

        let selectedCount: Int
        if let maxSeriesCount = configuration.maxSeriesCount {
            if configuration.includeOtherSeries && activeDatasets.count > maxSeriesCount {
                selectedCount = max(1, maxSeriesCount - 1)
            } else {
                selectedCount = min(maxSeriesCount, activeDatasets.count)
            }
        } else {
            selectedCount = activeDatasets.count
        }

        let selectedDatasets = Array(activeDatasets.prefix(selectedCount))
        let remainingDatasets = Array(activeDatasets.dropFirst(selectedCount))

        let allTimestamps = Array(
            Set((selectedDatasets + remainingDatasets).flatMap { datasetSummary in
                datasetSummary.dataset.points.compactMap(timestamp(from:))
            })
        ).sorted()

        guard !allTimestamps.isEmpty else {
            throw PortfolioGraphKitAdapterError.noActiveDatasets
        }

        var nextDefaultColor = 0
        var series = selectedDatasets.enumerated().map { index, datasetSummary in
            let dataset = datasetSummary.dataset
            let valuesByTimestamp = makeValueMap(for: dataset)
            let color = color(for: dataset, nextDefaultColor: &nextDefaultColor)

            return Series(
                id: "y\(index)",
                name: displayName(for: dataset),
                color: color,
                values: allTimestamps.map { valuesByTimestamp[$0] ?? 0 }
            )
        }

        if configuration.includeOtherSeries && !remainingDatasets.isEmpty {
            let remainingMaps = remainingDatasets.map { makeValueMap(for: $0.dataset) }
            let otherValues = allTimestamps.map { timestamp in
                remainingMaps.reduce(0) { partialResult, valuesByTimestamp in
                    partialResult + (valuesByTimestamp[timestamp] ?? 0)
                }
            }

            if otherValues.contains(where: { $0 > 0 }) {
                series.append(
                    Series(
                        id: "y\(series.count)",
                        name: lang("Other"),
                        color: PortfolioPalette.defaultColors[nextDefaultColor % PortfolioPalette.defaultColors.count],
                        values: otherValues
                    )
                )
                nextDefaultColor += 1
            }
        }

        var xColumn: [Any] = ["x"]
        xColumn.append(contentsOf: allTimestamps.map { Int64(($0 * 1000).rounded()) as Any })

        let dataColumns = series.map { series -> [Any] in
            var column: [Any] = [series.id]
            column.append(contentsOf: series.values.map { $0 as Any })
            return column
        }

        let types = Dictionary(uniqueKeysWithValues: series.map { ($0.id, "area") })
            .merging(["x": "x"]) { current, _ in current }
        let names = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.name) })
        let colors = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.color) })

        let payload: [String: Any] = [
            "columns": [xColumn] + dataColumns,
            "types": types,
            "names": names,
            "colors": colors,
            "stacked": true,
            "percentage": percentageBased,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let baseCurrency = MBaseCurrency(rawValue: response.base.uppercased()) ?? DEFAULT_PRICE_CURRENCY

        return ChartPresentation(
            json: String(decoding: jsonData, as: UTF8.self),
            limitedHistoryFraction: makeLimitedHistoryFraction(
                historyScanCursor: response.historyScanCursor,
                timestamps: allTimestamps
            ),
            baseCurrency: baseCurrency
        )
    }

    private static func makeChartResponse(from response: ApiPortfolioHistoryResponse) -> ApiPortfolioHistoryResponse {
        let chartDatasets = (response.datasets ?? []).filter { dataset in
            dataset.points.contains(where: { $0.count >= 2 && $0[1] > 0 })
        }

        return ApiPortfolioHistoryResponse(
            status: response.status,
            points: mergePoints(from: chartDatasets),
            datasets: chartDatasets,
            base: response.base,
            density: response.density,
            historyScanCursor: response.historyScanCursor,
            assetLimitExceeded: response.assetLimitExceeded
        )
    }

    private static func makeValueMap(for dataset: ApiPortfolioHistoryDataset) -> [TimeInterval: Double] {
        var valuesByTimestamp: [TimeInterval: Double] = [:]

        for point in dataset.points {
            guard let timestamp = timestamp(from: point),
                  let value = value(from: point)
            else {
                continue
            }

            valuesByTimestamp[timestamp] = value
        }

        return valuesByTimestamp
    }

    private static func mergePoints(from datasets: [ApiPortfolioHistoryDataset]) -> ApiHistoryList? {
        guard !datasets.isEmpty else {
            return nil
        }

        var valuesByTimestamp: [Double: Double] = [:]

        for dataset in datasets {
            for point in dataset.points where point.count >= 2 {
                valuesByTimestamp[point[0], default: 0] += point[1]
            }
        }

        return valuesByTimestamp
            .map { [$0.key, $0.value] }
            .sorted { $0[0] < $1[0] }
    }

    private static func displayName(for dataset: ApiPortfolioHistoryDataset) -> String {
        if !dataset.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dataset.symbol
        }

        let contractAddress = dataset.contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contractAddress.isEmpty {
            return contractAddress
        }

        return lang("Asset %1$@", arg1: "\(dataset.assetId)")
    }

    private static func color(for dataset: ApiPortfolioHistoryDataset, nextDefaultColor: inout Int) -> String {
        if let color = PortfolioPalette.normalize(color: dataset.color) {
            return color
        }

        let color = PortfolioPalette.defaultColors[nextDefaultColor % PortfolioPalette.defaultColors.count]
        nextDefaultColor += 1
        return color
    }

    private static func timestamp(from point: [Double]) -> TimeInterval? {
        guard point.count >= 2 else {
            return nil
        }

        return point[0]
    }

    private static func makeLimitedHistoryFraction(
        historyScanCursor: Double?,
        timestamps: [TimeInterval]
    ) -> Double? {
        guard let historyScanCursor,
              timestamps.count > 1,
              let index = timestamps.firstIndex(where: { $0 >= historyScanCursor }),
              index > 0
        else {
            return nil
        }

        return Double(index) / Double(timestamps.count - 1)
    }

    private static func value(from point: [Double]) -> Double? {
        guard point.count >= 2 else {
            return nil
        }

        return point[1]
    }

    private static func formatValue(_ value: Double, baseCurrency: MBaseCurrency) -> String {
        BaseCurrencyAmount.fromDouble(value, baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
    }
}

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
        private let valueFormat: ValueFormat

        init(
            json: String,
            limitedHistoryFraction: Double?,
            baseCurrency: MBaseCurrency,
            valueFormat: ValueFormat
        ) {
            self.json = json
            self.limitedHistoryFraction = limitedHistoryFraction
            self.baseCurrency = baseCurrency
            self.valueFormat = valueFormat
        }

        var detailsValueTextProvider: ChartDetailsValueTextProvider {
            { item in
                formatValue(item.rawValue, baseCurrency: baseCurrency, valueFormat: valueFormat)
            }
        }
    }

    struct PreparedCharts: Sendable {
        let hasChartData: Bool
        let totalValuePresentation: ChartPresentation?
        let totalPnlPresentation: ChartPresentation?
        let dailyPnlPresentation: ChartPresentation?
        let portfolioSharePresentation: ChartPresentation?

        static let empty = PreparedCharts(
            hasChartData: false,
            totalValuePresentation: nil,
            totalPnlPresentation: nil,
            dailyPnlPresentation: nil,
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

    private enum ChartStyle {
        case area
        case line
        case bar

        var columnType: String {
            switch self {
            case .area:
                return "area"
            case .line:
                return "line"
            case .bar:
                return "bar"
            }
        }

        var isStacked: Bool {
            switch self {
            case .area, .bar:
                return true
            case .line:
                return false
            }
        }
    }

    private enum DatasetSelection {
        case portfolioValue
        case signedValues
    }

    enum ValueFormat: Sendable {
        case currency
        case signedCurrency
    }

    private struct DatasetSummary {
        let dataset: ApiPortfolioHistoryDataset
        let latestValue: Double
        let impact: Double
        let hasValues: Bool
        let hasPositiveValues: Bool

        init(dataset: ApiPortfolioHistoryDataset) {
            self.dataset = dataset
            self.latestValue = dataset.points.reversed().compactMap(Self.value(from:)).first ?? 0
            self.impact = dataset.impact ?? 0
            self.hasValues = dataset.points.contains { Self.value(from: $0) != nil }
            self.hasPositiveValues = dataset.points.contains { (Self.value(from: $0) ?? 0) > 0 }
        }

        private static func value(from point: [Double?]) -> Double? {
            guard point.count >= 2 else {
                return nil
            }

            return point[1]
        }
    }

    private final class ColorResolver {
        private var colorByKey: [String: String] = [:]
        private var nextDefaultColor = 0

        func color(for dataset: ApiPortfolioHistoryDataset) -> String {
            if let color = PortfolioPalette.normalize(color: dataset.color) {
                return color
            }

            let key = PortfolioGraphKitAdapter.displayName(for: dataset)
            if let color = colorByKey[key] {
                return color
            }

            let color = nextColor()
            colorByKey[key] = color
            return color
        }

        func nextColor() -> String {
            let color = PortfolioPalette.defaultColors[nextDefaultColor % PortfolioPalette.defaultColors.count]
            nextDefaultColor += 1
            return color
        }
    }

    private struct Series {
        let id: String
        let name: String
        let color: String
        let values: [Double]
    }

    static func makePreparedCharts(
        from responses: PortfolioHistoryResponses?,
        configuration: Configuration = Configuration()
    ) -> PreparedCharts {
        guard let responses else {
            return .empty
        }

        let colorResolver = ColorResolver()
        let netWorthChartResponse = makeChartResponse(from: responses.netWorth)
        let totalValuePresentation = try? makeChartPresentation(
            from: netWorthChartResponse,
            configuration: configuration,
            style: .area,
            percentageBased: false,
            datasetSelection: .portfolioValue,
            valueFormat: .currency,
            colorResolver: colorResolver
        )
        let totalPnlPresentation = try? makeChartPresentation(
            from: responses.pnlCumulative,
            configuration: configuration,
            style: .line,
            percentageBased: false,
            datasetSelection: .signedValues,
            valueFormat: .signedCurrency,
            colorResolver: colorResolver
        )
        let dailyPnlPresentation = try? makeChartPresentation(
            from: responses.pnl,
            configuration: configuration,
            style: .bar,
            percentageBased: false,
            datasetSelection: .signedValues,
            valueFormat: .signedCurrency,
            colorResolver: colorResolver
        )
        let portfolioSharePresentation = try? makeChartPresentation(
            from: netWorthChartResponse,
            configuration: configuration,
            style: .area,
            percentageBased: true,
            datasetSelection: .portfolioValue,
            valueFormat: .currency,
            colorResolver: colorResolver
        )
        let hasChartData = [
            totalValuePresentation,
            totalPnlPresentation,
            dailyPnlPresentation,
            portfolioSharePresentation,
        ].contains { $0 != nil }

        return PreparedCharts(
            hasChartData: hasChartData,
            totalValuePresentation: totalValuePresentation,
            totalPnlPresentation: totalPnlPresentation,
            dailyPnlPresentation: dailyPnlPresentation,
            portfolioSharePresentation: portfolioSharePresentation
        )
    }

    private static func makeChartPresentation(
        from response: ApiPortfolioHistoryResponse,
        configuration: Configuration = Configuration(),
        style: ChartStyle,
        percentageBased: Bool,
        datasetSelection: DatasetSelection,
        valueFormat: ValueFormat,
        colorResolver: ColorResolver = ColorResolver()
    ) throws -> ChartPresentation {
        let activeDatasets = makeActiveDatasets(from: response, selection: datasetSelection)

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

        var series = selectedDatasets.enumerated().map { index, datasetSummary in
            let dataset = datasetSummary.dataset
            let valuesByTimestamp = makeValueMap(for: dataset)
            let color = colorResolver.color(for: dataset)

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

            let hasOtherValues: Bool
            switch datasetSelection {
            case .portfolioValue:
                hasOtherValues = otherValues.contains(where: { $0 > 0 })
            case .signedValues:
                hasOtherValues = otherValues.contains(where: { $0 != 0 })
            }

            if hasOtherValues {
                series.append(
                    Series(
                        id: "y\(series.count)",
                        name: lang("Other"),
                        color: colorResolver.nextColor(),
                        values: otherValues
                    )
                )
            }
        }

        guard !series.isEmpty else {
            throw PortfolioGraphKitAdapterError.noActiveDatasets
        }

        var xColumn: [Any] = ["x"]
        xColumn.append(contentsOf: allTimestamps.map { Int64(($0 * 1000).rounded()) as Any })

        let dataColumns = series.map { series -> [Any] in
            var column: [Any] = [series.id]
            column.append(contentsOf: series.values.map { $0 as Any })
            return column
        }

        let types = Dictionary(uniqueKeysWithValues: series.map { ($0.id, style.columnType) })
            .merging(["x": "x"]) { current, _ in current }
        let names = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.name) })
        let colors = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.color) })

        let payload: [String: Any] = [
            "columns": [xColumn] + dataColumns,
            "types": types,
            "names": names,
            "colors": colors,
            "stacked": style.isStacked,
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
            baseCurrency: baseCurrency,
            valueFormat: valueFormat
        )
    }

    private static func makeActiveDatasets(
        from response: ApiPortfolioHistoryResponse,
        selection: DatasetSelection
    ) -> [DatasetSummary] {
        let datasetSummaries = (response.datasets ?? []).map(DatasetSummary.init)

        switch selection {
        case .portfolioValue:
            return datasetSummaries
                .filter { $0.impact > 0 || $0.hasPositiveValues }
                .sorted {
                    if $0.impact == $1.impact {
                        return $0.latestValue > $1.latestValue
                    }
                    return $0.impact > $1.impact
                }
        case .signedValues:
            return datasetSummaries.filter(\.hasValues)
        }
    }

    private static func makeChartResponse(from response: ApiPortfolioHistoryResponse) -> ApiPortfolioHistoryResponse {
        let chartDatasets = (response.datasets ?? []).filter { dataset in
            dataset.points.contains(where: { (value(from: $0) ?? 0) > 0 })
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

    private static func mergePoints(from datasets: [ApiPortfolioHistoryDataset]) -> ApiPortfolioHistoryList? {
        guard !datasets.isEmpty else {
            return nil
        }

        var valuesByTimestamp: [Double: Double] = [:]

        for dataset in datasets {
            for point in dataset.points {
                guard let timestamp = timestamp(from: point),
                      let value = value(from: point)
                else {
                    continue
                }

                valuesByTimestamp[timestamp, default: 0] += value
            }
        }

        return valuesByTimestamp
            .map { [$0.key as Double?, $0.value as Double?] }
            .sorted { ($0[0] ?? 0) < ($1[0] ?? 0) }
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

    private static func timestamp(from point: [Double?]) -> TimeInterval? {
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

    private static func value(from point: [Double?]) -> Double? {
        guard point.count >= 2 else {
            return nil
        }

        return point[1]
    }

    private static func formatValue(
        _ value: Double,
        baseCurrency: MBaseCurrency,
        valueFormat: ValueFormat
    ) -> String {
        let amount = BaseCurrencyAmount.fromDouble(value, baseCurrency)

        switch valueFormat {
        case .currency:
            return amount.formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        case .signedCurrency:
            return amount.formatted(
                .baseCurrencyEquivalent,
                showPlus: true,
                showMinus: true,
                roundHalfUp: true
            )
        }
    }
}

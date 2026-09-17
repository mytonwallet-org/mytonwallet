import Foundation
import Testing
import WalletCore
@testable import UIPortfolio

@Suite("Portfolio Chart Time Range")
struct PortfolioGraphKitAdapterTests {
    private let now = Date(timeIntervalSince1970: 1_789_393_500)

    @Test(arguments: ["5m", "1h", "4h", "1d"])
    func `all charts omit future null and zero points`(density: String) throws {
        let timestamp = now.timeIntervalSince1970
        let responses = try makeResponses(
            timestamps: [timestamp - 600, timestamp - 300, timestamp, timestamp + 300, timestamp + 600],
            netWorth: [10, 12, 13, nil, 0],
            cumulativePnl: [-2, 0, 3, nil, 0],
            pnl: [-1, 0, 1, nil, 0],
            density: density
        )

        let result = PortfolioGraphKitAdapter.makePreparedCharts(from: responses, now: now)

        #expect(result.hasChartData)
        let expectedTimestamps = [timestamp - 600, timestamp - 300, timestamp].map { $0 * 1000 }
        let expectations: [(PortfolioGraphKitAdapter.ChartPresentation?, [Double])] = [
            (result.totalValuePresentation, [10, 12, 13]),
            (result.totalPnlPresentation, [-2, 0, 3]),
            (result.dailyPnlPresentation, [-1, 0, 1]),
            (result.portfolioSharePresentation, [10, 12, 13]),
        ]
        for (presentation, expectedValues) in expectations {
            let columns = try columns(from: #require(presentation))
            #expect(columns[0] == expectedTimestamps)
            #expect(columns[1] == expectedValues)
        }
    }

    @Test
    func `future-only data does not produce charts`() throws {
        let timestamp = now.timeIntervalSince1970
        let responses = try makeResponses(
            timestamps: [timestamp + 300, timestamp + 600],
            netWorth: [10, 12],
            cumulativePnl: [-2, 3],
            pnl: [-1, 1]
        )

        let result = PortfolioGraphKitAdapter.makePreparedCharts(from: responses, now: now)

        #expect(!result.hasChartData)
        #expect(result.totalValuePresentation == nil)
        #expect(result.totalPnlPresentation == nil)
        #expect(result.dailyPnlPresentation == nil)
        #expect(result.portfolioSharePresentation == nil)
    }

    @Test
    func `history boundary uses the displayed time range`() throws {
        let timestamp = now.timeIntervalSince1970
        let responses = try makeResponses(
            timestamps: [timestamp - 600, timestamp - 300, timestamp, timestamp + 300, timestamp + 600],
            netWorth: [10, 12, 13, nil, nil],
            cumulativePnl: [-2, 0, 3, nil, nil],
            pnl: [-1, 0, 1, nil, nil],
            historyScanCursor: timestamp - 300
        )

        let result = PortfolioGraphKitAdapter.makePreparedCharts(from: responses, now: now)

        #expect(result.totalValuePresentation?.limitedHistoryFraction == 0.5)
        #expect(result.totalPnlPresentation?.limitedHistoryFraction == 0.5)
        #expect(result.dailyPnlPresentation?.limitedHistoryFraction == 0.5)
        #expect(result.portfolioSharePresentation?.limitedHistoryFraction == 0.5)
    }

    @Test
    func `historical data keeps its last point even when its value is zero`() throws {
        let timestamp = now.timeIntervalSince1970
        let responses = try makeResponses(
            timestamps: [timestamp - 600, timestamp - 300],
            netWorth: [10, 0],
            cumulativePnl: [-2, 0],
            pnl: [-1, 0]
        )

        let result = PortfolioGraphKitAdapter.makePreparedCharts(from: responses, now: now)

        for presentation in [result.totalValuePresentation, result.totalPnlPresentation,
                             result.dailyPnlPresentation, result.portfolioSharePresentation] {
            let columns = try columns(from: #require(presentation))
            #expect(columns[0] == [timestamp - 600, timestamp - 300].map { $0 * 1000 })
            #expect(columns[1].last == 0)
        }
    }

    private func makeResponses(
        timestamps: [TimeInterval],
        netWorth: [Double?],
        cumulativePnl: [Double?],
        pnl: [Double?],
        density: String = "5m",
        historyScanCursor: Double? = nil
    ) throws -> PortfolioHistoryResponses {
        func response(values: [Double?]) throws -> ApiPortfolioHistoryResponse {
            let points: ApiPortfolioHistoryList = zip(timestamps, values).map { [$0, $1] }
            let pointsJSON = String(decoding: try JSONEncoder().encode(points), as: UTF8.self)
            let datasetJSON = """
                {"assetId": 1, "symbol": "TON", "contractAddress": "", "points": \(pointsJSON)}
                """
            let dataset = try JSONDecoder().decode(ApiPortfolioHistoryDataset.self, from: Data(datasetJSON.utf8))
            return ApiPortfolioHistoryResponse(
                status: "ok",
                points: points,
                datasets: [dataset],
                base: "usd",
                density: density,
                historyScanCursor: historyScanCursor,
                isAssetLimitExceeded: false
            )
        }

        return try PortfolioHistoryResponses(
            netWorth: response(values: netWorth),
            pnlCumulative: response(values: cumulativePnl),
            pnl: response(values: pnl)
        )
    }

    private func columns(from presentation: PortfolioGraphKitAdapter.ChartPresentation) throws -> [[Double]] {
        let payload = try #require(JSONSerialization.jsonObject(with: Data(presentation.json.utf8)) as? [String: Any])
        let columns = try #require(payload["columns"] as? [[Any]])
        return try columns.map { column in
            try #require(Array(column.dropFirst()) as? [Double])
        }
    }
}

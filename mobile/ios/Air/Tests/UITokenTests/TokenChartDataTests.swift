import Testing
@testable import UIToken

@Suite("Token Chart Data")
struct TokenChartDataTests {
    @Test
    func `preview sampling repeatedly keeps even-indexed points`() throws {
        let data = (0...400).map { [Double($0), Double($0)] }

        let result = try #require(reduceNumberOfPoints(data, to: 200))

        #expect(result.count == 101)
        #expect(result.first == [0, 0])
        #expect(result.last == [400, 400])
    }

    @Test
    func `range scope includes points surrounding fractional bounds`() throws {
        let data = (0...10).map { [Double($0), Double($0)] }

        let result = try #require(scope(data: data, range: 0.25...0.75))
        let timestamps = result.map { $0[0] }
        let expectedTimestamps = Array(2...8).map(Double.init)

        #expect(timestamps == expectedTimestamps)
    }

    @Test
    func `full range keeps all expanded chart points`() throws {
        let data = (0...1_200).map { [Double($0), Double($0)] }

        let result = try #require(scope(data: data, range: 0...1))

        #expect(result.count == data.count)
    }

    @Test
    func `full range percent change uses token metadata`() throws {
        let data = [
            [1.0, 100.0],
            [2.0, 101.68],
        ]

        let result = tokenChartPercentChange(
            historyData: data,
            range: 0...1,
            tokenPercentChange24h: 4.3,
            shouldUseTokenPercentChange: true,
            fallbackPrice: 101.68
        )

        #expect(abs(try #require(result) - 0.043) < 0.000001)
    }

    @Test
    func `non-day full range percent change uses chart data`() throws {
        let data = [
            [1.0, 100.0],
            [2.0, 101.68],
        ]

        let result = tokenChartPercentChange(
            historyData: data,
            range: 0...1,
            tokenPercentChange24h: 4.3,
            shouldUseTokenPercentChange: false,
            fallbackPrice: 101.68
        )

        #expect(abs(try #require(result) - 0.0168) < 0.000001)
    }

    @Test
    func `scoped range percent change uses chart data`() throws {
        let data = [
            [0.0, 50.0],
            [1.0, 100.0],
            [2.0, 110.0],
            [3.0, 200.0],
        ]

        let result = tokenChartPercentChange(
            historyData: data,
            range: 0.25...0.75,
            tokenPercentChange24h: 4.3,
            shouldUseTokenPercentChange: true,
            fallbackPrice: 110.0
        )

        #expect(abs(try #require(result) - 0.1) < 0.000001)
    }
}

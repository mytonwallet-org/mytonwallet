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
}

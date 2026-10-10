import Foundation
import WalletCore
import XCTest
@testable import UIAssets

@MainActor
final class MarketPreparationTests: XCTestCase {
    func testAppearanceRetriesFailedPreparationAndReusesTheFreshResult() async throws {
        let response = try JSONDecoder().decode(ApiMarketAssetsResponse.self, from: Data(#"{"sections":[]}"#.utf8))
        let requests = Requests(response: response)
        let model = MarketScreenModel(langCode: "en", fetchAssets: { _ in
            try await requests.fetch()
        }, loadCachedAssets: { _ in response }, now: { Date(timeIntervalSince1970: 1000) })
        model.start()
        try await Task.sleep(for: .milliseconds(100))
        let preparedCount = await requests.count
        XCTAssertEqual(preparedCount, 1)

        model.refreshIfNeeded()
        model.refreshIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let retryCount = await requests.count
        XCTAssertEqual(retryCount, 2)

        model.refreshIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let reusedCount = await requests.count
        XCTAssertEqual(reusedCount, 2)
    }

    private actor Requests {
        let response: ApiMarketAssetsResponse
        private(set) var count = 0

        init(response: ApiMarketAssetsResponse) { self.response = response }

        func fetch() throws -> ApiMarketAssetsResponse {
            count += 1
            if count == 1 { throw Failure.offline }
            return response
        }
    }

    private enum Failure: Error { case offline }
}

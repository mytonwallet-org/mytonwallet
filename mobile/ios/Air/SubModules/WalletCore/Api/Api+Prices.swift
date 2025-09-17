
import Foundation
import WalletContext

extension Api {
    
    public static func fetchPriceHistory(slug: String, period: ApiPriceHistoryPeriod, baseCurrency: MBaseCurrency) async throws -> ApiHistoryList {
        try await bridge.callApi("fetchPriceHistory", slug, period, baseCurrency, decoding: ApiHistoryList.self)
    }
}


// MARK: - Types

public typealias ApiHistoryList = [[Double]]

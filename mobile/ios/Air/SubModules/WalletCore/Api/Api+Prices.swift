
import Foundation
import WalletContext

extension Api {
    
    public static func getBaseCurrency() async throws -> MBaseCurrency {
        try await bridge.callApi("getBaseCurrency", decoding: MBaseCurrency.self)
    }
    
    internal static func setBaseCurrency(currency: MBaseCurrency) async throws {
        try await bridge.callApiVoid("setBaseCurrency", currency)
    }
    
    public static func fetchPriceHistory(slug: String, period: ApiPriceHistoryPeriod, baseCurrency: MBaseCurrency) async throws -> ApiHistoryList {
        try await bridge.callApi("fetchPriceHistory", slug, period, baseCurrency, decoding: ApiHistoryList.self)
    }
}


// MARK: - Types

public typealias ApiHistoryList = [[Double]]

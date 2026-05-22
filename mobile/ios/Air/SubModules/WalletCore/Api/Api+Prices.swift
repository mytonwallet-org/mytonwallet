
import Foundation
import WalletContext

extension Api {
    
    public static func fetchPriceHistory(slug: String, period: ApiPriceHistoryPeriod, baseCurrency: MBaseCurrency) async throws -> ApiHistoryList {
        try await bridge.callApi("fetchPriceHistory", slug, period, baseCurrency, decoding: ApiHistoryList.self)
    }

    @concurrent public static func fetchPortfolioNetWorthHistory(
        wallets: [String],
        baseCurrency: MBaseCurrency,
        historyRequest: ApiPortfolioHistoryRequest? = nil
    ) async throws -> ApiPortfolioHistoryResponse {
        if let historyRequest {
            try await bridge.callApi(
                "fetchPortfolioNetWorthHistory",
                wallets,
                baseCurrency,
                historyRequest,
                decoding: ApiPortfolioHistoryResponse.self
            )
        } else {
            try await bridge.callApi(
                "fetchPortfolioNetWorthHistory",
                wallets,
                baseCurrency,
                decoding: ApiPortfolioHistoryResponse.self
            )
        }
    }

    @concurrent public static func fetchPortfolioPnlCumulativeHistory(
        wallets: [String],
        baseCurrency: MBaseCurrency,
        historyRequest: ApiPortfolioHistoryRequest? = nil
    ) async throws -> ApiPortfolioHistoryResponse {
        if let historyRequest {
            try await bridge.callApi(
                "fetchPortfolioPnlCumulativeHistory",
                wallets,
                baseCurrency,
                historyRequest,
                decoding: ApiPortfolioHistoryResponse.self
            )
        } else {
            try await bridge.callApi(
                "fetchPortfolioPnlCumulativeHistory",
                wallets,
                baseCurrency,
                decoding: ApiPortfolioHistoryResponse.self
            )
        }
    }

    @concurrent public static func fetchPortfolioPnlHistory(
        wallets: [String],
        baseCurrency: MBaseCurrency,
        historyRequest: ApiPortfolioHistoryRequest? = nil
    ) async throws -> ApiPortfolioHistoryResponse {
        if let historyRequest {
            try await bridge.callApi(
                "fetchPortfolioPnlHistory",
                wallets,
                baseCurrency,
                historyRequest,
                decoding: ApiPortfolioHistoryResponse.self
            )
        } else {
            try await bridge.callApi(
                "fetchPortfolioPnlHistory",
                wallets,
                baseCurrency,
                decoding: ApiPortfolioHistoryResponse.self
            )
        }
    }
}


// MARK: - Types

public typealias ApiHistoryList = [[Double]]

public struct ApiPortfolioHistoryRequest: Encodable, Equatable, Hashable, Sendable {
    public let from: Double
    public let density: String

    public init(from: Date, density: String) {
        self.from = from.timeIntervalSince1970
        self.density = density
    }
}

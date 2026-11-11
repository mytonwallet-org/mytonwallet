
import Foundation
import WalletContext
import WalletCoreTypes

extension Api {
    
    public static func fetchPriceHistory(token: ApiToken, period: ApiPriceHistoryPeriod, baseCurrency: MBaseCurrency) async throws -> ApiPriceHistory {
        try await bridge.callApi("fetchPriceHistory", token.slug, period, baseCurrency, token, decoding: ApiPriceHistory.self)
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

/// Daily USD closes of the underlying stock, all earlier than the first point of the token's own history
public struct ApiPriceHistoryBackfill: Codable, Equatable, Hashable, Sendable {
    public let symbol: String
    public let points: ApiHistoryList
}

public struct ApiPriceHistory: Codable, Equatable, Hashable, Sendable {
    public let points: ApiHistoryList
    public let backfill: ApiPriceHistoryBackfill?
}

public struct ApiPortfolioHistoryRequest: Encodable, Equatable, Hashable, Sendable {
    public let from: Double
    public let to: Double
    public let density: String

    public init(from: Date, to: Date, density: String) {
        self.from = from.timeIntervalSince1970
        self.to = to.timeIntervalSince1970
        self.density = density
    }
}

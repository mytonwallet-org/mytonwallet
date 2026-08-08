import Foundation
import WalletCoreTypes

enum WidgetAPI {
    private static let baseURL = URL(string: "https://api.mytonwallet.org")!

    struct TokenPrice: Sendable {
        let priceUsd: Double
        let percentChange24h: Double?
    }

    static func fetchPrice(for token: ApiToken) async throws -> TokenPrice {
        var request = URLRequest(url: baseURL.appending(path: "assets"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AssetsRequest(assets: [token.swapIdentifier]))

        let data = try await data(for: request)
        let details = try JSONDecoder().decode([AssetPrice].self, from: data)
        guard let detail = details.last(where: { $0.slug == token.slug }),
              let priceUsd = detail.priceUsd else {
            throw WidgetAPIError.missingPrice(token.slug)
        }
        return TokenPrice(priceUsd: priceUsd, percentChange24h: detail.percentChange24h)
    }

    static func fetchCurrencyRates() async throws -> [String: MDouble] {
        let request = URLRequest(url: baseURL.appending(path: "currency-rates"))
        let data = try await data(for: request)
        return try JSONDecoder().decode(CurrencyRatesResponse.self, from: data).rates
    }

    static func fetchChart(
        for token: ApiToken,
        baseCurrency: MBaseCurrency,
        period: PricePeriod
    ) async throws -> [(Double, Double)] {
        let identifier = token.tokenAddress.flatMap { $0.isEmpty ? nil : $0 } ?? token.symbol
        let assetId = "\(token.chain.rawValue):\(identifier)"
        var components = URLComponents(
            url: baseURL.appending(path: "prices/chart/\(assetId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "base", value: baseCurrency.rawValue),
            URLQueryItem(name: "period", value: period.rawValue),
        ]

        let data = try await data(for: URLRequest(url: components.url!))
        let history = try JSONDecoder().decode([[Double]].self, from: data)
        return history.compactMap { point in
            guard point.count >= 2 else { return nil }
            return (point[0], point[1])
        }
    }

    private static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode else {
            throw WidgetAPIError.invalidResponse
        }
        return data
    }
}

private struct AssetsRequest: Encodable {
    let assets: [String]
}

private struct AssetPrice: Decodable {
    let slug: String
    let priceUsd: Double?
    let percentChange24h: Double?
}

private struct CurrencyRatesResponse: Decodable {
    let rates: [String: MDouble]
}

private enum WidgetAPIError: Error {
    case invalidResponse
    case missingPrice(String)
}

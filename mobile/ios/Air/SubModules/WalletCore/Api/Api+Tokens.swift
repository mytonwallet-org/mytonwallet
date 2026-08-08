//
//  Api+Tokens.swift
//  WalletCore
//
//  Created by Sina on 3/28/24.
//

import Foundation
import WalletContext
import WalletCoreTypes

extension Api {
    public static func fetchToken(accountId: String, chain: ApiChain, tokenAddress: String) async throws -> ApiToken {
        try await bridge.callApi("fetchToken", accountId, chain, tokenAddress, decoding: ApiToken.self)
    }

    public static func importToken(accountId: String, chain: ApiChain, tokenAddress: String) async throws {
        try await bridge.callApiVoid("importToken", accountId, chain, tokenAddress)
    }

    public static func buildTokenSlug(chain: ApiChain, tokenAddress: String) async throws -> String {
        try await bridge.callApi("buildTokenSlug", chain, tokenAddress, decoding: String.self)
    }

    @concurrent public static func fetchTokenDetails(asset: String, slug: String) async throws -> ApiTokenDetails? {
        let preset = DebugTokenInfoMock.preset

        if preset == .loading {
            while true {
                try await Task.sleep(for: .seconds(60))
            }
        }

        if preset != .disabled {
            try await Task.sleep(for: .seconds(1.5))
        }

        switch preset {
        case .disabled:
            let response = try await bridge.callApi(
                "fetchTokenDetails",
                [asset],
                decoding: [ApiTokenDetailsResponse].self
            )
            return response.first { $0.slug == slug }?.tokenInfo
        case .design:
            return .designMock
        case .localizedDescription:
            return .localizedDescriptionMock
        case .longSparse:
            return .longSparseMock
        case .missingDescription:
            return .missingDescriptionMock
        case .missingTokenInfo:
            return nil
        case .error, .loading:
            throw TokenInfoMockError.noData
        }
    }
}

private enum TokenInfoMockError: Error {
    case noData
}

struct ApiTokenDetailsResponse: Decodable, Sendable {
    let slug: String
    let tokenInfo: ApiTokenDetails?
}

public struct ApiTokenDetails: Equatable, Decodable, Sendable {
    public let description: String?
    public let localizedDescription: String?
    public let links: [Link]?
    public let marketCap: Double?
    public let circulatingSupply: Double?
    public let totalSupply: Double?
    public let createdAt: Date?
    public let volume24h: Volume?

    public struct Link: Equatable, Codable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case x
            case telegram
            case website
            case documentation
            case sourceCode
            case aggregator
        }

        public let kind: Kind
        public let title: String
        public let url: URL

        public var id: URL { url }
    }

    public struct Volume: Equatable, Codable, Sendable {
        public let total: Double
        public let buy: Double
        public let sell: Double
        public let change: Double?
        public let currency: MBaseCurrency
    }

    public init(
        description: String?,
        localizedDescription: String? = nil,
        links: [Link]?,
        marketCap: Double?,
        circulatingSupply: Double?,
        totalSupply: Double?,
        createdAt: Date?,
        volume24h: Volume?
    ) {
        self.description = description
        self.localizedDescription = localizedDescription
        self.links = links
        self.marketCap = marketCap
        self.circulatingSupply = circulatingSupply
        self.totalSupply = totalSupply
        self.createdAt = createdAt
        self.volume24h = volume24h
    }

    private enum CodingKeys: String, CodingKey {
        case description
        case localizedDescription
        case links
        case marketCap
        case supply
        case createdAt
        case volume24h
        case aggregatorLinks
        case docsUrl
        case sourceCodeUrl
    }

    private struct Supply: Decodable {
        let circulating: Double?
        let total: Double?

        private enum CodingKeys: String, CodingKey {
            case circulating
            case total
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.circulating = container.decodeLossy(Double.self, forKey: .circulating)
            self.total = container.decodeLossy(Double.self, forKey: .total)
        }
    }

    private struct BackendLink: Decodable {
        let url: String
        let type: String?

        private enum CodingKeys: String, CodingKey {
            case url
            case type
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.url = try container.decode(String.self, forKey: .url)
            self.type = container.decodeLossy(String.self, forKey: .type)
        }
    }

    private struct AggregatorLink: Decodable {
        let url: String
        let name: String
    }

    private struct BackendVolume: Decodable {
        let sell: Double?
        let buy: Double?
        let percentChange: Double?

        private enum CodingKeys: String, CodingKey {
            case sell
            case buy
            case percentChange
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.sell = container.decodeLossy(Double.self, forKey: .sell)
            self.buy = container.decodeLossy(Double.self, forKey: .buy)
            self.percentChange = container.decodeLossy(Double.self, forKey: .percentChange)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let supply = container.decodeLossy(Supply.self, forKey: .supply)
        let backendVolume = container.decodeLossy(BackendVolume.self, forKey: .volume24h)
        var links: [Link] = container
            .decodeLossyArray(BackendLink.self, forKey: .links)
            .compactMap { link -> Link? in
                guard let url = URL(string: link.url) else { return nil }
                let (kind, title): (Link.Kind, String) = switch link.type {
                case "x":
                    (.x, "X")
                case "telegram":
                    (.telegram, "Telegram")
                default:
                    (.website, "Website")
                }
                return Link(kind: kind, title: title, url: url)
            }

        let aggregatorLinks = container.decodeLossyArray(AggregatorLink.self, forKey: .aggregatorLinks)
        links.append(contentsOf: aggregatorLinks.compactMap { link in
            URL(string: link.url).map { Link(kind: .aggregator, title: link.name, url: $0) }
        })
        if let docsUrl = container.decodeLossy(String.self, forKey: .docsUrl),
           let url = URL(string: docsUrl) {
            links.append(Link(kind: .documentation, title: "Documentation", url: url))
        }
        if let sourceCodeUrl = container.decodeLossy(String.self, forKey: .sourceCodeUrl),
           let url = URL(string: sourceCodeUrl) {
            links.append(Link(kind: .sourceCode, title: "Source Code", url: url))
        }
        var seenUrls = Set<URL>()
        links = links.filter { seenUrls.insert($0.url).inserted }

        self.description = container.decodeLossy(String.self, forKey: .description)
        self.localizedDescription = container.decodeLossy(String.self, forKey: .localizedDescription)
        self.links = links.nilIfEmpty
        self.marketCap = container.decodeLossy(Double.self, forKey: .marketCap)
        self.circulatingSupply = supply?.circulating
        self.totalSupply = supply?.total
        self.createdAt = container.decodeLossy(String.self, forKey: .createdAt).flatMap(Self.parseDate)
        self.volume24h = if let backendVolume,
                            let buy = backendVolume.buy,
                            let sell = backendVolume.sell {
            Volume(
                total: buy + sell,
                buy: buy,
                sell: sell,
                change: backendVolume.percentChange.map { $0 / 100 },
                currency: .USD
            )
        } else {
            nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        self.value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossy<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        try? decode(type, forKey: key)
    }

    func decodeLossyArray<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> [Value] {
        decodeLossy([LossyDecodable<Value>].self, forKey: key)?.compactMap(\.value) ?? []
    }
}

private extension ApiTokenDetails {
    static let designMock = ApiTokenDetails(
        description: "Gram is TON’s native cryptocurrency and deeply integrated into the Telegram ecosystem.",
        links: [
            .init(kind: .x, title: "X", url: URL(string: "https://x.com")!),
            .init(kind: .telegram, title: "Telegram", url: URL(string: "https://t.me")!),
            .init(kind: .website, title: "Website", url: URL(string: "https://gramcoin.org")!),
        ],
        marketCap: 7_580_000_000,
        circulatingSupply: 5_120_000_000,
        totalSupply: 5_120_000_000,
        createdAt: Date(timeIntervalSince1970: 1_573_776_000),
        volume24h: .init(
            total: 4_030_000,
            buy: 2_440_000,
            sell: 1_580_000,
            change: 0.8946,
            currency: .USD
        )
    )

    static let localizedDescriptionMock = ApiTokenDetails(
        description: designMock.description,
        localizedDescription: "Gram — нативная криптовалюта TON, глубоко интегрированная в экосистему Telegram.",
        links: designMock.links,
        marketCap: designMock.marketCap,
        circulatingSupply: designMock.circulatingSupply,
        totalSupply: designMock.totalSupply,
        createdAt: designMock.createdAt,
        volume24h: designMock.volume24h
    )

    static let longSparseMock = ApiTokenDetails(
        description: "Gram is TON’s native cryptocurrency and deeply integrated into the Telegram ecosystem. This deliberately long test description verifies that every additional line contributes to the measured section height without truncation.",
        links: [
            .init(kind: .x, title: "X", url: URL(string: "https://x.com")!),
            .init(kind: .telegram, title: "Telegram", url: URL(string: "https://t.me")!),
            .init(kind: .website, title: "Website", url: URL(string: "https://gramcoin.org")!),
            .init(kind: .documentation, title: "Documentation", url: URL(string: "https://gramcoin.org/docs")!),
            .init(kind: .aggregator, title: "Community Forum", url: URL(string: "https://gramcoin.org/community")!),
            .init(kind: .sourceCode, title: "Source Code", url: URL(string: "https://github.com/gramcoin")!),
        ],
        marketCap: nil,
        circulatingSupply: 5_120_000_000,
        totalSupply: nil,
        createdAt: nil,
        volume24h: nil
    )

    static let missingDescriptionMock = ApiTokenDetails(
        description: nil,
        links: designMock.links,
        marketCap: designMock.marketCap,
        circulatingSupply: designMock.circulatingSupply,
        totalSupply: designMock.totalSupply,
        createdAt: designMock.createdAt,
        volume24h: designMock.volume24h
    )
}

//
//  Api+Market.swift
//  WalletCore
//

import Foundation
import WalletContext

extension Api {
    @concurrent public static func fetchMarketAssets(langCode: String) async throws -> ApiMarketAssetsResponse {
        let response = try await bridge.callApi(
            "fetchMarketAssets",
            langCode,
            decoding: ApiMarketAssetsResponse.self
        )
        await MarketAssetsCache.shared.save(response, langCode: langCode)
        return response
    }

    @concurrent public static func cachedMarketAssets(langCode: String) async -> ApiMarketAssetsResponse? {
        await MarketAssetsCache.shared.load(langCode: langCode)
    }
}

public enum ApiMarketSectionLayout: String, Codable, Sendable, Hashable {
    case largeHorizontal
    case grid
    case rows
}

public struct ApiMarketAsset: Codable, Sendable, Hashable {
    public var newBackendId: String
    public var name: String
    public var symbol: String
    public var chain: ApiChain
    public var image: String
    public var tokenAddress: String?
    public var label: String?
    public var price: Double
    public var percentChange24h: Double
    public var sparkline: [Double]?
    public var tintColor: String?
    public var slug: String
}

public struct ApiMarketSectionResponse: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var layout: ApiMarketSectionLayout
    public var limit: Int?
    public var desktopLimit: Int?
    public var mobileLimit: Int?
    public var hasMore: Bool
    public var assets: [ApiMarketAsset]
}

public struct ApiMarketAssetsResponse: Codable, Sendable, Hashable {
    public var sections: [ApiMarketSectionResponse]
}

actor MarketAssetsCache {
    static let shared = MarketAssetsCache()

    private struct Entry: Codable {
        let schemaVersion: Int
        let langCode: String
        let response: ApiMarketAssetsResponse
    }

    private static let schemaVersion = 1
    private let cacheURL: URL

    init(
        cacheURL: URL = URL.applicationSupportDirectory
            .appending(components: "air", "market-assets.json")
    ) {
        self.cacheURL = cacheURL
    }

    func load(langCode: String) -> ApiMarketAssetsResponse? {
        guard FileManager.default.fileExists(atPath: cacheURL.path()) else { return nil }

        do {
            let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: cacheURL))
            guard entry.schemaVersion == Self.schemaVersion, entry.langCode == langCode else {
                return nil
            }
            return entry.response
        } catch {
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }
    }

    func save(_ response: ApiMarketAssetsResponse, langCode: String) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let entry = Entry(
                schemaVersion: Self.schemaVersion,
                langCode: langCode,
                response: response
            )
            try JSONEncoder().encode(entry).write(to: cacheURL, options: .atomic)
        } catch {
        }
    }
}

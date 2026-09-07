import Foundation
import UniversalSearchCore
import WalletCore

public struct WalletCoreExploreAppSearchInput: Sendable {
    public let sites: [ApiSite]
    public let categories: [ApiSiteCategory]
    public let shouldRestrictSites: Bool

    public init(
        sites: [ApiSite],
        categories: [ApiSiteCategory],
        shouldRestrictSites: Bool
    ) {
        self.sites = sites
        self.categories = categories
        self.shouldRestrictSites = shouldRestrictSites
    }
}

public struct WalletCoreExploreAppSearchSource: UniversalSearchSource {
    public typealias Loader = @Sendable (
        UniversalSearchContext
    ) async throws -> WalletCoreExploreAppSearchInput

    public static let id = SearchSourceID("wallet-core:explore-apps")

    public let sourceID = Self.id
    public var scoping: UniversalSearchSourceScoping { .global }
    private let loader: Loader
    private let clock: @Sendable () -> Date

    public init(
        loader: @escaping Loader,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loader = loader
        self.clock = clock
    }

    public init() {
        self.init(loader: Self.loadLiveApps)
    }

    public func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let input = try await loader(context)
        let generatedAt = clock()
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: WalletCoreSearchSourceAuthority.catalog,
            generatedAt: generatedAt,
            documents: Self.documents(input: input, generatedAt: generatedAt)
        )
    }

    public static func documents(
        input: WalletCoreExploreAppSearchInput,
        generatedAt: Date
    ) -> [SearchDocument] {
        let categoryNames = Dictionary(
            input.categories.map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        let indexedSites = input.sites.enumerated().filter { _, site in
            !input.shouldRestrictSites || !site.canBeRestricted
        }

        var featuredRank = 0
        var documentByID: [SearchEntityID: SearchDocument] = [:]
        for (index, site) in indexedSites {
            let canonicalID = WalletCoreApplicationIdentity.canonicalID(url: site.url)
            let entityID = SearchEntityID("application:\(canonicalID)")
            guard documentByID[entityID] == nil else { continue }

            let isFeatured = site.isFeatured == true
            if isFeatured {
                featuredRank += 1
            }
            var traits: SearchTraits = [.curated, .popular]
            if site.isVerified == true {
                traits.insert(.verified)
            }
            if isFeatured {
                traits.insert(.trending)
            }
            let categoryName = site.categoryId.flatMap { categoryNames[$0] }
            documentByID[entityID] = SearchDocument(
                id: entityID,
                kind: .application,
                fields: makeSearchFields([
                    (site.name, .title, .text),
                    (site.url, .url, .text),
                    // For Telegram sites, siteHost is the username, not a domain (for example, "send").
                    (site.siteHost, URL(string: site.url)?.host?.lowercased() == "t.me" ? .alias : .domain, .text),
                    (categoryName, .keyword, .text),
                    (site.description, .description, .text),
                ]),
                attributes: makeSearchAttributes([
                    (WalletCoreSearchAttributeKey.iconURL, site.icon),
                    (WalletCoreSearchAttributeKey.url, site.url),
                    (
                        WalletCoreSearchAttributeKey.opensExternally,
                        String(site.shouldOpenExternally)
                    ),
                ]),
                signals: SearchSignals(
                    traits: traits,
                    popularity: SearchRankedSignal(
                        source: Self.id,
                        rank: index + 1,
                        generatedAt: generatedAt,
                        reason: "explore-catalog-order"
                    ),
                    recommendation: isFeatured ? SearchRankedSignal(
                        source: Self.id,
                        rank: featuredRank,
                        generatedAt: generatedAt,
                        reason: "explore-featured"
                    ) : nil
                )
            )
        }

        return documentByID.values.sorted { $0.id < $1.id }
    }

    private static func loadLiveApps(
        context: UniversalSearchContext
    ) async throws -> WalletCoreExploreAppSearchInput {
        let result = try await Api.loadExploreSites(langCode: context.localeIdentifier)
        return WalletCoreExploreAppSearchInput(
            sites: result.sites,
            categories: result.categories,
            shouldRestrictSites: ConfigStore.shared.shouldRestrictSites
        )
    }
}

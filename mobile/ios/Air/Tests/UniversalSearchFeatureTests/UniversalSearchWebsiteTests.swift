import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
@testable import UniversalSearchFeature

@MainActor
@Suite("Universal Search websites")
struct UniversalSearchWebsiteTests {
    private let context = UniversalSearchContext(
        scopeID: "account", network: "mainnet", localeIdentifier: "en"
    )

    @Test(arguments: ["app.ens.domains", "google.com"])
    func `URL input opens the requested website despite incidental app and history matches`(
        query: String
    ) throws {
        let documents = [
            webDocument("uniswap", url: "https://app.uniswap.org"),
            webDocument("aave", url: "https://app.aave.com"),
            webDocument("history", url: "https://fragment.com", kind: .site),
            webDocument(query, url: "https://unrelated.example"),
            SearchDocument(
                id: SearchEntityID("web-search-history:query"), kind: .webSearchHistory,
                fields: [.init(query, kind: .title)],
                attributes: [.init(key: UniversalSearchFeatureAttributeKey.query, value: query)]
            ),
        ]
        let snapshot = rankedSnapshot(query, documents: documents)
        #expect(!snapshot.hits.isEmpty)
        let presentation = UniversalSearchResultsPresenter().presentation(for: snapshot, context: context)

        #expect(presentation.sections.map(\.id) == ["open-website", "ask-agent", "search-google"])
        guard case .website(let url, _) = try selectedRoute(presentation) else {
            Issue.record("Expected the requested website to be selected")
            return
        }
        #expect(url.absoluteString == "https://\(query)")
        guard case .google(let googleQuery) = presentation.routesByItemID["web-action:google:\(query)"] else {
            Issue.record("Expected Google search to remain available separately")
            return
        }
        #expect(googleQuery == query)
    }

    @Test(arguments: ["app.uniswap.org", "APP.UNISWAP.ORG/", "app.uniswap.org:443"])
    func `a known dapp at the requested destination remains the top hit`(query: String) throws {
        let app = webDocument("uniswap", url: "https://app.uniswap.org/")
        let unrelated = webDocument("aave", url: "https://app.aave.com")
        let presentation = UniversalSearchResultsPresenter().presentation(
            for: rankedSnapshot(query, documents: [unrelated, app]), context: context
        )

        #expect(presentation.sections.map(\.id) == ["top-hit", "ask-agent", "search-google"])
        #expect(presentation.preselectedItemID == app.id.rawValue)
        guard case .application(let url, _, _) = try selectedRoute(presentation) else {
            Issue.record("Expected the matching dapp route")
            return
        }
        #expect(url.absoluteString == "https://app.uniswap.org/")
    }

    @Test
    func `history at the requested destination remains eligible`() throws {
        let site = webDocument("Google", url: "https://google.com/", kind: .site)
        let presentation = UniversalSearchResultsPresenter().presentation(
            for: rankedSnapshot("google.com", documents: [site]), context: context
        )

        #expect(presentation.preselectedItemID == site.id.rawValue)
        guard case .website(let url, _) = try selectedRoute(presentation) else {
            Issue.record("Expected the matching history route")
            return
        }
        #expect(url.host == "google.com")
    }

    @Test(arguments: [
        "google.com/search?q=TON", "google.com/#Details", "google.com/Path?Q=ABC",
        "http://google.com", "google.com:8443", "google.com/@alice",
    ])
    func `a matching host never discards an explicitly requested destination`(query: String) throws {
        let app = webDocument("Google", url: "https://google.com")
        let snapshot = rankedSnapshot(query, documents: [app])
        #expect(!snapshot.hits.isEmpty)
        let presentation = UniversalSearchResultsPresenter().presentation(for: snapshot, context: context)
        let expectedURL = query.hasPrefix("http://") ? query : "https://\(query)"

        #expect(presentation.sections.first?.id == "open-website")
        guard case .website(let url, _) = try selectedRoute(presentation) else {
            Issue.record("Expected the exact typed URL to open")
            return
        }
        #expect(url.absoluteString == expectedURL)
    }

    @Test(arguments: [
        "staking on google.com", "ens domains", "alice@example.com",
        "https://alice@example.com", "mwme.ton",
    ])
    func `ordinary queries email and wallet domains are not website navigation`(query: String) {
        guard case .searchGoogle(let text) = UniversalSearchWebIntent(query) else {
            Issue.record("Expected a search query")
            return
        }
        #expect(text == query)
    }

    @Test
    func `pasted Google search URL opens directly without wrapping it in another search`() throws {
        let input = "https://www.google.com/search?q=what%20is%20staking"
        let presentation = UniversalSearchResultsPresenter().presentation(
            for: rankedSnapshot(input, documents: []), context: context
        )
        guard case .website(let url, _) = try selectedRoute(presentation) else {
            Issue.record("Expected the pasted URL to open")
            return
        }
        #expect(url.absoluteString == input)
    }

    private func webDocument(
        _ name: String, url: String, kind: SearchEntityKind = .application
    ) -> SearchDocument {
        SearchDocument(
            id: SearchEntityID("\(kind.rawValue):\(name)"), kind: kind,
            fields: [
                .init(name, kind: .title),
                .init(URL(string: url)!.host!, kind: .domain),
                .init(url, kind: .url),
            ],
            attributes: [
                .init(key: WalletCoreSearchAttributeKey.url, value: url),
                .init(key: UniversalSearchFeatureAttributeKey.title, value: name),
            ]
        )
    }

    private func rankedSnapshot(_ text: String, documents: [SearchDocument]) -> UniversalSearchResultSnapshot {
        let query = UniversalSearchQuery(text)
        let hits = UniversalSearchEngine().search(query, in: documents)
        return UniversalSearchResultSnapshot(
            query: query, hits: hits, totalHitCount: hits.count,
            corpusRevision: 1, rankingPolicyVersion: "test", generatedAt: Date()
        )
    }

    private func selectedRoute(_ presentation: UniversalSearchPresentation) throws -> UniversalSearchFeatureRoute {
        let id = try #require(presentation.preselectedItemID)
        return try #require(presentation.routesByItemID[id])
    }
}

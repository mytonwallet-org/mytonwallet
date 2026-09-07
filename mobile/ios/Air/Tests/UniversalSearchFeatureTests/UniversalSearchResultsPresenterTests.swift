import Foundation
import Testing
import UIUniversalSearch
import UniversalSearchCore
import UniversalSearchFeature
import UniversalSearchWalletCore
import WalletCoreTypes

@MainActor
@Suite("Universal Search results presentation")
struct UniversalSearchResultsPresenterTests {
    @Test
    func `extracts top hit and groups remaining results without losing routes`() throws {
        let documents = makeDocuments()
        let hits = documents.map(makeSearchHit)
        let snapshot = UniversalSearchResultSnapshot(
            query: UniversalSearchQuery("wallet"),
            hits: hits,
            totalHitCount: hits.count,
            corpusRevision: 1,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let presenter = makePresenter()
        let context = UniversalSearchContext(
            scopeID: "account",
            network: "mainnet",
            localeIdentifier: "en"
        )

        let presentation = presenter.presentation(for: snapshot, context: context)
        let topSection = try #require(presentation.sections.first)
        let tokenSection = try #require(presentation.sections.first { $0.id == "tokens" })

        #expect(presentation.sections.map(\.id) == [
            "top-hit", "tokens", "apps", "ask-agent", "search-google",
        ])
        #expect(topSection.items.count == 1)
        #expect(presentation.preselectedItemID == topSection.items.first?.id)
        #expect(tokenSection.items.count == 4)
        #expect(presentation.routesByItemID.count == hits.count + 2)
    }

    @Test
    func `empty input produces no result sections`() {
        let snapshot = UniversalSearchResultSnapshot(
            query: UniversalSearchQuery(""),
            hits: [],
            totalHitCount: 0,
            corpusRevision: 0,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let presenter = UniversalSearchResultsPresenter(resolver: { _, _ in nil })
        let context = UniversalSearchContext(
            scopeID: nil,
            network: nil,
            localeIdentifier: "en"
        )

        let presentation = presenter.presentation(for: snapshot, context: context)

        #expect(presentation.sections.isEmpty)
        #expect(presentation.preselectedItemID == nil)
        #expect(presentation.routesByItemID.isEmpty)
    }

    @Test
    func `catalog app preserves external routing metadata`() throws {
        let document = SearchDocument(
            id: SearchEntityID("application:t.me/testbot"),
            kind: .application,
            fields: [SearchField("Test Bot", kind: .title)],
            attributes: [
                SearchAttribute(
                    key: WalletCoreSearchAttributeKey.url,
                    value: "https://t.me/testbot"
                ),
                SearchAttribute(
                    key: WalletCoreSearchAttributeKey.opensExternally,
                    value: "true"
                ),
            ]
        )
        let hits = [makeSearchHit(document)]
        let snapshot = UniversalSearchResultSnapshot(
            query: UniversalSearchQuery("Test"),
            hits: hits,
            totalHitCount: hits.count,
            corpusRevision: 1,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let context = UniversalSearchContext(
            scopeID: "account",
            network: "mainnet",
            localeIdentifier: "en"
        )

        let presentation = UniversalSearchResultsPresenter().presentation(
            for: snapshot,
            context: context
        )
        let route = try #require(presentation.routesByItemID[document.id.rawValue])
        guard case .application(let url, let title, let opensExternally) = route else {
            Issue.record("Expected an application route")
            return
        }

        #expect(url == URL(string: "https://t.me/testbot"))
        #expect(title == "Test Bot")
        #expect(opensExternally)
    }

    @Test
    func `token without a balance uses its ticker as trailing amount`() throws {
        let token = ApiToken(
            slug: "ton-fragment-test",
            name: "Fragment",
            symbol: "FRAG",
            decimals: 9,
            chain: .ton
        )
        let document = SearchDocument(
            id: SearchEntityID("token:\(token.slug)"),
            kind: .token,
            fields: [SearchField(token.name, kind: .title)],
            attributes: [SearchAttribute(
                key: WalletCoreSearchAttributeKey.tokenSlug,
                value: token.slug
            )]
        )
        let hits = [makeSearchHit(document)]
        let snapshot = UniversalSearchResultSnapshot(
            query: UniversalSearchQuery("fragment"),
            hits: hits,
            totalHitCount: hits.count,
            corpusRevision: 1,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let context = UniversalSearchContext(
            scopeID: "unheld-token-test",
            network: "mainnet",
            localeIdentifier: "en"
        )
        let presenter = UniversalSearchResultsPresenter(
            tokenResolver: { _, slug in
                slug == token.slug ? token : nil
            },
            tokenBalanceResolver: { _, _ in nil }
        )

        let presentation = presenter.presentation(for: snapshot, context: context)
        let item = try #require(presentation.sections.first?.items.first)
        guard case .token(let result) = item.content else {
            Issue.record("Expected a token result")
            return
        }

        #expect(result.amount == "FRAG")
        #expect(result.balanceValue == nil)
    }

    @Test
    func `resolved external wallet routes through temporary wallet input`() throws {
        let address = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
        let document = SearchDocument(
            id: SearchEntityID("wallet:external:mainnet:ton:mwme.ton"),
            kind: .wallet,
            fields: [SearchField("mwme.ton", kind: .domain, matchPolicy: .exact)],
            matchRequirement: .exactIdentifier,
            attributes: [
                SearchAttribute(key: WalletCoreSearchAttributeKey.address, value: address),
                SearchAttribute(key: WalletCoreSearchAttributeKey.addressName, value: "My Wallet"),
                SearchAttribute(key: WalletCoreSearchAttributeKey.chain, value: "ton"),
                SearchAttribute(key: WalletCoreSearchAttributeKey.domain, value: "mwme.ton"),
                SearchAttribute(
                    key: WalletCoreSearchAttributeKey.inputAddressOrDomain,
                    value: "mwme.ton"
                ),
                SearchAttribute(key: WalletCoreSearchAttributeKey.network, value: "mainnet"),
            ],
            signals: SearchSignals(traits: [.external, .viewOnly])
        )
        let hits = [makeSearchHit(document)]
        let snapshot = UniversalSearchResultSnapshot(
            query: UniversalSearchQuery("mwme.ton"),
            hits: hits,
            totalHitCount: hits.count,
            corpusRevision: 1,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        let presentation = UniversalSearchResultsPresenter().presentation(
            for: snapshot,
            context: context
        )
        let route = try #require(presentation.routesByItemID[document.id.rawValue])
        guard case .externalWallet(let network, let addressOrDomainByChain) = route else {
            Issue.record("Expected a temporary external wallet route")
            return
        }

        #expect(network == .mainnet)
        #expect(addressOrDomainByChain == ["ton": "mwme.ton"])
    }

    @Test
    func `browse presentation defaults each section to available recent or trending data`() throws {
        let fixture = makeMixedBrowseFixture()
        let tokens = try #require(fixture.presentation.sections.first { $0.id == "tokens" })
        let apps = try #require(fixture.presentation.sections.first { $0.id == "apps" })

        #expect(tokens.items.map(\.id) == [fixture.recentToken.id.rawValue])
        #expect(apps.items.map(\.id) == [fixture.trendingApp.id.rawValue])
        #expect(fixture.presentation.preselectedItemID == nil)
    }

    @Test
    func `browse presentation only exposes routes for the selected results`() {
        let fixture = makeMixedBrowseFixture()
        let expectedRouteIDs = [
            "agent-chat:start",
            fixture.trendingApp.id.rawValue,
            fixture.recentToken.id.rawValue,
        ].sorted()
        #expect(fixture.presentation.routesByItemID.keys.sorted() == expectedRouteIDs)
    }

    @Test
    func `browse selections are independent and the agent entry remains available`() throws {
        let recentToken = makeDocument(id: "token:recent", kind: .token)
        let trendingToken = makeDocument(id: "token:trending", kind: .token)
        let recentApp = makeDocument(id: "app:recent", kind: .application)
        let trendingApp = makeDocument(id: "app:trending", kind: .application)
        let snapshot = UniversalSearchBrowseSnapshot(
            recentDocuments: [recentToken, recentApp],
            trendingDocuments: [trendingToken, trendingApp],
            corpusRevision: 1,
            corpusDocumentCount: 4,
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        let presentation = makePresenter().browsePresentation(
            for: snapshot,
            selectedModes: ["tokens": .recent],
            context: context
        )
        let tokens = try #require(presentation.sections.first { $0.id == "tokens" })
        let apps = try #require(presentation.sections.first { $0.id == "apps" })

        #expect(tokens.items.map(\.id) == [recentToken.id.rawValue])
        #expect(apps.items.map(\.id) == [recentApp.id.rawValue])
        let chats = try #require(presentation.sections.first { $0.id == "chats" })
        #expect(chats.items.first?.id == "agent-chat:start")
    }

    @Test
    func `browse mode override selects trending results`() throws {
        let recent = makeDocument(id: "token:recent", kind: .token)
        let trending = (0..<4).map { index in
            makeDocument(id: "token:trending-\(index)", kind: .token)
        }
        let snapshot = UniversalSearchBrowseSnapshot(
            recentDocuments: [recent],
            trendingDocuments: trending,
            corpusRevision: 1,
            corpusDocumentCount: 5,
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        let presentation = makePresenter().browsePresentation(
            for: snapshot,
            selectedModes: ["tokens": .trending],
            context: context
        )
        let tokens = try #require(presentation.sections.first { $0.id == "tokens" })

        #expect(tokens.items.map(\.id) == trending.map { $0.id.rawValue })
    }

    private func makeDocuments() -> [SearchDocument] {
        let tokens = (0..<5).map { index in
            SearchDocument(
                id: SearchEntityID("token:\(index)"),
                kind: .token,
                fields: [SearchField("Wallet \(index)", kind: .title)]
            )
        }
        let apps = (0..<2).map { index in
            SearchDocument(
                id: SearchEntityID("app:\(index)"),
                kind: .application,
                fields: [SearchField("Wallet App \(index)", kind: .title)]
            )
        }
        return tokens + apps
    }

    private var context: UniversalSearchContext {
        UniversalSearchContext(
            scopeID: "account",
            network: "mainnet",
            localeIdentifier: "en"
        )
    }

    private func makeDocument(id: String, kind: SearchEntityKind) -> SearchDocument {
        SearchDocument(
            id: SearchEntityID(id),
            kind: kind,
            fields: [.init(id, kind: .title)]
        )
    }

    private struct MixedBrowseFixture {
        let presentation: UniversalSearchPresentation
        let recentToken: SearchDocument
        let trendingApp: SearchDocument
    }

    private func makeMixedBrowseFixture() -> MixedBrowseFixture {
        let recentToken = makeDocument(id: "token:recent", kind: .token)
        let trendingToken = makeDocument(id: "token:trending", kind: .token)
        let trendingApp = makeDocument(id: "app:trending", kind: .application)
        let snapshot = UniversalSearchBrowseSnapshot(
            recentDocuments: [recentToken],
            trendingDocuments: [trendingToken, trendingApp],
            corpusRevision: 1,
            corpusDocumentCount: 3,
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        return MixedBrowseFixture(
            presentation: makePresenter().browsePresentation(for: snapshot, context: context),
            recentToken: recentToken,
            trendingApp: trendingApp
        )
    }

    private func makePresenter() -> UniversalSearchResultsPresenter {
        UniversalSearchResultsPresenter { document, _ in
            guard let item = makeItem(for: document) else { return nil }
            return UniversalSearchResolvedResult(
                item: item,
                route: .application(
                    url: URL(string: "https://example.com")!,
                    title: "Test",
                    opensExternally: false
                )
            )
        }
    }

    private func makeItem(for document: SearchDocument) -> UniversalSearchItem? {
        switch document.kind {
        case .token:
            UniversalSearchItem(
                id: document.id.rawValue,
                content: .token(UniversalSearchTokenResult(
                    icon: UniversalSearchIconConfiguration(systemName: "circle"),
                    title: document.id.rawValue,
                    price: "$1"
                ))
            )
        case .application:
            UniversalSearchItem(
                id: document.id.rawValue,
                content: .app(UniversalSearchAppResult(
                    icon: UniversalSearchIconConfiguration(systemName: "app"),
                    title: document.id.rawValue,
                    subtitle: "example.com"
                ))
            )
        default:
            nil
        }
    }
}

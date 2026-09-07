import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletContext
import WalletCore
import WalletCoreTypes

@Suite("WalletCore Universal Search sources")
struct WalletCoreSearchSourceTests {
    private let account = MAccount(
        id: "account-mainnet",
        title: "Main Wallet",
        type: .mnemonic,
        byChain: [.ton: AccountChain(address: "EQ-main")]
    )

    @Test
    func `token source maps searchable fields ownership and stock traits`() {
        let token = ApiToken(
            slug: "ton-tesla",
            name: "Tesla xStock",
            symbol: "TSLAx",
            decimals: 9,
            chain: .ton,
            tokenAddress: "EQ-stock",
            isPopular: true,
            keywords: ["rwa", "shares"],
            label: "xStocks",
            priceUsd: 10
        )
        let balance = MTokenBalance(tokenSlug: token.slug, balance: 1, isStaking: false)

        let documents = WalletCoreTokenSearchSource.documents(input: .init(
            account: account,
            tokens: [token],
            balances: [balance],
            trackedTokenSlugs: [token.slug]
        ))
        let document = documents.first

        #expect(document?.id == SearchEntityID("token:ton-tesla"))
        #expect(document?.kind == .stock)
        #expect(document?.signals.traits.contains([
            .held,
            .tracked,
            .popular,
            .hasMarketData,
        ]) == true)
        #expect(document?.fields.contains(SearchField("Tesla", kind: .title)) == true)
        #expect(document?.fields.contains(SearchField("TSLAx", kind: .symbol)) == true)
        #expect(document?.fields.contains(SearchField(
            "EQ-stock",
            kind: .address,
            matchPolicy: .exact
        )) == true)
        #expect(document?.attributeValue(for: WalletCoreSearchAttributeKey.tokenSlug) == token.slug)
    }

    @Test
    func `token source excludes chains unsupported by active account`() {
        let solanaToken = ApiToken(
            slug: "solana-test",
            name: "Solana Test",
            symbol: "SOLT",
            decimals: 9,
            chain: .solana
        )

        let documents = WalletCoreTokenSearchSource.documents(input: .init(
            account: account,
            tokens: [solanaToken],
            balances: [],
            trackedTokenSlugs: []
        ))

        #expect(documents.isEmpty)
    }

    @Test
    func `wallet source distinguishes owned view and temporary external wallets`() {
        let owned = account
        let view = MAccount(
            id: "view-mainnet",
            title: "Watch",
            type: .view,
            byChain: [.ton: AccountChain(address: "EQ-view", domain: "watch.ton")]
        )
        let external = MAccount(
            id: "external-mainnet",
            title: nil,
            type: .view,
            byChain: [.ton: AccountChain(address: "EQ-external")],
            isTemporary: true
        )

        let documents = WalletCoreWalletSearchSource.documents(accounts: [owned, view, external])
        let byID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        let ownedDocument = byID[SearchEntityID("wallet:account-mainnet")]
        let viewDocument = byID[SearchEntityID("wallet:view-mainnet")]
        let externalDocument = byID[SearchEntityID("wallet:external-mainnet")]

        #expect(ownedDocument?.signals.traits == [.owned])
        #expect(viewDocument?.signals.traits.contains([.owned, .viewOnly]) == true)
        #expect(viewDocument?.fields.contains(SearchField("watch.ton", kind: .domain)) == true)
        #expect(viewDocument?.attributeValue(for: WalletCoreSearchAttributeKey.accountID) == view.id)
        #expect(externalDocument?.signals.traits.contains([.external, .viewOnly]) == true)
        #expect(externalDocument?.matchRequirement == .exactIdentifier)
    }

    @Test
    func `collectible source deduplicates collections and preserves account ownership`() {
        var first = ApiNft.ERROR
        first.address = "nft-1"
        first.name = "Alpha"
        first.collectionAddress = "collection-address"
        first.collectionName = "Alpha Collection"
        var second = first
        second.address = "nft-2"
        second.name = "Beta"

        let documents = WalletCoreCollectibleSearchSource.documents(
            nfts: [first, second],
            accountID: account.id
        )
        let collections = documents.filter { $0.kind == .collection }
        let collectibles = documents.filter { $0.kind == .collectible }

        #expect(collectibles.count == 2)
        #expect(collections.count == 1)
        #expect(collectibles.allSatisfy { $0.attributeValue(
            for: WalletCoreSearchAttributeKey.accountID
        ) == account.id })
    }

    @Test
    func `connected app source deduplicates canonical URL and keeps newest connection`() {
        let old = ApiDapp(
            url: "https://APP.Example.com/",
            name: "Old App",
            iconUrl: "",
            connectedAt: 1,
            urlTrustStatus: .verified,
            sse: nil
        )
        let new = ApiDapp(
            url: "https://app.example.com",
            name: "New App",
            iconUrl: "",
            connectedAt: 2,
            urlTrustStatus: .verified,
            sse: nil
        )

        let documents = WalletCoreConnectedAppSearchSource.documents(apps: [old, new])

        #expect(documents.count == 1)
        #expect(documents.first?.id == SearchEntityID("application:app.example.com"))
        #expect(documents.first?.fields.contains(SearchField("New App", kind: .title)) == true)
        #expect(documents.first?.attributeValue(for: WalletCoreSearchAttributeKey.url) == new.url)
        #expect(documents.first?.signals.traits == [.connected])
    }

    @Test
    func `explore app source maps catalog metadata ranking and restrictions`() throws {
        let date = Date(timeIntervalSince1970: 42)
        let visible = Self.makeSite(
            url: "https://t.me/VisibleBot/app?startapp=my-wallet",
            name: "Visible App",
            description: "Trade and earn on TON",
            canBeRestricted: false,
            isExternal: true,
            isFeatured: true,
            isVerified: true,
            categoryID: 7
        )
        let restricted = Self.makeSite(
            url: "https://restricted.example",
            name: "Restricted App",
            canBeRestricted: true
        )

        let documents = WalletCoreExploreAppSearchSource.documents(
            input: .init(
                sites: [visible, restricted],
                categories: [ApiSiteCategory(id: 7, name: "DeFi")],
                shouldRestrictSites: true
            ),
            generatedAt: date
        )
        let document = try #require(documents.first)

        #expect(documents.count == 1)
        #expect(document.id == SearchEntityID("application:t.me/visiblebot"))
        #expect(document.fields.contains(SearchField("Visible App", kind: .title)))
        #expect(document.fields.contains(SearchField("DeFi", kind: .keyword)))
        #expect(document.fields.contains(SearchField(
            "Trade and earn on TON",
            kind: .description
        )))
        #expect(document.attributeValue(
            for: WalletCoreSearchAttributeKey.opensExternally
        ) == "true")
        #expect(document.signals.traits.contains([
            .curated,
            .popular,
            .trending,
            .verified,
        ]))
        #expect(document.signals.popularity?.rank == 1)
        #expect(document.signals.popularity?.generatedAt == date)
        #expect(document.signals.recommendation?.rank == 1)
    }

    @Test
    func `Telegram usernames do not outrank wallet actions as exact domains`() {
        let apps = WalletCoreExploreAppSearchSource.documents(
            input: .init(
                sites: [Self.makeSite(url: "https://t.me/send", name: "Crypto Bot")],
                categories: [], shouldRestrictSites: false
            ),
            generatedAt: Date()
        )
        let send = SearchDocument(
            id: SearchEntityID("action:send"), kind: .walletAction,
            fields: [SearchField("Send", kind: .title)]
        )
        let engine = UniversalSearchEngine()
        #expect(engine.search("send", in: apps + [send]).first?.id == send.id)
        #expect(engine.search("https://t.me/send", in: apps + [send]).first?.id == apps.first?.id)
    }

    private static func makeSite(
        url: String,
        name: String,
        description: String = "",
        canBeRestricted: Bool = false,
        isExternal: Bool? = nil,
        isFeatured: Bool? = nil,
        isVerified: Bool? = nil,
        categoryID: Int? = nil
    ) -> ApiSite {
        ApiSite(
            url: url,
            name: name,
            icon: "https://example.com/icon.png",
            manifestUrl: nil,
            description: description,
            canBeRestricted: canBeRestricted,
            isExternal: isExternal,
            isFeatured: isFeatured,
            isVerified: isVerified,
            categoryId: categoryID,
            extendedIcon: nil,
            badgeText: nil,
            withBorder: nil,
            borderColor: nil
        )
    }
}

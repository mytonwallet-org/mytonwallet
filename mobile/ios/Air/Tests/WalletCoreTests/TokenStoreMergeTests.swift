import Testing
@testable import WalletCore

@Suite("TokenStore Merge")
struct TokenStoreMergeTests {
    @Test
    func `incoming missing localized name clears cached language value`() {
        let cached = makeToken(localizedName: "Тезер", image: "https://example.com/token.png")
        let incoming = makeToken(localizedName: nil, image: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: true)

        #expect(merged.localizedName == nil)
        #expect(merged.image == cached.image)
    }

    @Test
    func `incoming localized name replaces cached language value`() {
        let cached = makeToken(localizedName: "Тезер", image: nil)
        let incoming = makeToken(localizedName: "泰达币", image: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: true)

        #expect(merged.localizedName == "泰达币")
    }

    @Test
    func `incoming empty localized name clears cached language value`() {
        let cached = makeToken(localizedName: "Тезер", image: "https://example.com/token.png")
        let incoming = makeToken(localizedName: "", image: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: true)

        #expect(merged.localizedName == nil)
        #expect(merged.image == cached.image)
    }

    @Test
    func `stale incoming prices preserve cached values`() {
        let cached = makeToken(localizedName: nil, image: nil, priceUsd: 2.5, percentChange24h: 4.2)
        let incoming = makeToken(localizedName: nil, image: nil, priceUsd: 3.1, percentChange24h: 0)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: false)

        #expect(merged.priceUsd == cached.priceUsd)
        #expect(merged.percentChange24h == cached.percentChange24h)
    }

    @Test
    func `fresh incoming prices replace cached values`() {
        let cached = makeToken(localizedName: nil, image: nil, priceUsd: 2.5, percentChange24h: 4.2)
        let incoming = makeToken(localizedName: nil, image: nil, priceUsd: 2.7, percentChange24h: -1.3)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: true)

        #expect(merged.priceUsd == incoming.priceUsd)
        #expect(merged.percentChange24h == incoming.percentChange24h)
    }

    @Test
    func `stale incoming prices fill missing cached values`() {
        let cached = makeToken(localizedName: nil, image: nil, priceUsd: nil, percentChange24h: nil)
        let incoming = makeToken(localizedName: nil, image: nil, priceUsd: 3.1, percentChange24h: 0)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: false)

        #expect(merged.priceUsd == incoming.priceUsd)
        #expect(merged.percentChange24h == incoming.percentChange24h)
    }

    @Test
    func `partial update keeps unchanged tokens and removes explicit slugs`() {
        let retained = makeToken(slug: "retained", localizedName: nil, image: nil)
        let changed = makeToken(slug: "changed", localizedName: nil, image: nil, priceUsd: 1)
        let incoming = makeToken(slug: "changed", localizedName: nil, image: nil, priceUsd: 2)
        let removed = makeToken(slug: "removed", localizedName: nil, image: nil)

        let result = TokenStore._mergingTokenUpdate(
            currentTokens: [retained.slug: retained, changed.slug: changed, removed.slug: removed],
            newTokens: [incoming.slug: incoming],
            kind: .partial,
            removedSlugs: [removed.slug]
        )

        #expect(result[retained.slug] == retained)
        #expect(result[changed.slug]?.priceUsd == incoming.priceUsd)
        #expect(result[removed.slug] == nil)
    }

    @Test(arguments: [ApiUpdate.UpdateTokens.Kind.full, .fromCache])
    func `complete snapshot drops tokens omitted from the incoming list`(kind: ApiUpdate.UpdateTokens.Kind) {
        let retained = makeToken(slug: "retained", localizedName: nil, image: nil)
        let omitted = makeToken(slug: "omitted", localizedName: nil, image: nil)

        let result = TokenStore._mergingTokenUpdate(
            currentTokens: [retained.slug: retained, omitted.slug: omitted],
            newTokens: [retained.slug: retained],
            kind: kind,
            removedSlugs: []
        )

        #expect(result[retained.slug] == retained)
        #expect(result[omitted.slug] == nil)
    }

    @Test(arguments: [ApiUpdate.UpdateTokens.Kind.full, .fromCache])
    func `incomplete initial snapshot retains omitted tokens but honors explicit removals`(kind: ApiUpdate.UpdateTokens.Kind) {
        let held = makeToken(slug: "held", localizedName: nil, image: "cached-image", priceUsd: 12.5)
        let removed = makeToken(slug: "removed", localizedName: nil, image: nil)

        let result = TokenStore._mergingTokenUpdate(
            currentTokens: [held.slug: held, removed.slug: removed, ApiToken.TONCOIN.slug: .TONCOIN],
            newTokens: [:],
            kind: kind,
            removedSlugs: [removed.slug, ApiToken.TONCOIN.slug],
            isIncomplete: true
        )

        #expect(result[held.slug] == held)
        #expect(result[removed.slug] == nil)
        #expect(result[ApiToken.TONCOIN.slug] == .TONCOIN)

        let complete = TokenStore._mergingTokenUpdate(
            currentTokens: result,
            newTokens: [:],
            kind: .full,
            removedSlugs: []
        )
        #expect(complete[held.slug] == nil)
    }

    @Test(arguments: [ApiUpdate.UpdateTokens.Kind.full, .partial])
    func `placeholder price retains cached quote and a later fresh zero replaces it`(kind: ApiUpdate.UpdateTokens.Kind) {
        let cached = makeToken(localizedName: nil, image: nil, priceUsd: 1, percentChange24h: 2)
        let placeholder = makeToken(localizedName: nil, image: "new-image", priceUsd: 0, percentChange24h: 0)
        let initial = TokenStore._mergingTokenUpdate(
            currentTokens: [cached.slug: cached],
            newTokens: [placeholder.slug: placeholder],
            kind: kind,
            removedSlugs: [],
            isIncomplete: kind == .full,
            unpricedSlugs: [placeholder.slug]
        )

        #expect(initial[cached.slug]?.priceUsd == 1)
        #expect(initial[cached.slug]?.percentChange24h == 2)
        #expect(initial[cached.slug]?.image == "new-image")

        let priced = TokenStore._mergingTokenUpdate(
            currentTokens: initial,
            newTokens: [placeholder.slug: placeholder],
            kind: .partial,
            removedSlugs: []
        )
        #expect(priced[cached.slug]?.priceUsd == 0)
        #expect(priced[cached.slug]?.percentChange24h == 0)
    }

    @Test
    func `fresh update with missing quote fields retains cached values`() {
        let cached = makeToken(localizedName: nil, image: nil, priceUsd: 1, percentChange24h: 2)
        let incoming = makeToken(localizedName: nil, image: nil, priceUsd: nil, percentChange24h: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming, arePricesFresh: true)

        #expect(merged.priceUsd == 1)
        #expect(merged.percentChange24h == 2)
    }

    @Test
    func `cache update preserves existing prices`() {
        let cached = makeToken(
            slug: "cached",
            localizedName: nil,
            image: nil,
            priceUsd: 2.5,
            percentChange24h: 4.2
        )
        let incoming = makeToken(
            slug: "cached",
            localizedName: nil,
            image: nil,
            priceUsd: 3.1,
            percentChange24h: 0
        )

        let result = TokenStore._mergingTokenUpdate(
            currentTokens: [cached.slug: cached],
            newTokens: [incoming.slug: incoming],
            kind: .fromCache,
            removedSlugs: []
        )

        #expect(result[cached.slug]?.priceUsd == cached.priceUsd)
        #expect(result[cached.slug]?.percentChange24h == cached.percentChange24h)
    }

    private func makeToken(
        slug: String = "usdt",
        localizedName: String?,
        image: String?,
        priceUsd: Double? = 1,
        percentChange24h: Double? = nil
    ) -> ApiToken {
        ApiToken(
            slug: slug,
            name: "Tether USD",
            localizedName: localizedName,
            symbol: "USDT",
            decimals: 6,
            chain: .ton,
            image: image,
            priceUsd: priceUsd,
            percentChange24h: percentChange24h
        )
    }
}

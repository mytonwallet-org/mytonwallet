import Testing
@testable import WalletCore

@Suite("TokenStore Merge")
struct TokenStoreMergeTests {
    @Test
    func `incoming missing localized name clears cached language value`() {
        let cached = makeToken(localizedName: "Тезер", image: "https://example.com/token.png")
        let incoming = makeToken(localizedName: nil, image: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming)

        #expect(merged.localizedName == nil)
        #expect(merged.image == cached.image)
    }

    @Test
    func `incoming localized name replaces cached language value`() {
        let cached = makeToken(localizedName: "Тезер", image: nil)
        let incoming = makeToken(localizedName: "泰达币", image: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming)

        #expect(merged.localizedName == "泰达币")
    }

    @Test
    func `incoming empty localized name clears cached language value`() {
        let cached = makeToken(localizedName: "Тезер", image: "https://example.com/token.png")
        let incoming = makeToken(localizedName: "", image: nil)

        let merged = TokenStore._merge(cached: cached, incoming: incoming)

        #expect(merged.localizedName == nil)
        #expect(merged.image == cached.image)
    }

    private func makeToken(localizedName: String?, image: String?) -> ApiToken {
        ApiToken(
            slug: "usdt",
            name: "Tether USD",
            localizedName: localizedName,
            symbol: "USDT",
            decimals: 6,
            chain: .ton,
            image: image,
            priceUsd: 1
        )
    }
}

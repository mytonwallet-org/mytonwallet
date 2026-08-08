import Testing
import WalletCoreTypes

@Suite("TokenEntity Search")
struct TokenEntityLocalizedNameTests {
    @Test
    func `localized name is searchable without changing canonical presentation`() {
        guard #available(iOS 18.4, *) else { return }

        let token = ApiToken(
            slug: "usdt",
            name: "Tether USD",
            localizedName: "تتر",
            symbol: "USDT",
            decimals: 6,
            chain: .ton
        )

        let entity = TokenEntity(token: token)
        #expect(entity.name == "Tether USD")
        #expect(entity.apiTokenFallback.name == "Tether USD")
        #expect(entity.apiTokenFallback.localizedName == nil)
        #expect(entity.searchableKeywords.contains("تتر"))
        #expect(entity.matchesSearch("تت"))
    }
}

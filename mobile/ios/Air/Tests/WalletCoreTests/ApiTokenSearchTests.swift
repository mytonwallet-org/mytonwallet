import Testing
import WalletCore
import WalletContext

@Suite("ApiToken Search")
struct ApiTokenSearchTests {
    @Test
    func `matches token label`() {
        let token = ApiToken(
            slug: "tron-usdt",
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .tron,
            label: "TRC-20"
        )

        #expect(token.matchesSearch("trc"))
        #expect(token.matchesSearch("20"))
    }

    @Test
    func `matches blockchain title`() {
        let token = ApiToken(
            slug: "base-usdt",
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .base,
            label: "ERC-20"
        )

        #expect(token.matchesSearch("base"))
    }

    @Test
    func `keeps existing name symbol address and keyword matches`() {
        let token = ApiToken(
            slug: "custom-token",
            name: "Custom Coin",
            symbol: "CSTM",
            decimals: 9,
            chain: .ton,
            tokenAddress: "EQ_CUSTOM",
            keywords: ["alias"]
        )

        #expect(token.matchesSearch("custom"))
        #expect(token.matchesSearch("cstm"))
        #expect(token.matchesSearch("eq_custom"))
        #expect(token.matchesSearch("alias"))
        #expect(!token.matchesSearch("missing"))
    }
}

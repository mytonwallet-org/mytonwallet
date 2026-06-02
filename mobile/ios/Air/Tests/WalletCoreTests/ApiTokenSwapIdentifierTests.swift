import Testing
import WalletCore
import WalletContext

@Suite("ApiToken Swap Identifier")
struct ApiTokenSwapIdentifierTests {
    @Test
    func `toncoin uses TON swap identifier despite display symbol`() {
        #expect(ApiToken.TONCOIN.symbol == "GRAM")
        #expect(ApiToken.TONCOIN.swapIdentifier == "TON")
    }

    @Test
    func `jettons use token address before slug`() {
        let token = ApiToken(
            slug: "ton-test-token",
            name: "Test Token",
            symbol: "TEST",
            decimals: 9,
            chain: .ton,
            tokenAddress: "EQ_TEST"
        )

        #expect(token.swapIdentifier == "EQ_TEST")
    }
}

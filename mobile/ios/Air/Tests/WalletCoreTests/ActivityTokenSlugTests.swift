import Foundation
import Testing
@testable import WalletCore
import WalletContext

@Suite("Activity Token Slugs")
struct ActivityTokenSlugTests {
    @Test
    func `backend swap token address is indexed by resolved token slug`() throws {
        let activity = try makeSwapActivity(to: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB")

        let idsBySlug = buildActivityIdsBySlug([activity])

        #expect(idsBySlug[TONCOIN_SLUG] == ["swap-usdt-solana:backend-swap"])
        #expect(idsBySlug[SOLANA_USDT_MAINNET_SLUG] == ["swap-usdt-solana:backend-swap"])
        #expect(idsBySlug["Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"] == nil)
        #expect(activity.shouldIncludeForSlug(SOLANA_USDT_MAINNET_SLUG))
    }

    @Test
    func `token lookup resolves default token addresses`() {
        let token = TokenStore.getToken(slugOrAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB")

        #expect(token?.slug == SOLANA_USDT_MAINNET_SLUG)
    }

    private func makeSwapActivity(to: String) throws -> ApiActivity {
        let json = """
        {
          "kind": "swap",
          "id": "swap-usdt-solana:backend-swap",
          "timestamp": 1770000000,
          "from": "\(TONCOIN_SLUG)",
          "fromAmount": "0.00045",
          "to": "\(to)",
          "toAmount": "33.58",
          "status": "completed"
        }
        """

        return try JSONDecoder().decode(ApiActivity.self, from: Data(json.utf8))
    }
}

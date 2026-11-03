import Testing
import WalletCoreTypes
@testable import AirAsFramework

@Suite("Spotlight token selection")
@MainActor
struct TokenEntityProviderTests {
    @Test
    func selectsHeldTrackedRecentAndPopularWithoutRequiringAPrice() {
        guard #available(iOS 18.4, *) else { return }
        func token(_ slug: String, popular: Bool = false) -> ApiToken {
            ApiToken(slug: slug, name: slug, symbol: slug, decimals: 6, chain: .ton, isPopular: popular)
        }
        let tokens = [token("held"), token("tracked"), token("popular", popular: true), token("irrelevant")]
        let recent = TokenEntity(token: token("recent"))
        let entries = TokenEntityProvider.entries(
            tokens: Dictionary(uniqueKeysWithValues: tokens.map { ($0.slug, $0) }),
            held: ["held"], tracked: ["held", "tracked"], recent: [recent]
        )
        let ids = entries.map(\.entity.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(["held", "tracked", "popular", "recent", ApiChain.solana.nativeToken.slug]).isSubset(of: Set(ids)))
        #expect(!ids.contains("irrelevant"))
        #expect(entries.first { $0.entity.id == "held" }?.priority == 10)
    }
}

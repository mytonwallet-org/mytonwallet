import Foundation
import Testing
@testable import UIToken
import WalletContext
import WalletCore

@MainActor
@Suite("Token Info State")
struct TokenInfoStateTests {
    @Test
    func `missing description keeps available details expandable`() {
        let details = makeDetails(marketCap: 7_580_000_000)

        let state = TokenInfoState.resolved(details: details)

        #expect(state.details == details)
        #expect(state.canExpand)
        #expect(state.description == lang("$token_info_no_description"))
    }

    @Test
    func `links count as expandable public information`() throws {
        let details = try JSONDecoder().decode(
            ApiTokenDetails.self,
            from: Data(#"{"links":[{"url":"https://example.com"}]}"#.utf8)
        )

        let state = TokenInfoState.resolved(details: details)

        #expect(state.details == details)
        #expect(state.canExpand)
        #expect(state.description == lang("$token_info_no_description"))
    }

    @Test(arguments: [true, false])
    func `missing or empty details use no public information fallback`(hasDetails: Bool) {
        let state = TokenInfoState.resolved(details: hasDetails ? makeDetails() : nil)

        #expect(state == .fallback(lang("$token_info_fallback_description")))
        #expect(!state.canExpand)
    }

    private func makeDetails(
        marketCap: Double? = nil
    ) -> ApiTokenDetails {
        ApiTokenDetails(
            description: nil,
            links: nil,
            marketCap: marketCap,
            circulatingSupply: nil,
            totalSupply: nil,
            createdAt: nil,
            volume24h: nil
        )
    }
}

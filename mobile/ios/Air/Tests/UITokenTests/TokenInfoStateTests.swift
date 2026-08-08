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

    @Test
    func `empty details use no public information fallback`() {
        let state = TokenInfoState.resolved(details: makeDetails())

        #expect(state == .fallback(lang("$token_info_fallback_description")))
        #expect(!state.canExpand)
    }

    @Test
    func `preferred expansion is restored when details finish loading`() {
        let model = TokenInfoModel(state: .loading, isExpanded: true)

        #expect(!model.isExpanded)

        model.configure(state: .details(makeDetails(marketCap: 7_580_000_000)))

        #expect(model.isExpanded)
        #expect(model.expansionProgress == 1)
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

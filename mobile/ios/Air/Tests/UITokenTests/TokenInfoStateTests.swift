import Foundation
import GRDB
import Testing
@testable import UIToken
import WalletContext
@testable import WalletCore

@MainActor
@Suite("Token Info State", .serialized, .settingsStoreIsolation)
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

    @Test(arguments: [true, false])
    func `section expansion survives reopening and loading transitions`(isExpanded: Bool) throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        AppStorageHelper.isTokenInfoExpanded = !isExpanded
        let details = TokenInfoState.details(makeDetails(description: String(repeating: "A token description. ", count: 20), marketCap: 100))
        let model = TokenInfoModel(state: details)
        model.setExpanded(isExpanded)

        let reopened = TokenInfoModel(state: details)
        #expect(reopened.isExpanded == isExpanded)
        #expect(reopened.expansionProgress == (isExpanded ? 1 : 0))
        let loading = TokenInfoModel()
        #expect(!loading.isExpanded)
        loading.configure(state: details)
        #expect(loading.isExpanded == isExpanded)
        loading.configure(state: .error)
        loading.configure(state: details)
        #expect(loading.isExpanded == isExpanded)

        let market = TokenInfoModel(state: details, hasBalance: false)
        #expect(market.isExpanded)
        #expect(!market.showsFullDescription)
        market.toggleDescription()
        #expect(market.showsFullDescription)
        let reopenedMarket = TokenInfoModel(state: details, hasBalance: false)
        #expect(reopenedMarket.isExpanded)
        #expect(!reopenedMarket.showsFullDescription)
        market.configure(state: details, hasBalance: true)
        #expect(market.isExpanded == isExpanded)
        #expect(try db.read { try MSettings.fetchOne($0)?.isTokenInfoExpanded } == isExpanded)
    }

    private func makeDetails(
        description: String? = nil,
        marketCap: Double? = nil
    ) -> ApiTokenDetails {
        ApiTokenDetails(
            description: description,
            links: nil,
            marketCap: marketCap,
            circulatingSupply: nil,
            totalSupply: nil,
            createdAt: nil,
            volume24h: nil
        )
    }

    @Test
    func `ownership controls expansion independently of description and refreshes`() {
        let details = ApiTokenDetails(description: String(repeating: "Bitcoin is a cryptocurrency. ", count: 20),
                                     links: nil, marketCap: 100, circulatingSupply: nil,
                                     totalSupply: nil, createdAt: nil, volume24h: nil)
        let model = TokenInfoModel(state: .details(details), isExpanded: false, hasBalance: false)
        #expect(model.isExpanded)
        #expect(!model.showsFullDescription)
        model.toggleDescription()
        #expect(model.showsFullDescription)
        model.configure(state: .details(details), hasBalance: false)
        #expect(model.showsFullDescription)

        model.configure(state: .details(details), hasBalance: true)
        #expect(!model.isExpanded)
        #expect(!model.showsFullDescription)
        guard case .content(let previous) = model.presentationOverlay else {
            Issue.record("Ownership transition must preserve the outgoing info card")
            return
        }
        #expect(!previous.hasBalance)
        #expect(previous.showsFullDescription)

        model.configure(state: .details(details), hasBalance: false)
        #expect(model.isExpanded)
        #expect(!model.showsFullDescription)
        model.configure(state: .loading)
        model.configure(state: .details(details))
        #expect(model.isExpanded)
    }
}

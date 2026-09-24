import Testing
@testable import WalletCore

@Suite("Activity Preview")
struct ActivityPreviewViewModelTests {
    @Test
    func `preview remains loading while cached visible count is below requested count`() {
        #expect(ActivityPreviewViewModel.resolveLoadState(
            visibleCount: 6,
            requestedCount: 10,
            isEndReached: false,
            failed: false
        ) == .loading)
    }

    @Test
    func `preview becomes exhausted only after history end is known`() {
        #expect(ActivityPreviewViewModel.resolveLoadState(
            visibleCount: 6,
            requestedCount: 10,
            isEndReached: true,
            failed: false
        ) == .exhausted)
    }

    @Test
    func `hidden tiny and scam activities do not consume the requested count`() {
        let hidden = activity(id: "hidden", shouldHide: true)
        let tiny = activity(id: "tiny", isIncoming: true)
        let firstVisible = activity(id: "visible-1")
        let scam = activity(id: "scam", isIncoming: true, isScam: true)
        let secondVisible = activity(id: "visible-2")
        let activities = [hidden, tiny, firstVisible, scam, secondVisible]
        let byId = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })

        let visibleIDs = ActivityVisibilityFilter.visibleIDs(
            activities.map(\.id),
            activitiesById: byId,
            accountId: "0-mainnet",
            token: nil,
            poisoningCache: PoisoningCache(),
            hideTinyTransfers: true
        )

        #expect(Array(visibleIDs?.prefix(2) ?? []) == ["visible-1", "visible-2"])
    }

    @Test @MainActor
    func `updates outside the preview do not change its presentation`() {
        let visible = activity(id: "visible")
        let old = presentation([visible, activity(id: "older")])
        let next = presentation([visible, activity(id: "older", comment: "updated")])
        #expect(old == next)
        #expect(old != presentation([activity(id: "visible", comment: "updated")]))
    }

    @Test @MainActor
    func `only metadata for displayed activity tokens changes the presentation`() {
        let visible = activity(id: "visible")
        let originalToken = ApiToken(slug: "toncoin", name: "Toncoin", symbol: "TON", decimals: 9, chain: .ton)
        let old = presentation([visible], tokens: ["toncoin": originalToken])
        var tokens = ["toncoin": originalToken, "unrelated": originalToken]
        tokens["unrelated"]?.image = "new-icon"
        #expect(old == presentation([visible], tokens: tokens))
        tokens["toncoin"]?.image = "new-icon"
        #expect(old != presentation([visible], tokens: tokens))
        #expect(presentation([visible]) != old)
    }

    @Test @MainActor
    func `stored NFT preview changes remain observable without an activity change`() {
        let nft = ApiNft(chain: .ton, address: "gift", isOnSale: false)
        let visible = activity(id: "visible", nft: nft)
        let old = presentation([visible])
        var resolvedNft = nft
        resolvedNft.name = "Updated gift"
        #expect(old != presentation([visible], resolveNft: { _ in resolvedNft }))
    }

    @Test @MainActor
    func `currency changes update populated previews but leave empty previews alone`() {
        let visible = activity(id: "visible")
        #expect(presentation([visible]) != presentation([visible], currency: .EUR))
        #expect(presentation([visible]) != presentation([visible], currencyRate: 2))
        #expect(presentation([]) == presentation([], currency: .EUR, currencyRate: 2))
    }

    @Test @MainActor
    func `unknown history and preview limit changes remain observable`() {
        let unknown = ActivityPreviewViewModel.Presentation(
            activityIDs: nil, activitiesById: nil, requestedCount: 1,
            baseCurrency: .USD, baseCurrencyRate: 1, token: { _ in nil }, resolveNft: { $0 }
        )
        #expect(unknown != presentation([]))
        #expect(presentation([]) != presentation([], requestedCount: 2))
    }

    @MainActor
    private func presentation(
        _ activities: [ApiActivity],
        tokens: [String: ApiToken] = [:],
        currency: MBaseCurrency = .USD,
        currencyRate: Double = 1,
        requestedCount: Int = 1,
        resolveNft: (ApiNft) -> ApiNft = { $0 }
    ) -> ActivityPreviewViewModel.Presentation {
        .init(
            activityIDs: activities.map(\.id),
            activitiesById: Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) }),
            requestedCount: requestedCount,
            baseCurrency: currency,
            baseCurrencyRate: currencyRate,
            token: { tokens[$0] },
            resolveNft: resolveNft
        )
    }

    private func activity(
        id: String,
        shouldHide: Bool = false,
        isIncoming: Bool = false,
        isScam: Bool = false,
        comment: String? = nil,
        nft: ApiNft? = nil
    ) -> ApiActivity {
        .transaction(ApiTransactionActivity(
            id: id,
            kind: "transaction",
            shouldHide: shouldHide,
            externalMsgHashNorm: nil,
            timestamp: 0,
            amount: 0,
            fromAddress: "from",
            toAddress: "to",
            comment: comment,
            encryptedComment: nil,
            fee: 0,
            slug: "toncoin",
            isIncoming: isIncoming,
            normalizedAddress: nil,
            type: nil,
            metadata: isScam ? ApiAddressInfo(name: nil, isScam: true, isMemoRequired: nil) : nil,
            nft: nft,
            status: .confirmed
        ))
    }
}

import Dependencies
import Foundation
import GRDB
import Testing
import WalletContext
@testable import WalletCore

@Suite("Minted card installation")
struct PendingCardMintsTests {
    private let start = Date(timeIntervalSince1970: 100.5)

    @Test
    func `delivery is scoped to the minting account and consumed only once`() {
        var pending = PendingCardMints()
        pending.recordSubmission(accountId: "minting", since: start)
        let delivery = activity(nft: card())
        #expect(pending.consume(accountId: "other", activities: [delivery]) == nil)
        #expect(pending.consume(accountId: "minting", activities: [delivery]) == .minted(card()))
        #expect(pending.consume(accountId: "minting", activities: [delivery]) == nil)
    }

    @Test
    func `history and unconfirmed or unrelated transfers do not complete a mint`() {
        var pending = PendingCardMints()
        pending.recordSubmission(accountId: "minting", since: start)
        let unrelated = ApiNft(chain: .ton, address: "other-nft", collectionAddress: "other", isOnSale: false)
        let ignored = [
            activity(nft: card(), timestamp: 99_000),
            activity(nft: card(), status: .pending),
            activity(nft: card(), status: .pendingTrusted),
            activity(nft: card(), status: .failed),
            activity(nft: card(), id: "mint:local", status: .confirmed),
            activity(nft: card(), isIncoming: false),
            activity(nft: card(), type: .nftTrade),
            activity(nft: unrelated),
            activity(nft: card(), slug: "trx"),
        ]
        for activity in ignored {
            #expect(pending.consume(accountId: "minting", activities: [activity]) == nil)
        }
        // Also covers a delivery already cached when the submission callback runs.
        #expect(pending.consume(accountId: "minting", activities: ignored + [activity(nft: card())]) == .minted(card()))
    }

    @Test
    func `only a confirmed refund from the mint contract clears the pending upgrade`() {
        var pending = PendingCardMints()
        pending.recordSubmission(accountId: "minting", since: start)
        #expect(pending.consume(accountId: "minting", activities: [activity(comment: MINT_CARD_REFUND_COMMENT)]) == nil)
        #expect(pending.consume(accountId: "minting", activities: [activity(from: MINT_CARD_ADDRESS, comment: "Other")]) == nil)
        #expect(pending.consume(accountId: "minting", activities: [activity(from: MINT_CARD_ADDRESS, comment: MINT_CARD_REFUND_COMMENT, status: .pending)]) == nil)
        #expect(pending.consume(accountId: "minting", activities: [activity(from: MINT_CARD_ADDRESS, comment: MINT_CARD_REFUND_COMMENT)]) == .refunded)
        #expect(pending.consume(accountId: "minting", activities: [activity(nft: card())]) == nil)
    }

    @Test
    func `delivery takes precedence over a refund in the same update as on web`() {
        var pending = PendingCardMints()
        pending.recordSubmission(accountId: "minting", since: start)
        #expect(pending.consume(accountId: "minting", activities: [
            activity(from: MINT_CARD_ADDRESS, comment: MINT_CARD_REFUND_COMMENT),
            activity(nft: card()),
        ]) == .minted(card()))
    }

    @Test
    func `removing an account clears its pending mint only`() {
        var pending = PendingCardMints()
        pending.recordSubmission(accountId: "removed", since: start)
        pending.recordSubmission(accountId: "kept", since: start)
        pending.remove(accountId: "removed")
        #expect(pending.consume(accountId: "removed", activities: [activity(nft: card())]) == nil)
        #expect(pending.consume(accountId: "kept", activities: [activity(nft: card())]) == .minted(card()))
    }

    @Test @MainActor
    func `a minted card replaces the existing background and accent on its account`() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            for accountId in ["minting", "other"] {
                try MAccount(id: accountId, title: accountId, type: .view, byChain: ["ton": AccountChain(address: accountId)]).insert(db)
            }
        }
        let settingsStore = AccountSettingsStore()
        await settingsStore.use(db: db)
        await withDependencies {
            $0[AccountSettingsStore.self] = settingsStore
            $0.accountStore = _AccountStore(db: db)
        } operation: {
            let settings = settingsStore.for(accountId: "minting")
            let other = settingsStore.for(accountId: "other")
            let oldCard = card(address: "old-card")
            settings.setBackgroundNft(oldCard)
            settings.setAccentColorNft(oldCard)
            other.setBackgroundNft(oldCard)
            other.setAccentColorNft(oldCard)

            let store = _NftStore()
            store.installMtwCardIfNeeded(accountId: "minting", nft: card())
            #expect(settings.backgroundNft == oldCard)
            #expect(settings.accentColorNft == oldCard)

            store.installMtwCardIfNeeded(accountId: "minting", nft: card(), replacingCurrent: true)
            #expect(settings.backgroundNft == card())
            #expect(settings.accentColorNft == card())
            settings.setAccentColorIndex(index: ACCENT_GOLD_INDEX, for: card())
            settings.setAccentColorIndex(index: ACCENT_SILVER_INDEX, for: oldCard)
            #expect(settings.accentColorIndex == ACCENT_GOLD_INDEX)
            #expect(other.backgroundNft == oldCard)
            #expect(other.accentColorNft == oldCard)
        }
    }

    private func card(address: String = "minted-card") -> ApiNft {
        ApiNft(chain: .ton, address: address, collectionAddress: MTW_CARDS_COLLECTION, isOnSale: false)
    }

    private func activity(
        nft: ApiNft? = nil,
        timestamp: Int64 = 100_000,
        id: String = "delivery",
        from: String = "sender",
        comment: String? = nil,
        status: ApiTransactionStatus = .completed,
        isIncoming: Bool = true,
        slug: String = "toncoin",
        type: ApiTransactionType? = nil
    ) -> ApiActivity {
        .transaction(.init(
            id: id, kind: "transaction", externalMsgHashNorm: nil,
            timestamp: timestamp, amount: 0, fromAddress: from, toAddress: "wallet",
            comment: comment, encryptedComment: nil, fee: 0, slug: slug,
            isIncoming: isIncoming, normalizedAddress: nil, type: type,
            metadata: nil, nft: nft, status: status
        ))
    }
}

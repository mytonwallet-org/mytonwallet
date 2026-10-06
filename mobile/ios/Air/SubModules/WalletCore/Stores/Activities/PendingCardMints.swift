import Foundation
import Perception
import WalletContext

@Perceptible
final class PendingCardMints: Sendable {
    enum Resolution: Equatable {
        case minted(ApiNft)
        case refunded
    }

    private let startedAtByAccountId = UnfairLock<[String: Int64]>(initialState: [:])

    func isMinting(accountId: String) -> Bool {
        access(keyPath: \.startedAtByAccountId)
        return startedAtByAccountId.withLock { $0[accountId] != nil }
    }

    func recordSubmission(accountId: String, since date: Date) {
        // TON timestamps have second precision, unlike the local submission time.
        withMutation(keyPath: \.startedAtByAccountId) {
            startedAtByAccountId.withLock { $0[accountId] = Int64(date.timeIntervalSince1970.rounded(.down)) * 1_000 }
        }
    }

    func remove(accountId: String) {
        withMutation(keyPath: \.startedAtByAccountId) {
            startedAtByAccountId.withLock { $0[accountId] = nil }
        }
    }

    func removeAll() {
        withMutation(keyPath: \.startedAtByAccountId) {
            startedAtByAccountId.withLock { $0.removeAll() }
        }
    }

    func consume(accountId: String, activities: some Collection<ApiActivity>) -> Resolution? {
        guard let startedAt = startedAtByAccountId.withLock({ $0[accountId] }) else { return nil }
        let transactions = activities.compactMap { activity -> ApiTransactionActivity? in
            guard !activity.isLocal,
                  activity.isConfirmedOrCompleted,
                  activity.timestamp >= startedAt,
                  activity.shouldHide != true,
                  case .transaction(let transaction) = activity,
                  transaction.isIncoming,
                  transaction.type != .nftTrade,
                  getChainBySlug(transaction.slug) == .ton
            else { return nil }
            return transaction
        }
        if let nft = transactions.compactMap(\.nft).first(where: {
            $0.chain == .ton && $0.collectionAddress == MTW_CARDS_COLLECTION
        }) {
            remove(accountId: accountId)
            return .minted(nft)
        }
        if transactions.contains(where: {
            $0.fromAddress == MINT_CARD_ADDRESS && $0.comment == MINT_CARD_REFUND_COMMENT
        }) {
            remove(accountId: accountId)
            return .refunded
        }
        return nil
    }
}

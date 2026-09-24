import Foundation
import WalletContext

struct PendingCardMints: Sendable {
    enum Resolution: Equatable {
        case minted(ApiNft)
        case refunded
    }

    private var startedAtByAccountId: [String: Int64] = [:]

    mutating func recordSubmission(accountId: String, since date: Date) {
        // TON timestamps have second precision, unlike the local submission time.
        startedAtByAccountId[accountId] = Int64(date.timeIntervalSince1970.rounded(.down)) * 1_000
    }

    mutating func remove(accountId: String) {
        startedAtByAccountId[accountId] = nil
    }

    mutating func consume(accountId: String, activities: some Collection<ApiActivity>) -> Resolution? {
        guard let startedAt = startedAtByAccountId[accountId] else { return nil }
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

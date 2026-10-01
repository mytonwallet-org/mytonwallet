import WalletContext

struct ActivityVisibilityFilter {
    static func visibleIDs(
        _ ids: [String]?,
        activitiesById: [String: ApiActivity]?,
        accountId: String,
        token: ApiToken?,
        poisoningCache: PoisoningCache,
        hideTinyTransfers: Bool,
        limit: Int? = nil
    ) -> [String]? {
        guard let ids else { return nil }
        if let limit, limit <= 0 { return [] }
        let visible = ids.lazy.filter { id in
            guard let activity = activitiesById?[id] else { return false }

            switch activity {
            case .transaction(let transaction):
                if activity.shouldHide == true {
                    return false
                }
                if NftStore.shouldHideTransaction(accountId: accountId, transaction: transaction) {
                    return false
                }
                if poisoningCache.isTransactionWithPoisoning(transaction: transaction) {
                    return false
                }
                if hideTinyTransfers {
                    let tokenPriceUsd = TokenStore.tokens[activity.slug]?.priceUsd
                    if token != nil && tokenPriceUsd == 0 {
                        // Token pages should not hide zero-value tokens.
                        return true
                    }
                    return !activity.isTinyOrScamTransaction
                }
                return true

            case .swap:
                return activity.shouldHide != true
            }
        }
        return Array(visible.prefix(limit ?? ids.count))
    }
}

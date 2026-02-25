
import WalletContext

struct PoisoningCache {
    
    private struct Entry: Sendable {
        let address: String
        let amount: BigInt
        let timestamp: Int64
    }

    private let addressShift = 4
    private var cache: [String: Entry] = [:]
    
    init() {}

    func isTransactionWithPoisoning(transaction: ApiTransactionActivity) -> Bool {
        guard let fromAddress = transaction.fromAddress else { return false }
        let key = makeKey(address: fromAddress)
        guard let cached = cache[key] else { return false }
        return cached.address != fromAddress
    }

    mutating func update(activities: some Collection<ApiActivity>) {
        for activity in activities {
            update(activity: activity)
        }
    }

    private mutating func update(activity: ApiActivity) {
        guard case .transaction(let transaction) = activity else { return }
        guard !getIsActivityPending(activity) else { return }
        update(transaction: transaction)
    }

    private mutating func update(transaction: ApiTransactionActivity) {
        let address = transaction.isIncoming ? transaction.fromAddress : transaction.toAddress
        guard let address else { return }
        update(address: address, amount: transaction.amount, timestamp: transaction.timestamp)
    }

    private mutating func update(address: String, amount: BigInt, timestamp: Int64) {
        let key = makeKey(address: address)
        if let cached = cache[key] {
            if cached.timestamp > timestamp || (cached.timestamp == timestamp && cached.amount < amount) {
                cache[key] = Entry(address: address, amount: amount, timestamp: timestamp)
            }
        } else {
            cache[key] = Entry(address: address, amount: amount, timestamp: timestamp)
        }
    }

    private func makeKey(address: String) -> String {
        formatStartEndAddress(address, prefix: addressShift, suffix: addressShift)
    }
}

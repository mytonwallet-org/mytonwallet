import WalletContext

struct ByAccountIdStore<T: AnyObject & Sendable>: Sendable {
    
    let _byAccountId: UnfairLock<[String: T]> = .init(initialState: [:])
    
    private let initialValue: @Sendable (String) -> T
    
    init(initialValue: @escaping @Sendable (String) -> T) {
        self.initialValue = initialValue
    }
    
    func `for`(accountId: String) -> T {
        _byAccountId.withLock {
            if let value = $0[accountId] {
                return value
            } else {
                let value = initialValue(accountId)
                $0[accountId] = value
                return value
            }
        }
    }

    func existing(accountId: String) -> T? {
        _byAccountId.withLock { $0[accountId] }
    }

    func remove(accountId: String) {
        _byAccountId.withLock {
            $0[accountId] = nil
        }
    }

    func removeAll() {
        _byAccountId.withLock { $0 = [:] }
    }

    func accountIds() -> [String] {
        _byAccountId.withLock { Array($0.keys) }
    }
}

struct MainActorByAccountIdStore<T: AnyObject & Sendable> {
    
    private var byAccountId: [String: T] = [:]
    
    private let initialValue: @Sendable (String) -> T
    
    nonisolated init(initialValue: @escaping @Sendable (String) -> T) {
        self.initialValue = initialValue
    }
    
    mutating func `for`(accountId: String) -> T {
        if let value = byAccountId[accountId] {
            return value
        } else {
            let value = initialValue(accountId)
            byAccountId[accountId] = value
            return value
        }
    }

    mutating func existing(accountId: String) -> T? {
        byAccountId[accountId]
    }

    mutating func remove(accountId: String) {
        byAccountId[accountId] = nil
    }

    mutating func removeAll() {
        byAccountId = [:]
    }

    func accountIds() -> [String] {
        Array(byAccountId.keys)
    }
}

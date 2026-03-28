import Dependencies
import Foundation
import GRDB
import Perception
import WalletContext

private let log = Log("BalancesStore")

var BalancesStore: _BalancesStore { _BalancesStore.shared }

public final class AccountBalances: Sendable {
    @Perceptible
    public final class State: Sendable {
        private let _byChain: UnfairLock<[ApiChain: [String: BigInt]]> = .init(initialState: [:])

        nonisolated init() {}

        public var byChain: [ApiChain: [String: BigInt]] {
            access(keyPath: \._byChain)
            return _byChain.withLock { $0 }
        }

        fileprivate func replace(chain: ApiChain, balances: [String: BigInt]) {
            withMutation(keyPath: \._byChain) {
                _byChain.withLock { $0[chain] = balances }
            }
        }

        fileprivate func replaceAll(byChain: [ApiChain: [String: BigInt]]) {
            withMutation(keyPath: \._byChain) {
                _byChain.withLock { $0 = byChain }
            }
        }
    }

    public let accountId: String
    public let state = State()

    init(accountId: String) {
        self.accountId = accountId
    }

    public var byChain: [ApiChain: [String: BigInt]] {
        state.byChain
    }

    public var balances: [String: BigInt] {
        Self.flatten(byChain: state.byChain)
    }

    func replace(chain: ApiChain, balances: [String: BigInt]) {
        state.replace(chain: chain, balances: balances)
    }

    func replaceAll(byChain: [ApiChain: [String: BigInt]]) {
        state.replaceAll(byChain: byChain)
    }

    private static func flatten(byChain: [ApiChain: [String: BigInt]]) -> [String: BigInt] {
        var result: [String: BigInt] = [:]
        for chainBalances in byChain.values {
            for (slug, value) in chainBalances {
                result[slug] = value
            }
        }
        return result
    }
}

public actor _BalancesStore: WalletCoreData.EventsObserver {
    static let shared = _BalancesStore()

    nonisolated private let byAccountId: ByAccountIdStore<AccountBalances> = .init(initialValue: { AccountBalances(accountId: $0) })
    private var db: (any DatabaseWriter)?

    private init() {}

    public func use(db: any DatabaseWriter) {
        self.db = db
        loadFromDb()

        WalletCoreData.add(eventObserver: self)
    }

    public func clean() {
        byAccountId.removeAll()
    }

    public nonisolated func `for`(accountId: String) -> AccountBalances {
        byAccountId.for(accountId: accountId)
    }

    public nonisolated func getAccountBalances(accountId: String) -> [String: BigInt] {
        self.for(accountId: accountId).balances
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) {
        switch event {
        case .updateBalances(let update):
            handleUpdate(update)
        case .accountDeleted(let accountId):
            handleAccountDeleted(accountId: accountId)
        case .accountsReset:
            clean()
        default:
            break
        }
    }

    private func handleUpdate(_ update: ApiUpdate.UpdateBalances) {
        let accountId = update.accountId
        applyInMemory(accountId: accountId, chain: update.chain, balances: update.balances)

        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let row = MAccountBalances(
                accountId: accountId,
                chain: update.chain,
                balances: update.balances,
                updatedAt: .now
            )
            try db.write { db in
                try row.upsert(db)
            }
        } catch {
            log.error("handleUpdate failed accountId=\(accountId, .public) chain=\(update.chain.rawValue, .public) error=\(error, .public)")
        }

        WalletCoreData.notify(event: .rawBalancesChanged(accountId: accountId))
    }

    private func handleAccountDeleted(accountId: String) {
        byAccountId.existing(accountId: accountId)?.replaceAll(byChain: [:])
        byAccountId.remove(accountId: accountId)
    }

    private func applyInMemory(accountId: String, chain: ApiChain, balances: [String: BigInt]) {
        byAccountId.for(accountId: accountId).replace(chain: chain, balances: balances)
    }

    private func loadFromDb() {
        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let rows = try db.read { db in
                try MAccountBalances.fetchAll(db)
            }
            var balancesByAccountId: [String: [ApiChain: [String: BigInt]]] = [:]
            for row in rows {
                balancesByAccountId[row.accountId, default: [:]][row.chain] = row.balances
            }
            for (accountId, byChain) in balancesByAccountId {
                byAccountId.for(accountId: accountId).replaceAll(byChain: byChain)
            }
        } catch {
            log.error("balances initial load: \(error, .public)")
        }
    }

}

extension _BalancesStore: DependencyKey {
    public static let liveValue: _BalancesStore = .shared
}

public extension DependencyValues {
    var balancesStore: _BalancesStore {
        get { self[_BalancesStore.self] }
        set { self[_BalancesStore.self] = newValue }
    }
}

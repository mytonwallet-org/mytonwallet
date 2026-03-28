import Dependencies
import Foundation
import GRDB
import Perception
import WalletContext

public let StakingStore = _StakingStore.shared

private let log = Log("StakingStore")

public final class AccountStaking: Sendable {
    @Perceptible
    public final class State: Sendable {
        private let _data: UnfairLock<MStakingData?> = .init(initialState: nil)

        nonisolated init() {}

        public var data: MStakingData? {
            access(keyPath: \._data)
            return _data.withLock { $0 }
        }

        fileprivate func replace(_ data: MStakingData?) {
            withMutation(keyPath: \._data) {
                _data.withLock { $0 = data }
            }
        }
    }

    public let accountId: String
    public let state = State()

    init(accountId: String) {
        self.accountId = accountId
    }

    public var data: MStakingData? {
        state.data
    }

    func replace(_ data: MStakingData?) {
        state.replace(data)
    }
}

public actor _StakingStore: WalletCoreData.EventsObserver {
    fileprivate static let shared = _StakingStore()

    nonisolated private let byAccountId: ByAccountIdStore<AccountStaking> = .init(initialValue: { AccountStaking(accountId: $0) })
    private var db: (any DatabaseWriter)?

    private init() {}

    public nonisolated func stakingData(accountId: String) -> MStakingData? {
        byAccountId.for(accountId: accountId).data
    }

    public func use(db: any DatabaseWriter) {
        self.db = db
        loadFromDb()
        WalletCoreData.add(eventObserver: self)
    }

    public func clean() {
        byAccountId.removeAll()
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) {
        switch event {
        case .updateStaking(let update):
            handleUpdate(update)
        case .accountDeleted(let accountId):
            handleAccountDeleted(accountId: accountId)
        case .accountsReset:
            clean()
        default:
            break
        }
    }

    private func handleUpdate(_ update: ApiUpdate.UpdateStaking) {
        let stakingData = MStakingData(
            accountId: update.accountId,
            stateById: update.states.dictionaryByKey(\.id),
            totalProfit: update.totalProfit,
            shouldUseNominators: update.shouldUseNominators
        )

        applyInMemory(stakingData)

        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            try db.write { db in
                try stakingData.upsert(db)
            }
        } catch {
            log.error("handleUpdate failed accountId=\(update.accountId, .public) error=\(error, .public)")
        }
    }

    private func handleAccountDeleted(accountId: String) {
        byAccountId.existing(accountId: accountId)?.replace(nil)
        byAccountId.remove(accountId: accountId)
    }

    private func applyInMemory(_ stakingData: MStakingData) {
        byAccountId.for(accountId: stakingData.accountId).replace(stakingData)
        WalletCoreData.notify(event: .stakingAccountData(stakingData))
    }

    private func loadFromDb() {
        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let rows = try db.read { db in
                try MStakingData.fetchAll(db)
            }
            for stakingData in rows {
                applyInMemory(stakingData)
            }
        } catch {
            log.error("staking initial load: \(error, .public)")
        }
    }
}

extension _StakingStore: DependencyKey {
    public static let liveValue: _StakingStore = .shared
}

public extension DependencyValues {
    var stakingStore: _StakingStore {
        get { self[_StakingStore.self] }
        set { self[_StakingStore.self] = newValue }
    }
}

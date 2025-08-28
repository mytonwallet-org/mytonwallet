
import GRDB
import Foundation
import WalletContext
import os

public let StakingStore = _StakingStore.shared

private let log = Log("StakingStore")

public final class _StakingStore: WalletCoreData.EventsObserver {
    
    fileprivate static let shared = _StakingStore()
    
    private var _byId: UnfairLock<[String: MStakingData]> = .init(initialState: [:])
    public func byId(_ accountId: String) -> MStakingData? { _byId.withLock { $0[accountId] } }
    public var currentAccount: MStakingData? {
        if let accountId = AccountStore.accountId {
            return _byId.withLock { $0[accountId] }
        }
        return nil
    }
    
    private var _db: (any DatabaseWriter)?
    private var db: any DatabaseWriter {
        get throws {
            try _db.orThrow("database not ready")
        }
    }
    private var commonDataObservation: Task<Void, Never>?
    private var accountsObservation: Task<Void, Never>?

    private init() {
    }
    
    // MARK: - Database
    
    public func use(db: any DatabaseWriter) {
        self._db = db

        do {
            let fetchAccountStaking = { db in
                try MStakingData.fetchAll(db)
            }
            
            do {
                let accountStaking = try db.read(fetchAccountStaking)
                updateFromDb(accountStaking: accountStaking)
            } catch {
                log.error("accountStaking intial load: \(error, .public)")
            }

            let observation = ValueObservation.tracking(fetchAccountStaking)
            accountsObservation = Task { [weak self] in
                do {
                    for try await accountStaking in observation.values(in: db) {
                        self?.updateFromDb(accountStaking: accountStaking)
                    }
                } catch {
                    log.error("accountStaking: \(error, .public)")
                }
            }
        }

        WalletCoreData.add(eventObserver: self)
    }
    
    private func updateFromDb(accountStaking: [MStakingData]) {
        var byId: [String: MStakingData] = [:]
        for stakingData in accountStaking {
            byId[stakingData.accountId] = stakingData
        }
        self._byId.withLock { [byId] in
            $0 = byId
        }
        notifyObserversAllAccounts()
    }
    
    // MARK: - Events
    
    public func walletCore(event: WalletCoreData.Event) {
        Task { await self.handleEvent(event) }
    }
    
    func handleEvent(_ event: WalletCoreData.Event) async {
        do {
            switch event {
            case .updateStaking(let update):
                let stakingData = MStakingData(
                    accountId: update.accountId,
                    stateById: update.states.dictionaryByKey(\.id),
                    totalProfit: update.totalProfit,
                    shouldUseNominators: update.shouldUseNominators
                )
                try await db.write { db in
                    try stakingData.upsert(db)
                }
            default:
                break
            }
        } catch {
            log.info("handleEvent: \(error)")
        }
    }
    
    private func notifyObserversAllAccounts() {
        let byId = self._byId.withLock { $0 }
        for (accountId, data) in byId {
            WalletCoreData.notify(event: .stakingAccountData(data), for: accountId)
        }
    }
    private func notifyObserversAccount(_ accountId: String) {
        if let data = byId(accountId) {
            WalletCoreData.notify(event: .stakingAccountData(data), for: accountId)
        }
    }
}

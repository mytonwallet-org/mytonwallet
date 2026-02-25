
import GRDB
import Foundation
import WalletContext
import os
import Dependencies

public let StakingStore = _StakingStore.shared

private let log = Log("StakingStore")

public final class _StakingStore: WalletCoreData.EventsObserver {
    fileprivate static let shared = _StakingStore()
    
    private let _stakingData = UnfairLock<ValueFetchingState<[String: MStakingData]>>(initialState: .notSet)
    public func stakingData(forAccountID accountId: String) -> MStakingData? {
        _stakingData.withLock { dataSate in
            switch dataSate {
            case .notSet: nil
            case .data(let stakingData): stakingData[accountId]
            }
        }
    }
    
    public var isStakingDataLoaded: Bool {
        _stakingData.withLock { dataState in
            switch dataState {
            case .notSet: false
            case .data: true
            }
        }
    }
    
    private var _db: (any DatabaseWriter)?
    private var db: any DatabaseWriter {
        get throws {
            try _db.orThrow("database not ready")
        }
    }
    private var commonDataObservation: Task<Void, Never>?
    private var accountsObservation: Task<Void, Never>?

    private init() {}
    
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
        guard !accountStaking.isEmpty else { return } // lots of calls with empty array on app start
        
        let byId = mutate(value: [String: MStakingData]()) {
            for stakingData in accountStaking {
                $0[stakingData.accountId] = stakingData
            }
        }
        
        self._stakingData.withLock { dataState in dataState = .data(byId) }
        notifyObserversAllAccounts(stakingData: byId)
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
    
    private func notifyObserversAllAccounts(stakingData: [String: MStakingData]) {
        stakingData.values.forEach { accountStaking in
            WalletCoreData.notify(event: .stakingAccountData(accountStaking))
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

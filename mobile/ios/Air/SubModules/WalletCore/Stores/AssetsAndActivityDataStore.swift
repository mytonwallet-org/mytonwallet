import Dependencies
import Foundation
import GRDB
import Perception
import WalletContext

private let log = Log("AssetsAndActivityDataStore")

public var AssetsAndActivityDataStore: _AssetsAndActivityDataStore { _AssetsAndActivityDataStore.shared }

public final class AccountAssetsAndActivityData: Sendable {
    @Perceptible
    public final class State: Sendable {
        private let _data: UnfairLock<MAssetsAndActivityData?> = .init(initialState: nil)
        private let _didAutoPinStaking: UnfairLock<Bool> = .init(initialState: false)
        private let _ownedMtwCardAddresses: UnfairLock<[String]> = .init(initialState: [])

        nonisolated init() {}

        public var data: MAssetsAndActivityData? {
            access(keyPath: \._data)
            return _data.withLock { $0 }
        }

        public var didAutoPinStaking: Bool {
            access(keyPath: \._didAutoPinStaking)
            return _didAutoPinStaking.withLock { $0 }
        }

        public var ownedMtwCardAddresses: [String] {
            access(keyPath: \._ownedMtwCardAddresses)
            return _ownedMtwCardAddresses.withLock { $0 }
        }

        fileprivate func replace(
            data: MAssetsAndActivityData?,
            didAutoPinStaking: Bool,
            ownedMtwCardAddresses: [String]
        ) {
            withMutation(keyPath: \._data) {
                _data.withLock { $0 = data }
            }
            withMutation(keyPath: \._didAutoPinStaking) {
                _didAutoPinStaking.withLock { $0 = didAutoPinStaking }
            }
            withMutation(keyPath: \._ownedMtwCardAddresses) {
                _ownedMtwCardAddresses.withLock { $0 = ownedMtwCardAddresses }
            }
        }
    }

    public let accountId: String
    public let state = State()

    init(accountId: String) {
        self.accountId = accountId
    }

    public var data: MAssetsAndActivityData? {
        state.data
    }

    public var didAutoPinStaking: Bool {
        state.didAutoPinStaking
    }

    public var ownedMtwCardAddresses: [String] {
        state.ownedMtwCardAddresses
    }

    func replace(data: MAssetsAndActivityData?, didAutoPinStaking: Bool, ownedMtwCardAddresses: [String]) {
        state.replace(
            data: data,
            didAutoPinStaking: didAutoPinStaking,
            ownedMtwCardAddresses: ownedMtwCardAddresses
        )
    }
}

public actor _AssetsAndActivityDataStore: WalletCoreData.EventsObserver {
    public static let shared = _AssetsAndActivityDataStore()

    private let byAccountId: ByAccountIdStore<AccountAssetsAndActivityData> = .init(initialValue: { AccountAssetsAndActivityData(accountId: $0) })
    private var db: (any DatabaseWriter)?

    private init() {}

    public nonisolated func `for`(accountId: String) -> AccountAssetsAndActivityData {
        byAccountId.for(accountId: accountId)
    }

    public nonisolated func data(accountId: String) -> MAssetsAndActivityData? {
        self.for(accountId: accountId).data
    }

    public nonisolated func didAutoPinStaking(accountId: String) -> Bool {
        self.for(accountId: accountId).didAutoPinStaking
    }

    public nonisolated func ownedMtwCardAddresses(accountId: String) -> [String] {
        self.for(accountId: accountId).ownedMtwCardAddresses
    }

    public func use(db: any DatabaseWriter) {
        self.db = db
        loadFromDb()
        WalletCoreData.add(eventObserver: self)
    }

    public func clean() {
        byAccountId.removeAll()
    }

    public nonisolated func update(accountId: String, update: @escaping @Sendable (inout MAssetsAndActivityData) -> Void) {
        Task { await self._update(accountId: accountId, update: update) }
    }

    public nonisolated func autoPinStakingIfNeeded(accountId: String, slugs: [String]) {
        Task { await self._autoPinStakingIfNeeded(accountId: accountId, slugs: slugs) }
    }

    public func addOwnedMtwCardAddressIfNeeded(accountId: String, address: String) -> Bool {
        let current = ownedMtwCardAddresses(accountId: accountId)
        guard !current.contains(address) else {
            return false
        }
        persistOwnedMtwCardAddresses(accountId: accountId, addresses: current + [address])
        return true
    }

    public func setOwnedMtwCardAddresses(accountId: String, addresses: [String]) {
        persistOwnedMtwCardAddresses(accountId: accountId, addresses: unique(addresses))
    }

    public func pruneOwnedMtwCardAddress(accountId: String, address: String) {
        let current = ownedMtwCardAddresses(accountId: accountId)
        guard current.contains(address) else {
            return
        }
        persistOwnedMtwCardAddresses(accountId: accountId, addresses: current.filter { $0 != address })
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) {
        switch event {
        case .accountDeleted(let accountId):
            byAccountId.existing(accountId: accountId)?.replace(
                data: nil,
                didAutoPinStaking: false,
                ownedMtwCardAddresses: []
            )
            byAccountId.remove(accountId: accountId)
        case .accountsReset:
            clean()
        default:
            break
        }
    }

    private func _update(accountId: String, update: @escaping @Sendable (inout MAssetsAndActivityData) -> Void) {
        let context = byAccountId.for(accountId: accountId)
        var next = context.data ?? .empty
        update(&next)
        persist(
            accountId: accountId,
            data: next,
            didAutoPinStaking: context.didAutoPinStaking,
            ownedMtwCardAddresses: context.ownedMtwCardAddresses
        )
    }

    private func _autoPinStakingIfNeeded(accountId: String, slugs: [String]) {
        guard !slugs.isEmpty else { return }
        let context = byAccountId.for(accountId: accountId)
        guard !context.didAutoPinStaking else { return }
        var next = context.data ?? .empty
        if next.hasPinnedTokens {
            persist(
                accountId: accountId,
                data: next,
                didAutoPinStaking: true,
                ownedMtwCardAddresses: context.ownedMtwCardAddresses
            )
            return
        }
        for slug in slugs {
            next.saveTokenPinning(slug: slug, isStaking: true, isPinned: true)
        }
        persist(
            accountId: accountId,
            data: next,
            didAutoPinStaking: true,
            ownedMtwCardAddresses: context.ownedMtwCardAddresses
        )
    }

    private func persistOwnedMtwCardAddresses(accountId: String, addresses: [String]) {
        let context = byAccountId.for(accountId: accountId)
        persist(
            accountId: accountId,
            data: context.data ?? .empty,
            didAutoPinStaking: context.didAutoPinStaking,
            ownedMtwCardAddresses: addresses
        )
    }

    private func persist(
        accountId: String,
        data: MAssetsAndActivityData,
        didAutoPinStaking: Bool,
        ownedMtwCardAddresses: [String]
    ) {
        let context = byAccountId.for(accountId: accountId)
        let dataChanged = context.data != data
        let autoPinChanged = context.didAutoPinStaking != didAutoPinStaking
        let ownedMtwCardsChanged = context.ownedMtwCardAddresses != ownedMtwCardAddresses
        guard dataChanged || autoPinChanged || ownedMtwCardsChanged else { return }

        context.replace(
            data: data,
            didAutoPinStaking: didAutoPinStaking,
            ownedMtwCardAddresses: ownedMtwCardAddresses
        )

        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let row = MAccountAssetsAndActivityData(
                accountId: accountId,
                data: data,
                didAutoPinStaking: didAutoPinStaking,
                ownedMtwCardAddresses: ownedMtwCardAddresses
            )
            try db.write { db in
                try row.upsert(db)
            }
        } catch {
            log.error("save failed accountId=\(accountId, .public) error=\(error, .public)")
        }

        if dataChanged {
            WalletCoreData.notify(event: .assetsAndActivityDataUpdated)
        }
    }

    private func loadFromDb() {
        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let rows = try db.read { db in
                try MAccountAssetsAndActivityData.fetchAll(db)
            }
            for row in rows {
                byAccountId.for(accountId: row.accountId).replace(
                    data: row.data,
                    didAutoPinStaking: row.didAutoPinStaking,
                    ownedMtwCardAddresses: row.ownedMtwCardAddresses
                )
            }
        } catch {
            log.error("initial load failed: \(error, .public)")
        }
    }
}

extension _AssetsAndActivityDataStore: DependencyKey {
    public static let liveValue: _AssetsAndActivityDataStore = .shared
}

public extension DependencyValues {
    var assetsAndActivityDataStore: _AssetsAndActivityDataStore {
        get { self[_AssetsAndActivityDataStore.self] }
        set { self[_AssetsAndActivityDataStore.self] = newValue }
    }
}

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

        nonisolated init() {}

        public var data: MAssetsAndActivityData? {
            access(keyPath: \._data)
            return _data.withLock { $0 }
        }

        public var didAutoPinStaking: Bool {
            access(keyPath: \._didAutoPinStaking)
            return _didAutoPinStaking.withLock { $0 }
        }

        fileprivate func replace(data: MAssetsAndActivityData?, didAutoPinStaking: Bool) {
            withMutation(keyPath: \._data) {
                _data.withLock { $0 = data }
            }
            withMutation(keyPath: \._didAutoPinStaking) {
                _didAutoPinStaking.withLock { $0 = didAutoPinStaking }
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

    func replace(data: MAssetsAndActivityData?, didAutoPinStaking: Bool) {
        state.replace(data: data, didAutoPinStaking: didAutoPinStaking)
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

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) {
        switch event {
        case .accountDeleted(let accountId):
            byAccountId.existing(accountId: accountId)?.replace(data: nil, didAutoPinStaking: false)
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
        persist(accountId: accountId, data: next, didAutoPinStaking: context.didAutoPinStaking)
    }

    private func _autoPinStakingIfNeeded(accountId: String, slugs: [String]) {
        guard !slugs.isEmpty else { return }
        let context = byAccountId.for(accountId: accountId)
        guard !context.didAutoPinStaking else { return }
        var next = context.data ?? .empty
        if next.hasPinnedTokens {
            persist(accountId: accountId, data: next, didAutoPinStaking: true)
            return
        }
        for slug in slugs {
            next.saveTokenPinning(slug: slug, isStaking: true, isPinned: true)
        }
        persist(accountId: accountId, data: next, didAutoPinStaking: true)
    }

    private func persist(accountId: String, data: MAssetsAndActivityData, didAutoPinStaking: Bool) {
        let context = byAccountId.for(accountId: accountId)
        let dataChanged = context.data != data
        let autoPinChanged = context.didAutoPinStaking != didAutoPinStaking
        guard dataChanged || autoPinChanged else { return }

        context.replace(data: data, didAutoPinStaking: didAutoPinStaking)

        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let row = MAccountAssetsAndActivityData(accountId: accountId, data: data, didAutoPinStaking: didAutoPinStaking)
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
                byAccountId.for(accountId: row.accountId).replace(data: row.data, didAutoPinStaking: row.didAutoPinStaking)
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

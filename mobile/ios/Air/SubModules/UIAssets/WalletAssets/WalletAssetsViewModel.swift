
import Foundation
import Perception
import WalletContext
import WalletCore
import GRDB

@MainActor public protocol WalletAssetsViewModelDelegate: AnyObject {
    func walletAssetModelDidChangeDisplayTabs(dueToAccountSwitch: Bool)
}

@MainActor
public final class WalletAssetsViewModel: WalletCoreData.EventsObserver {

    public struct PreparedTabs: Sendable {
        public let accountId: String
        fileprivate let snapshot: AssetTabsSnapshot?
    }

    public static func prepareTabs(accountId: String) async -> PreparedTabs {
        await prepareTabs(accountId: accountId, database: WalletCore.db)
    }

    static func prepareTabs(accountId: String, database: (any DatabaseReader)?) async -> PreparedTabs {
        let snapshot = try? await database?.read { db in
            try AssetTabsSnapshot.fetchOne(db, key: accountId)
        }
        return PreparedTabs(accountId: accountId, snapshot: snapshot)
    }
        
    public private(set) var displayTabs: [DisplayAssetTab] = []
    
    public weak var delegate: WalletAssetsViewModelDelegate?
    
    private let accountIdProvider: AccountIdProvider
    private let includesTokens: Bool
    private var accountId: String { accountIdProvider.accountId }
    private var lastEvaluatedAccountId: String?
    
    private var _tabs: [WalletAssetsTab]?
    private var isAutoTelegramGiftsHidden: Bool = false
    private var observation: Task<Void, Never>?
    
    private var tabsOrderingSnapshot: [DisplayAssetTab]?
    private var nftsOrderingSnapshot: NtfsOrderingSnapshot?
    private var _isReordering: Bool = false
    
    public var isReordering: Bool { _isReordering }
    
    // dependencies
    private var db: (any DatabaseWriter)? { WalletCore.db }
    private var nftStore: _NftStore { NftStore }
        
    public init(accountSource: AccountSource, includesTokens: Bool = true) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.includesTokens = includesTokens
        self.observedAccountId = accountIdProvider.accountId
        WalletCoreData.add(eventObserver: self)
        let snapshot = try? WalletCore.db?.read { db in
            try AssetTabsSnapshot.fetchOne(db, key: accountId)
        }
        loadTabsFromDB(snapshot)
        setupTabsObservation()
        observeAccountId()
    }

    private var observedAccountId: String

    private func observeAccountId() {
        withPerceptionTracking {
            _ = accountIdProvider.accountId
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.accountIdChanged()
                self?.observeAccountId()
            }
        }
    }

    private func accountIdChanged() {
        guard accountId != observedAccountId else { return }
        observedAccountId = accountId
        setupTabsObservation()
    }

    func switchAccountTo(_ accountId: String, preparedTabs: PreparedTabs? = nil) {
        guard accountId != observedAccountId else { return }
        observedAccountId = accountId
        accountIdProvider.accountId = accountId
        setupTabsObservation(preparedTabs: preparedTabs)
    }

    deinit {
        observation?.cancel()
    }
    
    public func startOrdering() {
        guard !isReordering else {
            assertionFailure()
            return
        }
        _isReordering = true
        
        // make backup for possible cancellation
        nftsOrderingSnapshot = nftStore.getOrderingSnapshot(accountId: accountId)
        tabsOrderingSnapshot = displayTabs
    }
    
    public func stopReordering(isCanceled: Bool, restoreTabsOnCancel: Bool = false) {
        guard isReordering else { return }

        _isReordering = false
        
        // restore orders on cancellation
        if isCanceled {
           if let nftsOrderingSnapshot {
                nftStore.restoreOrderingWithSnapshot(nftsOrderingSnapshot, accountId: accountId)
           }
           if restoreTabsOnCancel, let tabsOrderingSnapshot {
               Task { [weak self] in
                   guard let viewModel = self else { return }
                   try? await viewModel.setOrder(displayTabs: tabsOrderingSnapshot)
               }
           }
        }
    }
    
    nonisolated public func walletCore(event: WalletCoreData.Event) {
        Task { [weak self] in
            guard let viewModel = self else { return }
            await viewModel.handleEvent(event)
        }
    }
    
    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .nftsChanged(accountId: accountId):
            if self.accountId == accountId {
                updateDisplayTabs()
            }
        default:
            break
        }
    }

    private func setupTabsObservation(preparedTabs: PreparedTabs? = nil) {
        let accountId = self.accountId
        observation?.cancel()
        observation = nil
        if let preparedTabs, preparedTabs.accountId == accountId {
            loadTabsFromDB(preparedTabs.snapshot)
        } else {
            let snapshot = try? db?.read { db in
                try AssetTabsSnapshot.fetchOne(db, key: accountId)
            }
            loadTabsFromDB(snapshot)
        }
        if let db = self.db {
            let o = ValueObservation.tracking { db in
                try AssetTabsSnapshot.fetchOne(db, key: accountId)
            }
            observation = Task { [weak self] in
                do {
                    for try await snapshot in o.values(in: db) {
                        guard !Task.isCancelled, let viewModel = self,
                              viewModel.accountId == accountId else { return }
                        viewModel.loadTabsFromDB(snapshot)
                    }
                } catch {
                }
            }
        }
    }
    
    private func updateDisplayTabs() {
        let currentAccountId = accountId
        let isAccountSwitch = lastEvaluatedAccountId != nil && lastEvaluatedAccountId != currentAccountId
        lastEvaluatedAccountId = currentAccountId

        let allDisplayTabs = makeAllDisplayTabs()
        let displayTabs = allDisplayTabs.filter(isIncluded)
        let displayTabsChanged = self.displayTabs != displayTabs
        if displayTabsChanged {
            self.displayTabs = displayTabs
        }
        if displayTabsChanged || isAccountSwitch {
            delegate?.walletAssetModelDidChangeDisplayTabs(dueToAccountSwitch: isAccountSwitch)
        }
    }

    private func makeAllDisplayTabs() -> [DisplayAssetTab] {
        if let _tabs {
            _tabs.compactMap(storedTabToDisplay)
        } else if isAutoTelegramGiftsHidden {
            [.tokens, .nfts].compactMap(storedTabToDisplay)
        } else {
            [.tokens, .nfts, .nftSuperCollection(TELEGRAM_GIFTS_SUPER_COLLECTION)].compactMap(storedTabToDisplay)
        }
    }

    private func isIncluded(_ tab: DisplayAssetTab) -> Bool {
        if case .tokens = tab {
            includesTokens
        } else {
            true
        }
    }
    
    private func storedTabToDisplay(_ tab: WalletAssetsTab) -> DisplayAssetTab? {
        switch tab {
        case .tokens:
            return .tokens
        case .nfts:
            return .nfts
        case .nftCollection(let string):
            if let collection = nftStore.getAccountCollection(accountId: accountId, address: string) {
                return .nftCollectionFilter(.collection(collection))
            }
            return nil
        case .nftSuperCollection(_):
            if nftStore.hasTelegramGifts(accountId: accountId) {
                return .nftCollectionFilter(.telegramGifts)
            }
            return nil
        }
    }
    
    private nonisolated func displayTabToStored(_ tab: DisplayAssetTab) -> WalletAssetsTab? {
        switch tab {
        case .tokens:
            return .tokens
        case .nfts:
            return .nfts
        case .nftCollectionFilter(let filter):
            switch filter {
            case .none:
                return nil
            case .collection(let nftCollection):
                return .nftCollection(nftCollection.id)
            case .telegramGifts:
                return .nftSuperCollection("super:telegram-gifts")
            }
        }
    }
    
    public func isFavorited(filter: NftCollectionFilter) -> Bool {
        displayTabs.contains {
            $0 == .nftCollectionFilter(filter)
        }
    }
    
    public func setIsFavorited(filter: NftCollectionFilter, isFavorited: Bool) async throws {
        var displayTabs = makeAllDisplayTabs()
        if !displayTabs.contains(.nftCollectionFilter(filter)) && isFavorited {
            displayTabs.append(.nftCollectionFilter(filter))
        } else if !isFavorited {
            displayTabs = displayTabs.filter { $0 != .nftCollectionFilter(filter) }
        }
        try await self.saveTabsToDB(displayTabs: displayTabs)
    }

    public var isCollectiblesHidden: Bool {
        !makeAllDisplayTabs().contains(.nfts)
    }

    public func setCollectiblesHidden(_ isHidden: Bool) async throws {
        var displayTabs = makeAllDisplayTabs()
        let show = !isHidden
        if !displayTabs.contains(.nfts) && show {
            displayTabs.append(.nfts)
        } else if !show {
            displayTabs = displayTabs.filter { $0 != .nfts }
        }
        try await self.saveTabsToDB(displayTabs: displayTabs)
    }

    public func setOrder(displayTabs: [DisplayAssetTab]) async throws {
        guard !includesTokens else {
            try await saveTabsToDB(displayTabs: displayTabs)
            return
        }

        var reorderedTabs = displayTabs.makeIterator()
        var mergedTabs = makeAllDisplayTabs().compactMap { tab -> DisplayAssetTab? in
            isIncluded(tab) ? reorderedTabs.next() : tab
        }
        while let remainingTab = reorderedTabs.next() {
            mergedTabs.append(remainingTab)
        }
        try await saveTabsToDB(displayTabs: mergedTabs)
    }
    
    // MARK: - DB
    
    private func loadTabsFromDB(_ snapshot: AssetTabsSnapshot?) {
        self._tabs = snapshot?.tabs
        self.isAutoTelegramGiftsHidden = snapshot?.auto_telegram_gifts_hidden ?? false
        updateDisplayTabs()
    }
    
    private func saveTabsToDB(displayTabs: [DisplayAssetTab]) async throws {
        let accountId = self.accountId
        let stored = displayTabs.compactMap(displayTabToStored)
        try await db?.write { db in
            try AssetTabsSnapshot(account_id: accountId, tabs: stored).upsert(db)
        }
    }
}

fileprivate struct AssetTabsSnapshot: Codable, PersistableRecord, FetchableRecord, Sendable {
    var account_id: String
    var tabs: [WalletAssetsTab]?
    var auto_telegram_gifts_hidden: Bool?
    
    static let databaseTableName = "asset_tabs"
}

fileprivate enum WalletAssetsTab: Codable, Hashable, Sendable {
    case tokens
    case nfts
    case nftCollection(String)
    case nftSuperCollection(String)
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .tokens:
            try container.encode("tokens")
        case .nfts:
            try container.encode("nfts")
        case .nftCollection(let address):
            try container.encode(address)
        case .nftSuperCollection(let name):
            try container.encode(name)
        }
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if string == "tokens" {
            self = .tokens
        } else if string == "nfts" {
            self = .nfts
        } else if string.starts(with: /super:/) {
            self = .nftSuperCollection(string)
        } else {
            self = .nftCollection(string)
        }
    }
}


import Foundation
import WalletContext
import WalletCore
import GRDB

private let log = Log("WalletAssetsViewModel")

@MainActor public protocol WalletAssetsViewModelDelegate: AnyObject {
    func displayTabsChanged()
}

public enum DisplayAssetTab: Hashable {
    case tokens
    case nfts
    case nftCollectionFilter(NftCollectionFilter)
}

@MainActor
public final class WalletAssetsViewModel: WalletCoreData.EventsObserver {
    
    public static let shared = WalletAssetsViewModel()
    
    public var displayTabs: [DisplayAssetTab] = []
    
    public weak var delegate: WalletAssetsViewModelDelegate?
    
    private var accountId: String
    private var _tabs: [WalletAssetsTab]?
    private var isAutoTelegramGiftsHidden: Bool = false
    private var observation: Task<Void, Never>?
    
    // dependencies
    private var db: (any DatabaseWriter)? { WalletCore.db }
    private var nftStore: _NftStore { NftStore }
    
    public init() {
        self.accountId = AccountStore.accountId ?? DUMMY_ACCOUNT.id
        WalletCoreData.add(eventObserver: self)
        let snapshot = try? WalletCore.db?.read { db in
            try AssetTabsSnapshot.fetchOne(db, key: accountId)
        }
        self._tabs = snapshot?.tabs
        self.isAutoTelegramGiftsHidden = snapshot?.auto_telegram_gifts_hidden ?? false
        updateDisplayTabs()
        setupTabsObservation()
    }
    
    nonisolated public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }
    
    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .accountChanged(let accountId, _):
            self.accountId = accountId
            setupTabsObservation()
        case .nftsChanged(accountId: accountId):
            if self.accountId == accountId {
                updateDisplayTabs()
            }
        default:
            break
        }
    }
    
    public func changAccountTo(accountId: String) {
        self.accountId = accountId
        setupTabsObservation()
    }
    
    private func setupTabsObservation() {
        let accountId = self.accountId
        if let db = self.db {
            let snapshot = try? db.read { db in
                try AssetTabsSnapshot.fetchOne(db, key: accountId)
            }
            self._tabs = snapshot?.tabs
            self.isAutoTelegramGiftsHidden = snapshot?.auto_telegram_gifts_hidden ?? false
            updateDisplayTabs()

            observation?.cancel()
            
            let o = ValueObservation.tracking { db in
                try AssetTabsSnapshot.fetchOne(db, key: accountId)
            }
            
            observation?.cancel()
            observation = Task {
                do {
                    for try await snapshot in o.values(in: db) {
                        self._tabs = snapshot?.tabs
                        self.isAutoTelegramGiftsHidden = snapshot?.auto_telegram_gifts_hidden ?? false
                        updateDisplayTabs()
                    }
                } catch {
                }
            }
        }
    }
    
    private func updateDisplayTabs() {
        let displayTabs: [DisplayAssetTab]
        if let _tabs {
            displayTabs = _tabs.compactMap(storedTabToDisplay)
        } else if isAutoTelegramGiftsHidden {
            displayTabs = [.tokens, .nfts].compactMap(storedTabToDisplay)
        } else {
            displayTabs = [.tokens, .nfts, .nftSuperCollection(TELEGRAM_GIFTS_SUPER_COLLECTION)].compactMap(storedTabToDisplay)
        }
        if self.displayTabs != displayTabs {
            self.displayTabs = displayTabs
            delegate?.displayTabsChanged()
        }
    }
    
    func storedTabToDisplay(_ tab: WalletAssetsTab) -> DisplayAssetTab? {
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
    
    nonisolated func displayTabToStored(_ tab: DisplayAssetTab) -> WalletAssetsTab? {
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
                return .nftCollection(nftCollection.address)
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
        var displayTabs = self.displayTabs
        if !displayTabs.contains(.nftCollectionFilter(filter)) && isFavorited {
            displayTabs.append(.nftCollectionFilter(filter))
        } else if !isFavorited {
            displayTabs = displayTabs.filter { $0 != .nftCollectionFilter(filter) }
        }
        let stored = displayTabs.compactMap(displayTabToStored)
        let accountId = self.accountId
        self.displayTabs = displayTabs
        try await db?.write { db in
            try AssetTabsSnapshot(account_id: accountId, tabs: stored).upsert(db)
        }
    }
    
    public func setOrder(displayTabs: [DisplayAssetTab]) async throws {
        let stored = displayTabs.compactMap(displayTabToStored)
        let accountId = self.accountId
        try await db?.write { db in
            try AssetTabsSnapshot(account_id: accountId, tabs: stored).upsert(db)
        }
    }
}

struct AssetTabsSnapshot: Codable, PersistableRecord, FetchableRecord {
    var account_id: String
    var tabs: [WalletAssetsTab]?
    var auto_telegram_gifts_hidden: Bool?
    
    static let databaseTableName = "asset_tabs"
}

enum WalletAssetsTab: Codable, Hashable {
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

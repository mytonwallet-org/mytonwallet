//
//  NftStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Foundation
import WalletContext
import OrderedCollections

private let log = Log("NftStore")
private let DEBUG_SHOW_TEST_NFTS = true

public var NftStore: _NftStore { .shared }


public final class _NftStore: Sendable {

    public static let shared = _NftStore()
    
    private init() {
    }

    private let _nfts: UnfairLock<[String: OrderedDictionary<String, DisplayNft>]> = .init(initialState: [:])
    private var nfts: [String: OrderedDictionary<String, DisplayNft>] {
        _nfts.withLock { $0 }
    }
    public var currentAccountNfts: OrderedDictionary<String, DisplayNft>? {
        _nfts.withLock { $0[AccountStore.accountId ?? ""] }
    }
    public var currentAccountShownNfts: OrderedDictionary<String, DisplayNft>? {
        guard let currentAccountNfts else { return nil }
        return currentAccountNfts
            .filter { (_, displayNft) in
                displayNft.shouldHide == false
            }
    }
    public var currentAccountHasHiddenNfts: Bool {
        guard let currentAccountNfts else { return false }
        return currentAccountNfts.contains { _, displayNft in
            displayNft.isUnhiddenByUser == true || displayNft.shouldHide == true
        }
    }
    public var currentAccountHiddenNftsCount: Int {
        guard let currentAccountNfts else { return 0 }
        return currentAccountNfts.count { _, displayNft in
            displayNft.isUnhiddenByUser == true || displayNft.shouldHide == true
        }
    }
    
    private let cacheUrl = URL.cachesDirectory.appending(components: "air", "nfts", "nfts.json")
    
    // MARK: - Load
    
    private func received(accountId: String, newNfts: [ApiNft], removedNftIds: [String], replaceExisting: Bool) async {
        var nfts = self.nfts[accountId, default: [:]]
        for removedNftId in removedNftIds {
            nfts.removeValue(forKey: removedNftId)
        }
        for nft in newNfts.reversed() {
            if var displayNft = nfts[nft.id] {
                let oldIsHidden = displayNft.shouldHide
                // update nft (e.g. to get new isHidden) but keep user settings
                displayNft.nft = nft
                if oldIsHidden == false && displayNft.shouldHide == true {
                    // move to end
                    nfts.removeValue(forKey: nft.id)
                }
                nfts[nft.id] = displayNft
            } else {
                let displayNft = DisplayNft(nft: nft, isHiddenByUser: false)
                if displayNft.shouldHide {
                    nfts[nft.id] = displayNft
                } else {
                    nfts.updateValue(displayNft, forKey: nft.id, insertingAt: 0)
                }
            }
        }
        if replaceExisting {
            let newNftIds = Set(newNfts.map { $0.id })
            nfts.removeAll { nftId, _ in
                !newNftIds.contains(nftId)
            }
        }
        self._nfts.withLock { [nfts] in
            $0[accountId] = nfts
        }
        _moveHiddenToEnd(accountId: accountId)
        _checkNftsOrder(accountId: accountId)
        saveToCache()
        _removeAccountNftIfNoLongerAvailable(accountId: accountId)
        WalletCoreData.notify(event: .nftsChanged(accountId: accountId), for: accountId)
    }
    
    // MARK: - Storage
    
    public func loadFromCache(accountIds: Set<String>) {
        Task {
            do {
                let data = try Data(contentsOf: cacheUrl)
                let nfts = try JSONDecoder()
                    .decode([String: OrderedDictionary<String, DisplayNft>].self, from: data)
                    .filter { accountIds.contains($0.key) }
                self._nfts.withLock { $0 = nfts }
            } catch {
                log.error("failed to load cache: \(error, .public)")
            }
            WalletCoreData.add(eventObserver: self)
        }
    }
    
    private func saveToCache() {
        Task(priority: .background) {
            do {
                try FileManager.default.createDirectory(at: cacheUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(nfts)
                try data.write(to: cacheUrl)
            } catch {
                log.error("failed to save to cache: \(error, .public)")
            }
        }
    }
    
    public func clean() {
        _nfts.withLock { $0 = [:] }
        saveToCache()
    }
    
    // MARK: - Hidden
    
    public func setHiddenByUser(accountId: String, nftId: String, isHidden newValue: Bool) {
        _nfts.withLock {
            if var displayNft = $0[accountId]?[nftId] {
                let oldShouldHide = displayNft.shouldHide
                
                if newValue == true {
                    displayNft.isUnhiddenByUser = false
                    if displayNft.nft.isScam != true {
                        displayNft.isHiddenByUser = true
                    }
                } else { // newValue == false
                    displayNft.isHiddenByUser = false
                    if displayNft.nft.isScam == true {
                        displayNft.isUnhiddenByUser = true
                    }
                }
                
                if displayNft.shouldHide != oldShouldHide {
                    _ = $0[accountId]?.removeValue(forKey: nftId)
                    if displayNft.shouldHide {
                        $0[accountId]?[nftId] = displayNft
                    } else {
                        $0[accountId]?.updateValue(displayNft, forKey: nftId, insertingAt: 0)
                    }
                } else {
                    $0[accountId]?[nftId] = displayNft
                }
                
                 // move to the end so that it doesn't interfere with ordering
            }
        }
        _checkNftsOrder(accountId: accountId)
        saveToCache()
        WalletCoreData.notify(event: .nftsChanged(accountId: accountId), for: accountId)
    }
    
    public func reorderNfts(accountId: String, changes: CollectionDifference<String>) {
        let originalValues = nfts[accountId, default: [:]]
        let maxIndex = originalValues.count(where: { $0.value.shouldHide })
        var nfts = originalValues
        for change in changes {
            switch change {
            case .remove(offset: _, element: let element, associatedWith: _):
                nfts.removeValue(forKey: element)
            case .insert(offset: let offset, element: let element, associatedWith: _):
                if let value = originalValues[element] {
                    nfts.updateValue(value, forKey: element, insertingAt: min(offset, maxIndex))
                }
            }
        }
        self._nfts.withLock { [nfts] in
            $0[accountId] = nfts
        }
        _checkNftsOrder(accountId: accountId)
        saveToCache()
        DispatchQueue.main.async {
            WalletCoreData.notify(event: .nftsChanged(accountId: accountId), for: accountId)
        }
    }
    
    public func showAllHiddenNfts(accountId: String) {
        _nfts.withLock {
            for nftId in $0[accountId, default: [:]].keys {
                $0[accountId]?[nftId]?.isHiddenByUser = false
            }
        }
        _moveHiddenToEnd(accountId: accountId)
        _checkNftsOrder(accountId: accountId)
        saveToCache()
        WalletCoreData.notify(event: .nftsChanged(accountId: accountId), for: accountId)
    }
    
    // MARK: - Collections
    
    public func getCollections(accountId: String) -> UserCollectionsInfo {
        let uniqueCollections = Array(OrderedSet(
            self.nfts[accountId, default: [:]]
                .filter { (_, displayNft) in
                    !displayNft.shouldHide
                }
                .compactMap { (_, dislayNft) in
                    dislayNft.nft.collection
                }
        )).sorted()
        let telegramGiftsCollections = Array(OrderedSet(
            self.nfts[accountId, default: [:]]
                .filter { (_, displayNft) in
                    !displayNft.shouldHide && displayNft.nft.isTelegramGift == true
                }
                .compactMap { (_, dislayNft) in
                    dislayNft.nft.collection
                }
        )).sorted()
        let notTelegramGiftsCollections = Array(OrderedSet(
            self.nfts[accountId, default: [:]]
                .filter { (_, displayNft) in
                    !displayNft.shouldHide && displayNft.nft.isTelegramGift != true
                }
                .compactMap { (_, dislayNft) in
                    dislayNft.nft.collection
                }
        )).sorted()
        return UserCollectionsInfo(
            accountId: accountId,
            collections: uniqueCollections,
            telegramGiftsCollections: telegramGiftsCollections,
            notTelegramGiftsCollections: notTelegramGiftsCollections
        )
    }
    
    public func accountOwnsCollection(accountId: String, address: String?) -> Bool {
        if let address {
            for collection in getCollections(accountId: accountId).collections {
                if collection.address == address {
                    return true
                }
            }
        }
        return false
    }
    
    public func hasTelegramGifts(accountId: String) -> Bool {
        !getCollections(accountId: accountId).telegramGiftsCollections.isEmpty
    }
    
    public func getAccountCollection(accountId: String, address: String) -> NftCollection? {
        if let nft = nfts[accountId, default: [:]]
            .values
            .first(where: { $0.nft.collectionAddress == address })?
            .nft {
            return NftCollection(address: address, name: nft.collectionName ?? "Collection")
        }
        return nil
    }
    
    // MARK: - Private
    
    private func _moveHiddenToEnd(accountId: String) {
        _nfts.withLock {
            if var nfts = $0[accountId], let lastShown = nfts.elements.lastIndex(where: { $1.shouldHide == false }) {
                let tooEarly = nfts.elements[..<lastShown].filter { _, nft in
                    nft.shouldHide
                }
                for (nftId, nft) in tooEarly {
                    nfts.removeValue(forKey: nftId)
                    nfts[nftId] = nft
                }
                $0[accountId] = nfts
            }
        }
    }
    
    private func _checkNftsOrder(accountId: String) {
        _nfts.withLock {
            let nfts = $0[accountId, default: [:]]
            let shownNfts = nfts.filter { (_, nft) in !nft.shouldHide }
            let hiddenNfts = nfts.filter { (_, nft) in nft.shouldHide }
            assert(Array(nfts.values) == Array(shownNfts.values) + Array(hiddenNfts.values), "nfts are out of order; reordering won't work")
            if Array(nfts.values) != Array(shownNfts.values) + Array(hiddenNfts.values) {
                log.fault("logic error: nfts are out of order; reordering won't work")
                _moveHiddenToEnd(accountId: accountId)
            }
        }
    }
    
    private func _removeAccountNftIfNoLongerAvailable(accountId: String) {
        if accountId == AccountStore.accountId, let nfts = self.currentAccountNfts {
            if let nft = AccountStore.currentAccountCardBackgroundNft, nfts[nft.id] == nil {
                AccountStore.currentAccountCardBackgroundNft = nil
            }
            if let nft = AccountStore.currentAccountAccentColorNft, nfts[nft.id] == nil {
                AccountStore.currentAccountAccentColorNft = nil
            }
        }
    }
}


extension _NftStore: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountDeleted(let accountId):
            _nfts.withLock { $0[accountId] = nil }
            
        case .updateNfts(let update):
            Task {
                await self.received(accountId: update.accountId, newNfts: update.nfts, removedNftIds: [], replaceExisting: update.shouldAppend != true)
            }
        case .nftReceived(let update):
            Task {
                await self.received(accountId: update.accountId, newNfts: [update.nft], removedNftIds: [], replaceExisting: false)
            }
        case .nftSent(let update):
            Task {
                await self.received(accountId: update.accountId, newNfts: [], removedNftIds: [update.nftAddress], replaceExisting: false)
            }
        case .nftPutUpForSale(let update):
            // might want to add a badge here?
            _ = update
            break
        default:
            break
        }
    }
}


// MARK: - UI extensions

import UIKit

extension _NftStore {
    
    @MainActor public func makeNftCollectionsMenu(accountId: String) -> UIMenu? {
        
        let collections = NftStore.getCollections(accountId: accountId)
        let hasHidden = NftStore.currentAccountHasHiddenNfts

        var children: [UIMenuElement] = []

        let gifts = collections.telegramGiftsCollections
        if !gifts.isEmpty {
            var collectionActions: [UIMenuElement] = [
                UIMenu(options: .displayInline, children: [
                    UIAction(title: "All Telegram Gifts") { _ in
                        AppActions.showAssets(selectedTab: 1, collectionsFilter: .telegramGifts)
                    }
                ])
            ]
            let collections = gifts.map { collection in
                UIAction(title: collection.name) { _ in
                    AppActions.showAssets(selectedTab: 1, collectionsFilter: .collection(collection))
                }
            }
            collectionActions.append(contentsOf: collections)
            let collectionsMenu = UIMenu(title: "Telegram Gifts", options: [], children: collectionActions)
            children.append(collectionsMenu)
        }
        
        let notGifts = collections.notTelegramGiftsCollections
        if !notGifts.isEmpty {
            let collectionActions = notGifts.map { collection in
                UIAction(title: collection.name) { _ in
                    AppActions.showAssets(selectedTab: 1, collectionsFilter: .collection(collection))
                }
            }
            let collectionsMenu = UIMenu(options: .displayInline, children: collectionActions)
            children.append(collectionsMenu)
        }

        if hasHidden {
            let hiddenNftsAction = UIAction(title: "Hidden NFTs") { _ in
                AppActions.showHiddenNfts()
            }
            let hiddenNftsMenu = UIMenu(options: .displayInline, children: [hiddenNftsAction])
            children.append(hiddenNftsMenu)
        }
        
        if children.isEmpty {
            return nil
        }

        return UIMenu(children: children)
    }
}


// MARK: - Custom types

public struct DisplayNft: Equatable, Hashable, Codable, Identifiable, Sendable {
    
    public var nft: ApiNft
    public var isHiddenByUser: Bool
    public var isUnhiddenByUser: Bool = false
    
    public var id: String { nft.address }
    
    public var shouldHide: Bool {
        if isUnhiddenByUser {
            return false
        } else {
            return isHiddenByUser || nft.isHidden == true
        }
    }
}

public struct UserCollectionsInfo {
    public var accountId: String
    public var collections: [NftCollection]
    public var telegramGiftsCollections: [NftCollection]
    public var notTelegramGiftsCollections: [NftCollection]
}

#if DEBUG
public extension _NftStore {
    @MainActor func configureForPreview() {
        _nfts.withLock {
            $0[""] = [ApiNft.sample, ApiNft.sampleMtwCard]
                .map { DisplayNft(nft: $0, isHiddenByUser: false) } .orderedDictionaryByKey(\.id)
        }
    }
}
#endif

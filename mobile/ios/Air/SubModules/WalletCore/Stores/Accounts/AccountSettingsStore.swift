//
//  AccountSettingsStore.swift
//  WalletCore
//
//  Created by nikstar on 24.11.2025.
//

import Foundation
import Dependencies
import Perception
import WalletContext
import UIKit

private let log = Log("AccountSettings")

@Perceptible
public final class AccountSettingsStore {
    
    private var _byAccountId: UnfairLock<[String: AccountSettings]> = .init(initialState: [:])
    
    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    
    init() {
        Task {
            await preload()
        }
    }
    
    @concurrent func preload() async {
        for accountId in accountStore.accountsById.keys {
            _ = `for`(accountId: accountId)
        }
    }
    
    public func `for`(accountId: String) -> AccountSettings {
        access(keyPath: \.__byAccountId)
        return _byAccountId.withLock { _byAccountId in
            if let settings = _byAccountId[accountId] {
                return settings
            }
            let settings = AccountSettings(accountId: accountId)
            _byAccountId[accountId] = settings
            return settings
        }
    }
}

extension AccountSettingsStore: DependencyKey {
    public static let liveValue: AccountSettingsStore = AccountSettingsStore()
}

extension DependencyValues {
    public var accountSettings: AccountSettingsStore {
        self[AccountSettingsStore.self]
    }
}

@Perceptible
public final class AccountSettings {
    
    public let accountId: String
    
    @PerceptionIgnored
    @Dependency(\.accountStore.currentAccountId) var currentAccountId
    
    @PerceptionIgnored
    private var _backgroundNft: ApiNft??
    
    init(accountId: String) {
        self.accountId = accountId
        _ = backgroundNft
    }
    
    public var backgroundNft: ApiNft? {
        access(keyPath: \.backgroundNft)
        if let maybeNft = _backgroundNft {
            return maybeNft
        }
        if let data = GlobalStorage["settings.byAccountId.\(accountId).cardBackgroundNft"], let nft = try? JSONSerialization.decode(ApiNft.self, from: data) {
            _backgroundNft = .some(.some(nft))
            return nft
        }
        _backgroundNft = .some(nil)
        return nil
    }
    
    public func setBackgroundNft(_ nft: ApiNft?) {
        withMutation(keyPath: \.backgroundNft) {
            do {
                if let nft {
                    _backgroundNft = .some(.some(nft))
                    let object = try JSONSerialization.encode(nft)
                    GlobalStorage.update { $0["settings.byAccountId.\(accountId).cardBackgroundNft"] = object }
                    Task(priority: .background) { try? await GlobalStorage.syncronize() }
                } else {
                    _backgroundNft = .some(nil)
                    GlobalStorage.update { $0["settings.byAccountId.\(accountId).cardBackgroundNft"] = nil }
                    Task(priority: .background) { try? await GlobalStorage.syncronize() }
                }
                WalletCoreData.notify(event: .cardBackgroundChanged(accountId, nft))
            } catch {
                log.fault("failed to save cardBackgroundNft: \(error, .public)")
            }
        }
    }
    
    public var accentColorNft: ApiNft? {
        access(keyPath: \.accentColorNft)
        if let data = GlobalStorage["settings.byAccountId.\(accountId).accentColorNft"], let nft = try? JSONSerialization.decode(ApiNft.self, from: data) {
            return nft
        }
        return nil
    }
    
    public func setAccentColorNft(_ nft: ApiNft?) {
        withMutation(keyPath: \.accentColorNft) {
            do {
                if let nft {
                    let object = try JSONSerialization.encode(nft)
                    GlobalStorage.update { $0["settings.byAccountId.\(accountId).accentColorNft"] = object }
                } else {
                    GlobalStorage.update { $0["settings.byAccountId.\(accountId).accentColorNft"] = nil }
                }
                installAccentColorFromNft(accountId: accountId, nft: nft)
            } catch {
                log.fault("failed to save accentColorNft: \(error, .public)")
            }
        }
    }
    
    private func installAccentColorFromNft(accountId: String, nft: ApiNft?) {
        Task.detached {
            let color: Int? = if let nft {
                await getAccentColorIndexFromNft(nft: nft)
            } else {
                nil
            }
            self.setAccentColorIndex(index: color)
        }
    }

    public var accentColorIndex: Int? {
        access(keyPath: \.accentColorIndex)
        if let index = GlobalStorage["settings.byAccountId.\(accountId).accentColorIndex"] as? Int {
            return index
        }
        return nil
    }

    private func setAccentColorIndex(index newValue: Int?) {
        withMutation(keyPath: \.accentColorIndex) {
            GlobalStorage.update { $0["settings.byAccountId.\(accountId).accentColorIndex"] = newValue }
        }
        if accountId == currentAccountId {
            changeThemeColors(to: newValue)
            DispatchQueue.main.async {
                UIApplication.shared.sceneWindows.forEach { $0.updateTheme() }
            }
        }
        Task(priority: .background) { try? await GlobalStorage.syncronize() }
    }
}

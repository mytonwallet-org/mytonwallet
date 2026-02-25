//
//  ConfigStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/6/24.
//

import Foundation
import WalletContext

private let log = Log("ConfigStore")

public class ConfigStore {

    public static let shared = ConfigStore()
    
    private init() {}
    
    private let queue = DispatchQueue(label: "org.mytonwallet.app.config_store", attributes: .concurrent)
    
    private var _config: ApiUpdate.UpdateConfig? = nil
    private var _isLimitedOverride: Bool?
    private var _seasonalThemeOverride: ApiUpdate.UpdateConfig.SeasonalTheme?

    private func applyOverrides(on config: ApiUpdate.UpdateConfig?) -> ApiUpdate.UpdateConfig? {
        guard var config else { return nil }
        if let isLimitedOverride = _isLimitedOverride {
            config.isLimited = isLimitedOverride
        }
        if let seasonalThemeOverride = _seasonalThemeOverride {
            config.seasonalTheme = seasonalThemeOverride
        }
        return config
    }

    public internal(set) var config: ApiUpdate.UpdateConfig? {
        get {
            return queue.sync { applyOverrides(on: _config) }
        }
        set {
            queue.async(flags: .barrier) {
                self._config = newValue
                if let newValue {
                    self.handleConfig(newValue)
                } else {
                    WalletCoreData.notify(event: .configChanged)
                }
            }
        }
    }

    public var seasonalThemeOverride: ApiUpdate.UpdateConfig.SeasonalTheme? {
        get {
            queue.sync { _seasonalThemeOverride }
        }
        set {
            queue.async(flags: .barrier) {
                self._seasonalThemeOverride = newValue
                WalletCoreData.notify(event: .configChanged)
            }
        }
    }

    public var isLimitedOverride: Bool? {
        get {
            queue.sync { _isLimitedOverride }
        }
        set {
            queue.async(flags: .barrier) {
                self._isLimitedOverride = newValue
                WalletCoreData.notify(event: .configChanged)
            }
        }
    }
    
    public var shouldRestrictSwapsAndOnRamp: Bool { config?.isLimited == true }
    public var shouldRestrictBuyNfts: Bool { config?.isLimited == true }
    public var shouldRestrictSites: Bool { config?.isLimited == true }
    public var shouldRestrictSell: Bool { config?.isLimited == true }
    
    private func handleConfig(_ config: ApiUpdate.UpdateConfig) {
        if config.switchToClassic == true {
            log.info("updateConfig.switchToClassic = true")
            WalletContextManager.delegate?.switchToCapacitor()
            return
        }
        WalletCoreData.notify(event: .configChanged)
    }
    
    public func clean() {
        queue.async(flags: .barrier) {
            self._config = nil
            self._isLimitedOverride = nil
            self._seasonalThemeOverride = nil
        }
    }
}

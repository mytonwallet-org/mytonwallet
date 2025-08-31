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
    public internal(set) var config: ApiUpdate.UpdateConfig? {
        get {
            return queue.sync { _config }
        }
        set {
            queue.async(flags: .barrier) {
                self._config = newValue
                if let newValue {
                    self.handleConfig(newValue)
                }
            }
        }
    }
    
    public var shouldRestrictSwapsAndOnRamp: Bool { config?.isLimited == true }
    public var shouldRestrictBuyNfts: Bool { config?.isLimited == true }
    
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
        }
    }
}

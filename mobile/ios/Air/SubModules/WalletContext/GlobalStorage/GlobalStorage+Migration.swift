
import Foundation

public let STATE_VERSION: Int = 51

private let log = Log("GlobalStorage+Migration")

public enum GlobalMigrationError: Error {
    case stateVersionIsNil
    case stateVersionTooOld
}

extension _GlobalStorage {
    
    fileprivate var stateVersion: Int? {
        get { self["stateVersion"] as? Int}
        set { update { $0["stateVersion"] = newValue } }
    }
    
    public func migrate() async throws {
        
        if let v = self.stateVersion, v > STATE_VERSION {
            log.fault("migration error: stateVersion=\(v) greater than STATE_VERSION=\(STATE_VERSION)")
        }
        
        if let v = self.stateVersion, v >= STATE_VERSION {
            return
        }
        
        log.info("migration started")
        
        if self.stateVersion == nil {
            throw GlobalMigrationError.stateVersionIsNil
        }
        
        if let v = self.stateVersion, v < 32 {
            throw GlobalMigrationError.stateVersionTooOld
        }
        
        if let v = self.stateVersion, v >= 32 && v <= 35 {
            _clearActivities()
            self.stateVersion = 36
        }

        if let v = self.stateVersion, v == 36 {
            let cached = self["accounts.byId"] as? [String: [String: Any]] ?? [:]
            var accounts = cached
            for (accountId, var account) in cached {
                let type = account["isHardware"] as? Bool == true || account["type"] as? String == "hardware"  ? "hardware" : "mnemonic"
                account["type"] = type
                account["isHardware"] = nil
                accounts[accountId] = account
            }
            update {
                $0["accounts.byId"] = accounts
            }
            self.stateVersion = 37
        }
        
        if let v = self.stateVersion, v == 37 {
            update {
                if var tokens = $0["tokenInfo.bySlug"] as? [String: [String: Any]] {
                    for (slug, _) in tokens {
                        if let quote = tokens[slug]?["quote"] as? [String: Any] {
                            tokens[slug]?["price"] = quote["price"] as? Double
                            tokens[slug]?["priceUsd"] = quote["priceUsd"] as? Double
                            tokens[slug]?["percentChange24h"] = quote["percentChange24h"] as? Double
                            tokens[slug]?["quote"] = nil
                        }
                    }
                    $0["tokenInfo.bySlug"] = tokens
                }
            }
            self.stateVersion = 38
        }

        if let v = self.stateVersion, v < 44 {
            _clearActivities()
            self.stateVersion = 44
        }

        if let v = self.stateVersion, v < 47 {
            _clearActivities()
            // accounts are migrated in switchStorageToCapacitor
            self.stateVersion = 47
        }

        if let v = self.stateVersion, v == 47 {
            update {
                if var pushNotifications = $0["pushNotifications"] as? [String: Any] {
                    if let enabledAccounts = pushNotifications["enabledAccounts"] as? [String: Any] {
                        pushNotifications["enabledAccounts"] = Array(enabledAccounts.keys)
                    }
                    $0["pushNotifications"] = pushNotifications
                }
            }
            self.stateVersion = 48
        }
        

        if let v = self.stateVersion, v < 50 {
            // Android app specific migration
            self.stateVersion = 50
        }

        if let v = self.stateVersion, v == 50 {
            _clearActivities()
            self.stateVersion = 51
        }

        assert(self.stateVersion == STATE_VERSION)
        
        try await syncronize()
        log.info("migration completed")
    }
    
    private func _clearActivities() {
        let cached = self["byAccountId"] as? [String: [String: Any]] ?? [:]
        var byAccountId = cached
        for (accountId, var data) in cached {
            data["activities"] = nil
            byAccountId[accountId] = data
        }
        update {
            $0["byAccountId"] = byAccountId
        }
    }
}

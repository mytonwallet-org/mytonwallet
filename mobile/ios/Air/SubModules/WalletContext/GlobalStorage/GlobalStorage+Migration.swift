
import Foundation

public let STATE_VERSION: Int = 45

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
            assertionFailure()
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

        if let v = self.stateVersion, v < 45 {
            _clearActivities()
            self.stateVersion = 45
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

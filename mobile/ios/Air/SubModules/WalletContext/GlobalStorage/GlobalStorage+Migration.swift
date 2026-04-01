
import Foundation

public let STATE_VERSION: Int = 54

private let log = Log("GlobalStorage+Migration")

public enum GlobalMigrationError: Error {
    case stateVersionIsNil
    case stateVersionTooOld
}

extension GlobalStorage {
    
    fileprivate var stateVersion: Int? {
        get { self["stateVersion"] as? Int}
        set { update { $0["stateVersion"] = newValue } }
    }
    
    public func migrate() async throws {
        let initialStateVersion = self.stateVersion
        let initialStateVersionDescription = initialStateVersion.map(String.init) ?? "nil"

        if self.stateVersion == nil {
            throw GlobalMigrationError.stateVersionIsNil
        }

        if let v = self.stateVersion, v < 32 {
            throw GlobalMigrationError.stateVersionTooOld
        }

        if let v = self.stateVersion, v > STATE_VERSION {
            log.fault("migration error: stateVersion=\(v) greater than STATE_VERSION=\(STATE_VERSION)")
            return
        }

        let didRepairKnownSchemaGaps = repairKnownSchemaGaps()

        if didRepairKnownSchemaGaps {
            log.info("migration recovery path triggered from stateVersion=\(initialStateVersionDescription, .public)")
        }
        
        if let v = self.stateVersion, v >= STATE_VERSION {
            if didRepairKnownSchemaGaps {
                log.info("migration finishing after recovery path stateVersion=\(v, .public)")
                try await syncronize()
                log.info("migration completed")
            }
            return
        }
        
        log.info(
            "migration started from stateVersion=\(initialStateVersionDescription, .public) recoveryPathTriggered=\(didRepairKnownSchemaGaps, .public)"
        )
        log.info("migration started")
        
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

        if let v = self.stateVersion, v < 45 {
            _clearActivities()
            self.stateVersion = 45
        }

        if let v = self.stateVersion, v == 45 {
            _migrateAccountsToByChainIfNeeded()
            self.stateVersion = 46
        }

        if let v = self.stateVersion, v == 46 {
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

        if let v = self.stateVersion, v == 51 {
            self.stateVersion = 52
        }

        if let v = self.stateVersion, v == 52 {
            self.stateVersion = 53
        }

        if let v = self.stateVersion, v == 53 {
            if self["settings.langSource"] == nil {
                update { $0["settings.langSource"] = "user" }
            }
            self.stateVersion = 54
        }

        assert(self.stateVersion == STATE_VERSION)
        
        try await syncronize()
        log.info(
            "migration completed from stateVersion=\(initialStateVersionDescription, .public) to stateVersion=\(self.stateVersion ?? -1, .public) recoveryPathTriggered=\(didRepairKnownSchemaGaps, .public)"
        )
        log.info("migration completed")
    }

    private func repairKnownSchemaGaps() -> Bool {
        _migrateAccountsToByChainIfNeeded()
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

    @discardableResult
    private func _migrateAccountsToByChainIfNeeded() -> Bool {
        let cached = self["accounts.byId"] as? [String: [String: Any]] ?? [:]
        guard !cached.isEmpty else { return false }

        var accounts = cached
        var migratedAccountIds: [String] = []

        for (accountId, var account) in cached {
            let existingByChain = account["byChain"] as? [String: Any]
            guard existingByChain?.isEmpty != false else { continue }
            guard let addressByChain = account["addressByChain"] as? [String: Any] else { continue }

            let domainByChain = account["domainByChain"] as? [String: Any]
            let isMultisigByChain = account["isMultisigByChain"] as? [String: Any]

            let byChain = addressByChain.reduce(into: [String: [String: Any]]()) { result, item in
                let (chain, rawAddress) = item
                guard let address = rawAddress as? String else { return }
                var chainData: [String: Any] = ["address": address]
                if let domain = domainByChain?[chain] as? String, !domain.isEmpty {
                    chainData["domain"] = domain
                }
                if isMultisigByChain?[chain] as? Bool == true {
                    chainData["isMultisig"] = true
                }
                result[chain] = chainData
            }
            guard !byChain.isEmpty else { continue }

            account["byChain"] = byChain
            account["addressByChain"] = nil
            account["domainByChain"] = nil
            account["isMultisigByChain"] = nil
            accounts[accountId] = account
            migratedAccountIds.append(accountId)
        }

        guard !migratedAccountIds.isEmpty else { return false }

        update {
            $0["accounts.byId"] = accounts
        }
        log.info("migrated legacy accounts to byChain count=\(migratedAccountIds.count)")
        return true
    }
}

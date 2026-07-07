import Testing
@testable import WalletContext

@MainActor
@Suite("GlobalStorage Migration")
struct GlobalStorageMigrationTests {
    @Test
    func `nil version single account cache migrates to current schema`() async throws {
        let storage = makeStorage([
            "addresses": [
                "byAccountId": [
                    "0-ton-mainnet": "EQlegacy",
                ],
            ],
            "currentTokenSlug": "toncoin",
            "currentTokenPeriod": "1D",
            "tokenInfo": [
                "bySlug": [
                    "toncoin": [
                        "slug": "toncoin",
                    ],
                ],
            ],
        ])

        try await storage.migrate(persist: false)

        #expect(storage["stateVersion"] as? Int == STATE_VERSION)
        #expect(storage["accounts.byId.0-ton-mainnet.byChain.ton.address"] as? String == "EQlegacy")
        #expect(storage["accounts.byId.0-ton-mainnet.type"] as? String == "mnemonic")
        #expect(storage["byAccountId.0-ton-mainnet.currentTokenSlug"] as? String == "toncoin")
    }

    @Test
    func `zero version cache with accounts uses legacy migration path`() async throws {
        let storage = makeStorage([
            "stateVersion": 0,
            "accounts": [
                "byId": [
                    "legacy-mainnet": [
                        "address": "EQzero",
                        "title": "Recovered",
                    ],
                ],
            ],
            "byAccountId": [
                "legacy-mainnet": [:],
            ],
            "currentAccountId": "legacy-mainnet",
        ])

        try await storage.migrate(persist: false)

        #expect(storage["stateVersion"] as? Int == STATE_VERSION)
        #expect(storage["accounts.byId.legacy-mainnet.byChain.ton.address"] as? String == "EQzero")
        #expect(storage["accounts.byId.legacy-mainnet.type"] as? String == "mnemonic")
    }

    @Test
    func `hardware account migrates ledger index into ton chain`() async throws {
        let storage = makeStorage([
            "stateVersion": 46,
            "accounts": [
                "byId": [
                    "hardware-mainnet": [
                        "type": "hardware",
                        "byChain": [
                            "ton": [
                                "address": "EQhardware",
                            ],
                        ],
                        "ledger": [
                            "index": 7,
                        ],
                    ],
                ],
            ],
            "byAccountId": [
                "hardware-mainnet": [:],
            ],
        ])

        try await storage.migrate(persist: false)

        #expect(storage["stateVersion"] as? Int == STATE_VERSION)
        #expect(storage["accounts.byId.hardware-mainnet.byChain.ton.ledgerIndex"] as? Int == 7)
        #expect(storage["accounts.byId.hardware-mainnet.ledger"] == nil)
    }

    @Test
    func `recent web migration tail is applied`() async throws {
        let storage = makeStorage([
            "stateVersion": 54,
            "accounts": [
                "byId": [
                    "0-ton-mainnet": [
                        "type": "mnemonic",
                        "byChain": [
                            "ton": [
                                "address": "EQtail",
                            ],
                        ],
                    ],
                ],
            ],
            "byAccountId": [
                "0-ton-mainnet": [
                    "activeContentTab": 1,
                    "landscapeActionsActiveTabIndex": 2,
                    "activities": [
                        "idsMain": ["activity-id"],
                    ],
                    "nfts": [
                        "ownedMtwCardAddresses": ["EQcard"],
                    ],
                ],
            ],
            "settings": [
                "byAccountId": [
                    "0-ton-mainnet": [
                        "walletTokensLimit": 7,
                    ],
                ],
            ],
            "portfolio": [
                "netChangeByAccountId": [
                    "0-ton-mainnet": 10,
                ],
                "other": true,
            ],
        ])

        try await storage.migrate(persist: false)

        #expect(storage["stateVersion"] as? Int == STATE_VERSION)
        #expect(storage["byAccountId.0-ton-mainnet.activeContentTab"] == nil)
        #expect(storage["byAccountId.0-ton-mainnet.landscapeActionsActiveTabIndex"] == nil)
        #expect(storage["byAccountId.0-ton-mainnet.activities"] == nil)
        #expect(storage["byAccountId.0-ton-mainnet.nfts.ownedMwCardAddresses"] as? [String] == ["EQcard"])
        #expect(storage["byAccountId.0-ton-mainnet.nfts.ownedMtwCardAddresses"] == nil)
        #expect(storage["settings.byAccountId.0-ton-mainnet.overviewCellSize"] as? String == "small")
        #expect(storage["settings.byAccountId.0-ton-mainnet.walletTokensLimit"] == nil)
        #expect(storage["portfolio.netChangeByAccountId"] == nil)
        #expect(storage["portfolio.other"] as? Bool == true)
    }

    @Test
    func `nil version without accounts remains a migration failure`() async {
        let storage = makeStorage([:])
        var didThrowMissingVersion = false

        do {
            try await storage.migrate(persist: false)
        } catch GlobalMigrationError.stateVersionIsNil {
            didThrowMissingVersion = true
        } catch {
        }

        #expect(didThrowMissingVersion)
    }

    private func makeStorage(_ root: [String: Any]) -> GlobalStorage {
        let storage = GlobalStorage()
        storage.update {
            $0[""] = root
        }
        return storage
    }
}

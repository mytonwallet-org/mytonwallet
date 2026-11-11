import Foundation
import Testing
import WalletContext
@testable import WalletCore

@Suite @MainActor
struct PerpsReadCacheTests {
    private let btc = "hyperliquid:hl:BTC"

    // MARK: - Cached render

    @Test func restoredPositionsActivityAndCatalogueNeedNoSDKCall() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = account(positions: [try position()])
        let history = try history()
        var client = client()
        client.marketSnapshot = { try self.market() }
        client.positions = { _ in snapshot }
        client.history = { _ in history }
        let original = store(client: client, directory: directory)
        await original.refresh(accountId: "a")
        let restored = store(client: offlineClient(), directory: directory)
        await restored.loadFromCache(accountIds: ["a", "b"])
        #expect(restored.snapshots["a"] == snapshot)
        #expect(restored.snapshots["b"] == nil)
        #expect(restored.fills["a"] == history.fills)
        #expect(restored.market == original.market)
        #expect(restored.asset(id: btc)?.symbol == "BTC")
        #expect(restored.asset(named: "BTC")?.id == btc)
        #expect(restored.loading.isEmpty)
        #expect(restored.snapshotErrors.isEmpty)
        #expect(!restored.isSnapshotStale(accountId: "a"))
        #expect(!restored.isHistoryStale(accountId: "a"))
        #expect(!restored.isMarketStale())
    }

    // MARK: - Persistence format

    @Test func accountsCatalogueAndChartsArePersistedSeparatelyWithTheCatalogueStoredOnce() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var client = client()
        client.marketSnapshot = { try self.market() }
        client.positions = { _ in self.account(positions: [try self.position()]) }
        client.history = { _ in try self.history() }
        client.candles = { _, _ in [[1, 60_000], [2, 61_000]] }
        let value = PerpsStore(client: client, cacheDirectory: directory.appending(component: "perps"),
                               currentAccountId: { nil }, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await value.loadFromCache(accountIds: ["a", "b"])
        await value.refresh(accountId: "a")
        await value.refresh(accountId: "b")
        await value.refreshChart(assetId: btc, period: "1D")
        await value.cache?.flush()

        let accounts = try contents(of: directory.appending(components: "perps", "accounts.json"), version: PerpsReadCache.accountsVersion)
        let byAccount = try #require(accounts as? [String: [String: Any]])
        #expect(Set(byAccount.keys) == ["a", "b"])
        let stored = try #require(byAccount["a"])
        #expect(Set(stored.keys) == ["snapshot", "fills", "historyFetchedAt", "hasActivityHistory"])
        let storedSnapshot = try #require(stored["snapshot"] as? [String: Any])
        #expect(storedSnapshot["assets"] == nil)
        #expect(storedSnapshot["marketSections"] == nil)
        #expect((storedSnapshot["positions"] as? [Any])?.count == 1)

        let market = try #require(try contents(of: directory.appending(components: "perps", "market.json"),
                                               version: PerpsReadCache.marketVersion) as? [String: Any])
        #expect(market["langCode"] as? String == LocalizationSupport.shared.langCode)
        #expect(((market["market"] as? [String: Any])?["assets"] as? [Any])?.count == 1)

        let charts = try #require(try contents(of: directory.appending(components: "perps", "charts.json"),
                                               version: PerpsReadCache.chartsVersion) as? [String: Any])
        #expect(Set(charts.keys) == [btc + "/1D"])

        for file in ["accounts.json", "market.json", "charts.json"] {
            let url = directory.appending(components: "perps", file)
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }
    }

    @Test func aFileInAnotherFormatIsDiscardedAndReplacedByTheNextSave() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accountsURL = directory.appending(component: "accounts.json")
        let marketURL = directory.appending(component: "market.json")
        let snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(account()))
        try JSONSerialization.data(withJSONObject: ["version": PerpsReadCache.accountsVersion + 1,
                                                    "contents": ["a": ["snapshot": snapshot]]]).write(to: accountsURL)
        try Data("not json".utf8).write(to: marketURL)
        var client = client()
        client.marketSnapshot = { try self.market() }
        client.positions = { _ in self.account() }
        let value = store(client: client, directory: directory)
        await value.loadFromCache(accountIds: ["a"])
        #expect(value.snapshots["a"] == nil)
        #expect(value.market == nil)
        #expect(!FileManager.default.fileExists(atPath: marketURL.path()))
        await value.refresh(accountId: "a")
        #expect(await PerpsReadCache(directory: directory).accounts.load().value?.keys.sorted() == ["a"])
        #expect(await PerpsReadCache(directory: directory).market.load().value?.market == value.market)
    }

    // MARK: - Activity evidence

    @Test func confirmedEmptyHistoryRestoresUntilTheAccountIsRemoved() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var client = client()
        client.positions = { _ in self.account() }
        client.history = { _ in .init(fills: []) }
        let confirmed = store(client: client, directory: directory)
        await confirmed.refresh(accountId: "a")
        let restored = store(client: self.client(), directory: directory)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.hasActivityHistory["a"] == false)
        #expect(restored.hasActivityHistory["b"] == nil)
        restored.removeAccount("a")
        #expect(restored.hasActivityHistory["a"] == nil)
    }

    @Test func unrenderedActivityEvidenceSurvivesALaterEmptyPageAndRestart() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var response = ApiPerpsActivityHistory(fills: [], hasActivity: true)
        var client = client()
        client.positions = { _ in self.account() }
        client.history = { _ in response }
        let original = store(client: client, directory: directory)
        await original.refresh(accountId: "a")
        #expect(original.fills["a"]?.isEmpty == true)
        #expect(original.hasActivityHistory["a"] == true)
        response = .init(fills: [])
        await original.refresh(accountId: "a")
        let restored = store(client: self.client(), directory: directory)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.hasActivityHistory["a"] == true)
        await restored.clearCache()
        #expect(restored.hasActivityHistory.isEmpty)
    }

    @Test func failedAndAssetOnlyHistoryReadsCannotConfirmAnEmptyAccount() async throws {
        let asset = try #require(try market().assets.first)
        var client = client()
        client.positions = { _ in self.account() }
        client.assetDetail = { _, _, _ in .init(asset: asset, history: .init(fills: [])) }
        let value = store(client: client)
        await value.refresh(accountId: "a")
        await value.refreshAsset(accountId: "a", assetId: asset.id)
        #expect(value.hasActivityHistory["a"] == nil)
    }

    @Test func partialPositionEvidencePersistsEvenWhenHistoryFails() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var response = account()
        var historyFails = false
        var client = client()
        client.positions = { _ in response }
        client.history = { _ in
            if historyFails { throw PerpsError.invalidResponse }
            return .init(fills: [])
        }
        let value = store(client: client, directory: directory)
        await value.refresh(accountId: "a")
        #expect(value.hasActivityHistory["a"] == false)
        response = account(positions: [try position()], unavailableDexs: ["xyz"])
        historyFails = true
        await value.refresh(accountId: "a")
        let restored = store(client: self.client(), directory: directory)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.snapshots["a"]?.positions.isEmpty == true)
        #expect(restored.hasActivityHistory["a"] == true)
    }

    // MARK: - Restoration and removal

    @Test func dataThatArrivesWhileTheCacheIsReadWinsAndTheFilesAreWrittenBackWhole() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        let cache = PerpsReadCache(directory: directory)
        cache.accounts.save(["a": .init(snapshot: account(equity: "100")), "b": .init(snapshot: account(equity: "50")),
                             "removed": .init(snapshot: account())])
        cache.market.save(.init(langCode: LocalizationSupport.shared.langCode,
                                market: try market(fetchedAt: now.addingTimeInterval(-600)), descriptions: [btc: "Bitcoin"]))
        await cache.flush()
        var client = client()
        client.marketSnapshot = { try self.market(fetchedAt: now, markPx: "61000") }
        let value = store(client: client, directory: directory)
        var started = false
        let hydration = Task {
            started = true
            await value.loadFromCache(accountIds: ["a", "b"])
        }
        while !started { await Task.yield() }
        // Both save their files from memory that does not hold the restored data yet.
        push(account(equity: "200"), to: value, accountId: "a")
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: Self.milliseconds(now)))
        await hydration.value
        #expect(value.snapshots["a"]?.totalEquity == "200")
        #expect(value.snapshots["b"]?.totalEquity == "50")
        #expect(value.snapshots["removed"] == nil)
        #expect(value.asset(id: btc)?.context.markPx == "61000")
        #expect(value.asset(id: btc)?.description == "Bitcoin")
        await value.cache?.flush()
        let restored = store(client: offlineClient(), directory: directory)
        await restored.loadFromCache(accountIds: ["a", "b", "removed"])
        #expect(restored.snapshots["a"]?.totalEquity == "200")
        #expect(restored.snapshots["b"]?.totalEquity == "50")
        #expect(restored.snapshots["removed"] == nil)
        #expect(restored.asset(id: btc)?.context.markPx == "61000")
    }

    @Test func deletingAnAccountRemovesOnlyItsDataAndAllowsANewAccountWithThatID() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = account()
        var client = client()
        client.marketSnapshot = { try self.market() }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: []) }
        client.candles = { _, _ in [[1, 60_000]] }
        let value = store(client: client, directory: directory)
        await value.refresh(accountId: "a")
        await value.refresh(accountId: "b")
        await value.refreshChart(assetId: btc, period: "1D")
        value.walletCore(event: .accountDeleted(accountId: "a"))
        push(account(equity: "300"), to: value, accountId: "a")
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"] == nil)
        #expect(value.market != nil)
        #expect(value.chart(assetId: btc, period: "1D") != nil)
        await value.cache?.flush()
        let restored = store(client: offlineClient(), directory: directory)
        await restored.loadFromCache(accountIds: ["a", "b"])
        #expect(restored.snapshots["a"] == nil)
        #expect(restored.snapshots["b"] == snapshot)
        #expect(restored.market != nil)
        value.walletCore(event: .accountChanged(accountId: "a", isNew: true))
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"] == snapshot)
    }

    @Test(arguments: [false, true])
    func clearingOrResettingDuringHydrationDoesNotRestoreAccounts(reset: Bool) async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var client = client()
        client.marketSnapshot = { try self.market() }
        client.positions = { _ in self.account() }
        client.history = { _ in .init(fills: []) }
        let original = store(client: client, directory: directory)
        await original.refresh(accountId: "a")
        let operation = ApiPerpsOperation(id: "pending", accountId: "a", assetId: btc, kind: "increase", createdAt: 1)
        let restored = store(client: client, directory: directory, operations: [operation])
        var started = false
        let hydration = Task {
            started = true
            await restored.loadFromCache(accountIds: ["a"])
        }
        while !started { await Task.yield() }
        if reset {
            restored.walletCore(event: .accountsReset)
        } else {
            await restored.clearCache()
        }
        await hydration.value
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.snapshots.isEmpty)
        #expect(restored.fills.isEmpty)
        #expect(restored.pendingOperation(accountId: "a")?.id == operation.id)
        // The catalogue belongs to no account and survives a reset.
        #expect((restored.market != nil) == reset)
    }

    @Test func deletingOrClearingWhileRefreshIsSuspendedCannotRepopulateCache() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for delete in [false, true] {
            var response: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
            var client = client()
            client.positions = { _ in try await withCheckedThrowingContinuation { response = $0 } }
            let value = store(client: client, directory: directory)
            let refresh = Task { await value.refresh(accountId: "a") }
            while response == nil { await Task.yield() }
            if delete { value.removeAccount("a") } else { await value.clearCache() }
            response?.resume(returning: account())
            await refresh.value
            await value.loadFromCache(accountIds: ["a"])
            #expect(value.snapshots.isEmpty)
            #expect(value.loading.isEmpty)
            await value.cache?.flush()
            let restored = store(client: self.client(), directory: directory)
            await restored.loadFromCache(accountIds: ["a"])
            #expect(restored.snapshots.isEmpty)
        }
    }

    // MARK: - Partial reads and freshness

    @Test func partialSnapshotsRemainUnavailableAndHistoryIsBounded() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fill = try #require(history().fills.first)
        var history = ApiPerpsActivityHistory(fills: [])
        for index in 0..<(PerpsCachedAccount.historyLimit + 1) {
            var nextFill = fill
            nextFill.activityId = "fill/\(index)"
            history.fills.append(nextFill)
        }
        var client = client()
        client.positions = { _ in self.account(unavailableDexs: ["xyz"]) }
        client.history = { _ in history }
        let value = store(client: client, directory: directory)
        await value.refresh(accountId: "a")
        #expect(value.fills["a"]?.count == PerpsCachedAccount.historyLimit + 1)
        let restored = store(client: self.client(), directory: directory)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.snapshotErrors["a"] == "PerpsIncompleteData")
        #expect(restored.snapshots["a"]?.unavailableDexs == ["xyz"])
        #expect(restored.isSnapshotStale(accountId: "a"))
        #expect(restored.fills["a"]?.count == PerpsCachedAccount.historyLimit)
    }

    @Test func partialReadKeepsTheLastCompletePortfolioUntilACompleteEmptyResponse() async throws {
        let complete = account(positions: [try position()])
        var response = complete
        var client = client()
        client.positions = { _ in response }
        client.history = { _ in .init(fills: []) }
        let value = store(client: client)
        await value.refresh(accountId: "a")
        response = account(equity: "0", unavailableDexs: [""])
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"] == complete)
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.snapshotErrors["a"] == "PerpsIncompleteData")
        #expect(!value.isHistoryStale(accountId: "a"))
        push(account(equity: "0", unavailableDexs: ["xyz"]), to: value, accountId: "a")
        #expect(value.snapshots["a"] == complete)
        response = account(equity: "0")
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"]?.positions.isEmpty == true)
        #expect(value.snapshotErrors["a"] == nil)
        #expect(!value.isSnapshotStale(accountId: "a"))
    }

    @Test func positionsAndHistoryFreshnessResolveIndependently() async throws {
        var historyResponse: CheckedContinuation<ApiPerpsActivityHistory, Error>?
        var client = client()
        client.positions = { _ in self.account() }
        client.history = { _ in try await withCheckedThrowingContinuation { historyResponse = $0 } }
        let value = store(client: client)
        let refresh = Task { await value.refresh(accountId: "a") }
        while historyResponse == nil || value.snapshots["a"] == nil { await Task.yield() }
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.isHistoryStale(accountId: "a"))
        #expect(value.loading.contains("a"))
        historyResponse?.resume(throwing: PerpsError.invalidResponse)
        await refresh.value
        #expect(value.snapshotErrors["a"] == nil)
        #expect(value.loading.isEmpty)
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.isHistoryStale(accountId: "a"))
    }

    @Test func restoredFreshnessUsesReadTimesAndKeepsAccountsAndPeriodsIsolated() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        let history = try history()
        let cache = PerpsReadCache(directory: directory)
        cache.accounts.save([
            "recent": .init(snapshot: account(at: now.addingTimeInterval(-59)), fills: history.fills,
                            historyFetchedAt: now.addingTimeInterval(-299)),
            "old": .init(snapshot: account(at: now.addingTimeInterval(-60)), fills: history.fills,
                         historyFetchedAt: now.addingTimeInterval(-300)),
            "unknown": .init(snapshot: account(at: now), fills: history.fills),
            "partial": .init(snapshot: account(at: now, unavailableDexs: ["xyz"])),
        ])
        cache.charts.save([btc + "/1D": .init(points: [[1, 60_000]], fetchedAt: now.addingTimeInterval(-299))])
        await cache.flush()
        var client = client()
        client.candles = { _, _ in throw PerpsError.invalidResponse }
        let value = store(client: client, directory: directory)
        await value.loadFromCache(accountIds: ["recent", "old", "unknown", "partial"])
        await value.refreshChart(assetId: btc, period: "1D")
        #expect(!value.isSnapshotStale(accountId: "recent", now: now))
        #expect(!value.isHistoryStale(accountId: "recent", now: now))
        #expect(!value.isChartRestored(assetId: btc, period: "1D", now: now))
        #expect(value.isChartRestored(assetId: btc, period: "7D", now: now))
        #expect(!value.isSnapshotStale(accountId: "unknown", now: now))
        for accountId in ["old", "missing"] {
            #expect(value.isSnapshotStale(accountId: accountId, now: now))
            #expect(value.isHistoryStale(accountId: accountId, now: now))
        }
        #expect(value.isHistoryStale(accountId: "unknown", now: now))
        #expect(value.isSnapshotStale(accountId: "partial", now: now))
        #expect(value.isSnapshotStale(accountId: "recent", now: now.addingTimeInterval(1)))
        #expect(value.isHistoryStale(accountId: "recent", now: now.addingTimeInterval(1)))
        #expect(value.isChartRestored(assetId: btc, period: "1D", now: now.addingTimeInterval(1)))
        value.removeAccount("old")
        #expect(!value.isSnapshotStale(accountId: "recent", now: now))
        await value.clearCache()
        #expect(value.isSnapshotStale(accountId: "recent", now: now))
        #expect(value.chart(assetId: btc, period: "1D") == nil)
    }

    @Test func failedOrPartialRefreshCannotRenewOldData() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        let old = account(at: now.addingTimeInterval(-61))
        let history = try history()
        let cache = PerpsReadCache(directory: directory)
        cache.accounts.save(["a": .init(snapshot: old, fills: history.fills, historyFetchedAt: now.addingTimeInterval(-301))])
        await cache.flush()
        var complete = false
        var response: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
        var client = client()
        client.positions = { _ in
            if complete { return self.account() }
            return try await withCheckedThrowingContinuation { response = $0 }
        }
        client.history = { _ in
            guard complete else { throw PerpsError.invalidResponse }
            return history
        }
        let value = store(client: client, directory: directory)
        await value.loadFromCache(accountIds: ["a"])
        let refresh = Task { await value.refresh(accountId: "a") }
        while response == nil { await Task.yield() }
        #expect(value.isSnapshotStale(accountId: "a"))
        response?.resume(returning: account(unavailableDexs: ["xyz"]))
        await refresh.value
        #expect(value.snapshots["a"] == old)
        #expect(value.isSnapshotStale(accountId: "a"))
        #expect(value.isHistoryStale(accountId: "a"))
        await value.cache?.flush()
        let restored = store(client: self.client(), directory: directory)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.isSnapshotStale(accountId: "a"))
        #expect(restored.isHistoryStale(accountId: "a"))

        complete = true
        await value.refresh(accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(!value.isHistoryStale(accountId: "a"))
    }

    @Test func capabilityIsAssumedUntilTheSDKReportsItAndTradingNeedsAnEligibleSnapshot() async throws {
        let account = MAccount(id: "a-mainnet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        let testnet = MAccount(id: "b-testnet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x5678")])
        var snapshot = self.account()
        var supported: Bool?
        var client = client()
        client.positions = { _ in snapshot }
        client.supported = {
            guard let supported else { throw PerpsError.invalidResponse }
            return supported
        }
        let value = store(client: client)
        await value.loadCapabilities()
        #expect(!PerpsAvailability.canRead(account, store: value))
        #expect(!PerpsAvailability.canRead(testnet, store: value))
        await value.refresh(accountId: account.id)
        #expect(!PerpsAvailability.canTrade(account, store: value))
        snapshot.tradingAvailability = .init(isAvailable: true)
        await value.refresh(accountId: account.id)
        #expect(!PerpsAvailability.canTrade(account, store: value))
        supported = false
        await value.loadCapabilities()
        #expect(!PerpsAvailability.canRead(account, store: value))
        #expect(!PerpsAvailability.canTrade(account, store: value))
        supported = true
        await value.loadCapabilities()
        #expect(!PerpsAvailability.canRead(account, store: value))
    }

    // MARK: - Pushed positions

    @Test func failedPollingEndsFreshnessUntilTheNextPush() async throws {
        let value = store(client: client(), current: CurrentAccount("a"))
        let later = Date.now.addingTimeInterval(3_600)
        push(account(), to: value, accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a", now: later))
        value.walletCore(event: .updatePerpsPositionsUnavailable(.init(accountId: "b")))
        #expect(!value.isSnapshotStale(accountId: "a", now: later))
        value.walletCore(event: .updatePerpsPositionsUnavailable(.init(accountId: "a")))
        #expect(value.isSnapshotStale(accountId: "a", now: later))
        push(account(), to: value, accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a", now: later))
    }

    @Test func pushedPositionsDecodeFromTheSDKShapeAndApplyOnlyToTheirAccount() async throws {
        let update = try JSONDecoder().decode(ApiUpdate.UpdatePerpsPositions.self, from: Data("""
        {"type":"updatePerpsPositions","accountId":"a","abstractionMode":"unifiedAccount",
         "tradingAvailability":{"isAvailable":true},
         "positions":[{"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
          "collateral":"100","equity":"102","raw":{"coin":"BTC","leverage":{"type":"isolated","value":2},
          "marginUsed":"102","positionValue":"600","returnOnEquity":"0.02","szi":"0.01","unrealizedPnl":"2"}}],
         "totalEquity":"102","totalPnl":"2","totalReturnOnEquity":"0.02","timestamp":1792760045000,"unavailableDexs":[]}
        """.utf8))
        #expect(update.accountId == "a")
        #expect(update.snapshot.abstractionMode == "unifiedAccount")
        #expect(update.snapshot.positions.first?.size == "0.01")
        let value = store(client: offlineClient())
        value.walletCore(event: .updatePerpsPositions(update))
        #expect(value.snapshots["a"] == update.snapshot)
        #expect(value.snapshots["b"] == nil)
        #expect(value.snapshotErrors["a"] == nil)
        #expect(value.hasActivityHistory["a"] == true)
    }

    @Test func theActiveAccountStaysLiveBetweenPushesUntilTheAccountChanges() async throws {
        let current = CurrentAccount("a")
        let longAgo = Date.now.addingTimeInterval(-600)
        var positionReads: [String] = []
        var client = client()
        client.marketSnapshot = { try self.market() }
        client.positions = { accountId in
            positionReads.append(accountId)
            return self.account(at: longAgo)
        }
        client.history = { _ in .init(fills: []) }
        let value = store(client: client, current: current)
        push(account(at: longAgo), to: value, accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a"))
        await value.refresh(accountId: "a")
        #expect(positionReads.isEmpty)

        // The SDK does not poll an account that is not active, even if it pushed its positions after an operation.
        push(account(at: longAgo), to: value, accountId: "b")
        #expect(value.isSnapshotStale(accountId: "b"))
        await value.refresh(accountId: "b")
        #expect(positionReads == ["b"])

        current.id = "b"
        value.walletCore(event: .accountChanged(accountId: "b", isNew: false))
        #expect(value.isSnapshotStale(accountId: "a"))
        #expect(value.isSnapshotStale(accountId: "b"))
        await value.refresh(accountId: "a")
        #expect(positionReads == ["b", "a"])

        // The first push after a switch may arrive before the switch event.
        current.id = "a"
        push(account(at: longAgo), to: value, accountId: "a")
        value.walletCore(event: .accountChanged(accountId: "a", isNew: false))
        #expect(!value.isSnapshotStale(accountId: "a"))

        // An incomplete push keeps the last complete portfolio but no longer counts as live.
        push(account(at: .now, unavailableDexs: ["xyz"]), to: value, accountId: "a")
        #expect(value.snapshots["a"]?.unavailableDexs.isEmpty == true)
        #expect(value.snapshotErrors["a"] == "PerpsIncompleteData")
        #expect(value.isSnapshotStale(accountId: "a"))
    }

    // MARK: - Charts

    @Test func chartsAreSharedByAccountsAndRestoredWhenFirstNeeded() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let points = [[1.0, 60_000.0], [2.0, 61_000.0]]
        var client = client()
        client.candles = { _, _ in points }
        let value = store(client: client, directory: directory)
        await value.refreshChart(assetId: btc, period: "1D")
        #expect(!value.isChartRestored(assetId: btc, period: "1D"))
        value.removeAccount("a")
        #expect(value.chart(assetId: btc, period: "1D") == points)
        client.candles = { _, _ in throw PerpsError.invalidResponse }
        let restored = store(client: client, directory: directory)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.chart(assetId: btc, period: "1D") == nil)
        await restored.refreshChart(assetId: btc, period: "1D")
        #expect(restored.chart(assetId: btc, period: "1D") == points)
        #expect(restored.chart(assetId: btc, period: "7D") == nil)
        #expect(!restored.isChartRestored(assetId: btc, period: "1D"))
        #expect(restored.isChartRestored(assetId: btc, period: "1D", now: .now.addingTimeInterval(301)))
    }

    @Test func clearingDuringAChartFetchDiscardsIt() async {
        var response: CheckedContinuation<[[Double]], Error>?
        var client = client()
        client.candles = { _, _ in try await withCheckedThrowingContinuation { response = $0 } }
        let value = store(client: client)
        let request = Task { await value.refreshChart(assetId: btc, period: "1D") }
        while response == nil { await Task.yield() }
        await value.clearCache()
        response?.resume(returning: [[1, 60_000]])
        await request.value
        #expect(value.chart(assetId: btc, period: "1D") == nil)
    }

    @Test func longChartsRetainTheirTimeRangeAndRefreshWithoutDimmingRecentData() async {
        let points = (1...3_000).map { [Double($0), Double(60_000 + $0)] }
        var response: CheckedContinuation<[[Double]], Error>?
        var deferChart = false
        var client = client()
        client.candles = { _, _ in
            if deferChart { return try await withCheckedThrowingContinuation { response = $0 } }
            return points
        }
        let value = store(client: client)
        await value.refreshChart(assetId: btc, period: "ALL")
        let chart = value.chart(assetId: btc, period: "ALL")
        #expect(chart?.count == PerpsCachedChart.pointLimit)
        #expect(chart?.first == points.first)
        #expect(chart?.last == points.last)
        deferChart = true
        let refresh = Task { await value.refreshChart(assetId: btc, period: "ALL") }
        while response == nil { await Task.yield() }
        #expect(!value.isChartRestored(assetId: btc, period: "ALL"))
        #expect(value.chart(assetId: btc, period: "ALL") == chart)
        response?.resume(returning: points)
        await refresh.value
        #expect(!value.isChartRestored(assetId: btc, period: "ALL"))
    }

    // MARK: - Catalogue

    @Test func assetDescriptionsSurviveCataloguePushesAndRestartWithoutRenewingTheAccount() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        var detail = try #require(try market().assets.first)
        detail.description = "Bitcoin perpetual futures."
        var fetchedAt = now.addingTimeInterval(-10)
        var client = client()
        client.marketSnapshot = { try self.market(fetchedAt: fetchedAt) }
        client.assetDetail = { _, _, _ in .init(asset: detail, history: .init(fills: [])) }
        let cache = PerpsReadCache(directory: directory)
        cache.accounts.save(["a": .init(snapshot: account(at: .distantPast), fills: [], historyFetchedAt: .distantPast)])
        await cache.flush()
        let value = store(client: client, directory: directory)
        await value.loadFromCache(accountIds: ["a"])
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: Self.milliseconds(fetchedAt)))
        await value.refreshAsset(accountId: "a", assetId: btc)
        #expect(value.asset(id: btc)?.description == detail.description)
        #expect(value.isSnapshotStale(accountId: "a"))
        #expect(value.isHistoryStale(accountId: "a"))
        fetchedAt = now
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: Self.milliseconds(now)))
        #expect(value.market?.assetsFetchedAt == Self.milliseconds(now))
        #expect(value.asset(id: btc)?.description == detail.description)
        await value.cache?.flush()
        let reopened = store(client: offlineClient(), directory: directory)
        await reopened.loadFromCache(accountIds: ["a"])
        #expect(reopened.asset(id: btc)?.description == detail.description)
    }

    @Test func clearingDuringAnAssetOnlyFetchInvalidatesItsGeneration() async throws {
        let asset = try #require(try market().assets.first)
        var response: CheckedContinuation<ApiPerpsAssetDetail, Error>?
        var client = client()
        client.assetDetail = { _, _, _ in try await withCheckedThrowingContinuation { response = $0 } }
        let value = store(client: client)
        let request = Task { await value.refreshAsset(accountId: "a", assetId: asset.id) }
        while response == nil { await Task.yield() }
        await value.clearCache()
        var described = asset
        described.description = "Bitcoin"
        response?.resume(returning: .init(asset: described, history: try history()))
        await request.value
        #expect(value.fills(accountId: "a", assetId: asset.id) == nil)
        #expect(value.asset(id: asset.id) == nil)
    }

    @Test func marketFreshnessUsesTheCatalogueFetchTimeIndependentlyOfPositions() async throws {
        let now = Date.now
        var fetchedAt = now.addingTimeInterval(-120)
        var client = client()
        client.marketSnapshot = { try self.market(fetchedAt: fetchedAt) }
        client.positions = { _ in self.account() }
        let value = store(client: client)
        await value.refresh(accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.isMarketStale(now: now))

        fetchedAt = now.addingTimeInterval(-119)
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: Self.milliseconds(fetchedAt)))
        #expect(!value.isMarketStale(now: now))
        #expect(value.isMarketStale(now: now.addingTimeInterval(2)))

        let unknown = store(client: client)
        fetchedAt = Date(timeIntervalSince1970: 0)
        await unknown.refresh(accountId: "a")
        #expect(unknown.market != nil)
        #expect(unknown.isMarketStale(now: now))
    }

    @Test func pushedCatalogueServesEveryAccountWithoutReadingPositionsOrHistory() async throws {
        let directory = cacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        let fetchedAt = Self.milliseconds(now)
        let cache = PerpsReadCache(directory: directory)
        cache.accounts.save(["a": .init(snapshot: account(positions: [try position()])), "b": .init(snapshot: account())])
        cache.market.save(.init(langCode: LocalizationSupport.shared.langCode,
                                market: try market(fetchedAt: now.addingTimeInterval(-180)), descriptions: [:]))
        await cache.flush()
        var reads = 0
        var client = offlineClient()
        client.marketSnapshot = {
            reads += 1
            return try self.market(fetchedAt: now, markPx: "61000")
        }
        let value = store(client: client, directory: directory)
        await value.loadFromCache(accountIds: ["a", "b"])
        #expect(value.isMarketStale(now: now))
        let update = try JSONDecoder().decode(ApiUpdate.UpdatePerpsAssets.self, from: Data("""
        {"type":"updatePerpsAssets","assets":{"assetsByChain":{}},"fetchedAt":\(fetchedAt)}
        """.utf8))
        await value.receiveAssetsUpdate(update)
        await value.receiveAssetsUpdate(update)
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: fetchedAt - 1))
        await value.receiveAssetsUpdate(.init(langCode: "unsupported-language", fetchedAt: fetchedAt + 1))
        #expect(reads == 1)
        #expect(value.asset(id: btc)?.context.markPx == "61000")
        #expect(!value.isMarketStale(now: now))
        #expect(value.snapshots["a"]?.positions.count == 1)
        let restored = store(client: offlineClient(), directory: directory)
        await restored.loadFromCache(accountIds: ["a", "b"])
        #expect(restored.market == value.market)
        #expect(!restored.isMarketStale(now: now))
    }

    @Test func clearingDuringACatalogueReadDiscardsItsResponse() async throws {
        let market = try market()
        var response: CheckedContinuation<ApiPerpsMarketSnapshot, Error>?
        var client = client()
        client.marketSnapshot = { try await withCheckedThrowingContinuation { response = $0 } }
        let value = store(client: client)
        let request = Task { await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: market.assetsFetchedAt)) }
        while response == nil { await Task.yield() }
        await value.clearCache()
        response?.resume(returning: market)
        await request.value
        #expect(value.market == nil)
    }

    // MARK: - Fixtures

    private final class CurrentAccount {
        var id: String?
        init(_ id: String?) { self.id = id }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }

    private func cacheDirectory() -> URL {
        URL.temporaryDirectory.appending(components: UUID().uuidString)
    }

    private func store(client: PerpsClient, directory: URL? = nil, current: CurrentAccount? = nil,
                       operations: [ApiPerpsOperation] = []) -> PerpsStore {
        PerpsStore(client: client, cacheDirectory: directory, currentAccountId: { current?.id }, load: { operations },
                   save: { _ in }, loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
    }

    private func push(_ snapshot: ApiPerpsAccountSnapshot, to store: PerpsStore, accountId: String) {
        store.walletCore(event: .updatePerpsPositions(.init(accountId: accountId, snapshot: snapshot)))
    }

    private func client() -> PerpsClient {
        var client = PerpsClient()
        client.marketSnapshot = { throw PerpsError.invalidResponse }
        client.positions = { _ in throw PerpsError.invalidResponse }
        client.history = { _ in throw PerpsError.invalidResponse }
        client.receiptDetails = { _ in .init() }
        return client
    }

    /// A client for data that must render before the SDK answers anything.
    private func offlineClient() -> PerpsClient {
        var client = PerpsClient()
        client.marketSnapshot = { Issue.record("Restored data must not read the catalogue"); throw PerpsError.invalidResponse }
        client.positions = { _ in Issue.record("Restored data must not read positions"); throw PerpsError.invalidResponse }
        client.history = { _ in Issue.record("Restored data must not read Activity"); throw PerpsError.invalidResponse }
        client.candles = { _, _ in throw PerpsError.invalidResponse }
        client.receiptDetails = { _ in .init() }
        return client
    }

    private func contents(of url: URL, version: Int) throws -> Any? {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["version"] as? Int == version)
        return object["contents"]
    }

    private func market(fetchedAt: Date = .now, markPx: String = "60000") throws -> ApiPerpsMarketSnapshot {
        try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
        "dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"\(markPx)","prevDayPx":"60000"}}],
        "marketSections":[],"assetsFetchedAt":\(Self.milliseconds(fetchedAt))}
        """.utf8))
    }

    private func account(equity: String = "100", positions: [ApiPerpsAccountPosition] = [], at date: Date = .now,
                         unavailableDexs: [String] = []) -> ApiPerpsAccountSnapshot {
        .init(positions: positions, totalEquity: equity, totalPnl: "2", timestamp: Self.milliseconds(date),
              unavailableDexs: unavailableDexs)
    }

    private func position() throws -> ApiPerpsAccountPosition {
        try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
         "collateral":"100","equity":"102","raw":{"coin":"BTC","leverage":{"type":"isolated","value":2},
         "marginUsed":"102","positionValue":"600","returnOnEquity":"0.02","szi":"0.01","unrealizedPnl":"2"}}
        """.utf8))
    }

    private func history() throws -> ApiPerpsActivityHistory {
        try JSONDecoder().decode(ApiPerpsActivityHistory.self, from: Data("""
        {"fills":[{"activityId":"BTC/20/open","coin":"BTC","oid":20,"time":1,"px":"60000","sz":"0.01",
        "fee":"0.2","feeToken":"USDC","eventKind":"opened","positionSide":"long","positionSize":"0.01"}],"hasActivity":true}
        """.utf8))
    }
}

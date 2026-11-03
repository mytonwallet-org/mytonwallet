import Foundation
import Testing
@testable import WalletCore

@Suite @MainActor
struct PerpsReadCacheTests {
    @Test func confirmedEmptyHistoryRestoresButLegacyEmptyHistoryRemainsUnknown() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try snapshot()
        let cache = PerpsReadCache(url: url)
        cache.save(["a": .init(snapshot: snapshot, history: .init(fills: [], cashFlows: []))])
        let legacy = store(client: client(), url: url)
        await legacy.loadFromCache(accountIds: ["a"])
        #expect(legacy.hasActivityHistory["a"] == nil)
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let confirmed = store(client: client, url: url)
        await confirmed.refresh(accountId: "a")
        let restored = store(client: self.client(), url: url)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.hasActivityHistory["a"] == false)
        #expect(restored.hasActivityHistory["b"] == nil)
        restored.removeAccount("a")
        #expect(restored.hasActivityHistory["a"] == nil)
    }

    @Test(arguments: [false, true])
    func hiddenFundingHistoryStillDisqualifiesFirstTimeOnboardingAfterRestart(normalized: Bool) async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try snapshot()
        let funding = try JSONDecoder().decode(ApiPerpsActivityHistory.self, from: Data("""
        {"fills":[],"cashFlows":[{"id":"funding/1","kind":"funding","direction":"incoming","time":1,
        "amount":"0.01","token":"USDC","fees":[]}]}
        """.utf8))
        var response = normalized ? ApiPerpsActivityHistory(fills: [], cashFlows: [], hasActivity: true) : funding
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in response }
        let original = store(client: client, url: url)
        await original.refresh(accountId: "a")
        #expect(original.cashFlows["a"]?.isEmpty == true)
        #expect(original.hasActivityHistory["a"] == true)
        response = .init(fills: [], cashFlows: [])
        await original.refresh(accountId: "a")
        let restored = store(client: self.client(), url: url)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.hasActivityHistory["a"] == true)
        await restored.clearCache()
        #expect(restored.hasActivityHistory.isEmpty)
    }

    @Test func failedAndAssetOnlyHistoryReadsCannotConfirmAnEmptyAccount() async throws {
        let snapshot = try snapshot()
        var client = client()
        client.snapshot = { _ in snapshot }
        client.assetDetail = { _, _, _ in .init(asset: snapshot.assets[0], history: .init(fills: [], cashFlows: [])) }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        await value.refresh(accountId: "a")
        await value.refreshAsset(accountId: "a", assetId: snapshot.assets[0].id)
        #expect(value.hasActivityHistory["a"] == nil)
    }

    @Test func partialPositionEvidencePersistsEvenWhenHistoryFails() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var response = try snapshot()
        var historyFails = false
        var client = client()
        client.snapshot = { _ in response }
        client.history = { _ in
            if historyFails { throw PerpsError.invalidResponse }
            return .init(fills: [], cashFlows: [])
        }
        let value = store(client: client, url: url)
        await value.refresh(accountId: "a")
        #expect(value.hasActivityHistory["a"] == false)
        response.unavailableDexs = ["xyz"]
        response.positions = [try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
         "collateral":"100","equity":"102","raw":{"coin":"BTC","leverage":{"type":"isolated","value":2},
         "marginUsed":"102","positionValue":"600","returnOnEquity":"0.02","szi":"0.01","unrealizedPnl":"2"}}
        """.utf8))]
        historyFails = true
        await value.refresh(accountId: "a")
        let restored = store(client: self.client(), url: url)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.snapshots["a"]?.positions.isEmpty == true)
        #expect(restored.hasActivityHistory["a"] == true)
    }

    @Test func restoredPortfolioAndHistoryAreAvailableBeforeTheFirstRefresh() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try snapshot()
        let history = try history()
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in history }
        let original = store(client: client, url: url)
        await original.refresh(accountId: "a")
        let restored = store(client: self.client(), url: url)
        await restored.loadFromCache(accountIds: ["a", "b"])
        #expect(restored.snapshots["a"] == snapshot)
        #expect(restored.fills["a"] == history.fills)
        #expect(restored.cashFlows["a"] == history.cashFlows)
        #expect(restored.snapshots["b"] == nil)
        #expect(restored.loading.isEmpty)
        #expect(restored.errors.isEmpty)
        #expect(!restored.isSupported)
        #expect(!restored.isSnapshotStale(accountId: "a"))
        #expect(!restored.isHistoryStale(accountId: "a"))
        #expect(!original.isSnapshotStale(accountId: "a"))
        #expect(!original.isHistoryStale(accountId: "a"))

        await restored.refresh(accountId: "a")
        #expect(restored.snapshots["a"] == snapshot)
        #expect(restored.cashFlows["a"] == history.cashFlows)
        #expect(restored.errors["a"] == "PerpsUnavailable")
        #expect(!restored.isSnapshotStale(accountId: "a"))
        #expect(!restored.isHistoryStale(accountId: "a"))
    }

    @Test func hydrationCannotOverwriteANewerLiveSnapshot() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var live = try snapshot()
        var client = client()
        client.snapshot = { _ in live }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let value = store(client: client, url: url)
        await value.refresh(accountId: "a")
        live.totalEquity = "200"
        await value.refresh(accountId: "a")
        await value.loadFromCache(accountIds: ["a"])
        #expect(value.snapshots["a"]?.totalEquity == "200")
    }

    @Test func deletingAnAccountRemovesItsPersistedDataAndAllowsANewAccountWithThatID() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try snapshot()
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let value = store(client: client, url: url)
        await value.refresh(accountId: "a")
        await value.refresh(accountId: "b")
        value.walletCore(event: .accountDeleted(accountId: "a"))
        // Loading on the same storage queue waits for its queued deletion write.
        await value.loadFromCache(accountIds: ["a", "b"])
        let restored = store(client: client, url: url)
        await restored.loadFromCache(accountIds: ["a", "b"])
        #expect(restored.snapshots["a"] == nil)
        #expect(restored.snapshots["b"] == snapshot)
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"] == nil)
        value.walletCore(event: .accountChanged(accountId: "a", isNew: true))
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"] == snapshot)
    }

    @Test(arguments: [false, true])
    func clearingOrResettingDuringHydrationDoesNotRestoreBalances(reset: Bool) async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try snapshot()
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let original = store(client: client, url: url)
        await original.refresh(accountId: "a")
        let operation = ApiPerpsOperation(id: "pending", accountId: "a", assetId: "BTC", kind: "increase", createdAt: 1)
        let restored = PerpsStore(client: client, cacheURL: url, load: { [operation] }, save: { _ in },
                                 loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
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
        #expect(restored.cashFlows.isEmpty)
        #expect(restored.pendingOperation(accountId: "a")?.id == operation.id)
    }

    @Test func deletingOrClearingWhileRefreshIsSuspendedCannotRepopulateCache() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for delete in [false, true] {
            let snapshot = try snapshot()
            var response: CheckedContinuation<ApiPerpsSnapshot, Error>?
            var client = client()
            client.snapshot = { _ in try await withCheckedThrowingContinuation { response = $0 } }
            let value = store(client: client, url: url)
            let refresh = Task { await value.refresh(accountId: "a") }
            while response == nil { await Task.yield() }
            if delete { value.removeAccount("a") } else { await value.clearCache() }
            response?.resume(returning: snapshot)
            await refresh.value
            await value.loadFromCache(accountIds: ["a"])
            #expect(value.snapshots.isEmpty)
            #expect(value.loading.isEmpty)
            let restored = store(client: self.client(), url: url)
            await restored.loadFromCache(accountIds: ["a"])
            #expect(restored.snapshots.isEmpty)
        }
    }

    @Test func oldDisplayDataSurvivesButCorruptAndUnownedDataAreIgnored() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date.now
        let snapshot = try snapshot()
        let cache = PerpsReadCache(url: url)
        cache.save([
            "old": .init(snapshot: snapshot, snapshotFetchedAt: now.addingTimeInterval(-365 * 24 * 60 * 60)),
            "future": .init(snapshot: snapshot, snapshotFetchedAt: now.addingTimeInterval(60)),
            "deleted": .init(snapshot: snapshot, snapshotFetchedAt: now),
            "current": .init(snapshot: snapshot, snapshotFetchedAt: now)
        ])
        await cache.flush()
        let value = store(client: client(), url: url)
        await value.loadFromCache(accountIds: ["old", "future", "current"], now: now)
        #expect(Set(value.snapshots.keys) == ["old", "future", "current"])
        #expect(value.isSnapshotStale(accountId: "old"))
        #expect(Set(await cache.load().keys) == ["old", "future", "current"])
        await value.clearCache()
        try Data("not json".utf8).write(to: url)
        let invalid = store(client: client(), url: url)
        await invalid.loadFromCache(accountIds: ["current"])
        #expect(invalid.snapshots.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func partialSnapshotsRemainUnavailableAndHistoryIsBounded() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var snapshot = try snapshot()
        snapshot.unavailableDexs = ["xyz"]
        let fill = try #require(history().fills.first)
        let cashFlow = try #require(history().cashFlows.first)
        var history = ApiPerpsActivityHistory(fills: [], cashFlows: [])
        for index in 0..<(PerpsCachedAccount.historyLimit + 1) {
            var nextFill = fill
            nextFill.tid = Int64(index)
            history.fills.append(nextFill)
            var nextFlow = cashFlow
            nextFlow.id = "deposit/\(index)"
            history.cashFlows.append(nextFlow)
        }
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in history }
        let value = store(client: client, url: url)
        await value.refresh(accountId: "a")
        #expect(value.fills["a"]?.count == PerpsCachedAccount.historyLimit + 1)
        let restored = store(client: self.client(), url: url)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.errors["a"] == "PerpsIncompleteData")
        #expect(restored.snapshots["a"]?.unavailableDexs == ["xyz"])
        #expect(restored.fills["a"]?.count == PerpsCachedAccount.historyLimit)
        #expect(restored.cashFlows["a"]?.count == PerpsCachedAccount.historyLimit)
    }

    @Test func versionTwoCacheMigratesToPersistentStorageAfterFilteringAccounts() async throws {
        let url = cacheURL()
        let legacyURL = url.deletingLastPathComponent().appending(path: "legacy.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        struct Legacy: Encodable {
            var version = 2
            var accounts: [String: PerpsCachedAccount]
        }
        let old = PerpsCachedAccount(snapshot: try snapshot(), snapshotFetchedAt: .distantPast)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Legacy(accounts: ["a": old, "removed": old])).write(to: legacyURL)
        let value = PerpsStore(client: client(), cacheURL: url, legacyCacheURL: legacyURL, load: { [] }, save: { _ in },
                              loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await value.loadFromCache(accountIds: ["a"])
        #expect(value.snapshots["a"] == old.snapshot)
        #expect(value.isSnapshotStale(accountId: "a"))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path()))
        #expect(Set(await PerpsReadCache(url: url).load().keys) == ["a"])
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func partialRefreshKeepsTheLastCompletePortfolioUntilACompleteEmptyResponse() async throws {
        var snapshot = try snapshot()
        snapshot.positions = [try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
         "collateral":"100","equity":"102","raw":{"coin":"BTC","leverage":{"type":"isolated","value":2},
         "marginUsed":"102","positionValue":"600","returnOnEquity":"0.02","szi":"0.01","unrealizedPnl":"2"}}
        """.utf8))]
        var response = snapshot
        var client = client()
        client.snapshot = { _ in response }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        await value.refresh(accountId: "a")
        response.positions = []
        response.totalEquity = "0"
        response.unavailableDexs = [""]
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"] == snapshot)
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.snapshotErrors["a"] == "PerpsIncompleteData")
        #expect(!value.isHistoryStale(accountId: "a"))
        response.unavailableDexs = []
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"]?.positions.isEmpty == true)
        #expect(!value.isSnapshotStale(accountId: "a"))
    }

    @Test func snapshotAndHistoryFreshnessResolveIndependently() async throws {
        let snapshot = try snapshot()
        var historyResponse: CheckedContinuation<ApiPerpsActivityHistory, Error>?
        var client = client()
        client.snapshot = { _ in snapshot }
        client.history = { _ in try await withCheckedThrowingContinuation { historyResponse = $0 } }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        let refresh = Task { await value.refresh(accountId: "a") }
        while historyResponse == nil || value.snapshotLoading.contains("a") { await Task.yield() }
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.isHistoryStale(accountId: "a"))
        #expect(value.historyLoading.contains("a"))
        historyResponse?.resume(throwing: PerpsError.invalidResponse)
        await refresh.value
        #expect(value.snapshotErrors["a"] == nil)
        #expect(value.historyErrors["a"] == "PerpsUnavailable")
        #expect(value.historyLoading.isEmpty)
        #expect(!value.isSnapshotStale(accountId: "a"))
    }

    @Test func subsequentRefreshKeepsRecentDataFreshWhileItsSourceIsPending() async throws {
        let snapshot = try snapshot()
        var response: CheckedContinuation<ApiPerpsSnapshot, Error>?
        var deferSnapshot = false
        var client = client()
        client.snapshot = { _ in
            if deferSnapshot { return try await withCheckedThrowingContinuation { response = $0 } }
            return snapshot
        }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        await value.refresh(accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a"))
        deferSnapshot = true
        let refresh = Task { await value.refresh(accountId: "a") }
        while response == nil { await Task.yield() }
        #expect(value.snapshots["a"] == snapshot)
        #expect(!value.isSnapshotStale(accountId: "a"))
        response?.resume(returning: snapshot)
        await refresh.value
        #expect(!value.isSnapshotStale(accountId: "a"))
    }

    @Test func restoredFreshnessUsesFetchAgeAndKeepsAccountsAndPeriodsIsolated() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date.now
        let snapshot = try snapshot()
        let history = try history()
        var partial = snapshot
        partial.unavailableDexs = ["xyz"]
        let cache = PerpsReadCache(url: url)
        cache.save([
            "recent": .init(snapshot: snapshot, snapshotFetchedAt: now.addingTimeInterval(-59),
                            history: history, historyFetchedAt: now.addingTimeInterval(-299),
                            charts: ["BTC/1D": .init(points: [[1, 60_000]], fetchedAt: now.addingTimeInterval(-299))]),
            "old": .init(snapshot: snapshot, snapshotFetchedAt: now.addingTimeInterval(-60),
                         history: history, historyFetchedAt: now.addingTimeInterval(-300),
                         charts: ["BTC/1D": .init(points: [[1, 60_000]], fetchedAt: now.addingTimeInterval(-300))]),
            "unknown": .init(snapshot: snapshot, history: history),
            "partial": .init(snapshot: partial, snapshotFetchedAt: now),
        ])
        await cache.flush()
        let value = store(client: client(), url: url)
        await value.loadFromCache(accountIds: ["recent", "old", "unknown", "partial"], now: now)
        #expect(!value.isSnapshotStale(accountId: "recent", now: now))
        #expect(!value.isHistoryStale(accountId: "recent", now: now))
        #expect(!value.isChartRestored(accountId: "recent", assetId: "BTC", period: "1D", now: now))
        #expect(value.isChartRestored(accountId: "recent", assetId: "BTC", period: "7D", now: now))
        for accountId in ["old", "unknown", "missing"] {
            #expect(value.isSnapshotStale(accountId: accountId, now: now))
            #expect(value.isHistoryStale(accountId: accountId, now: now))
            #expect(value.isChartRestored(accountId: accountId, assetId: "BTC", period: "1D", now: now))
        }
        #expect(value.isSnapshotStale(accountId: "partial", now: now))
        #expect(value.isSnapshotStale(accountId: "recent", now: now.addingTimeInterval(1)))
        #expect(value.isHistoryStale(accountId: "recent", now: now.addingTimeInterval(1)))
        #expect(value.isChartRestored(accountId: "recent", assetId: "BTC", period: "1D", now: now.addingTimeInterval(1)))
        value.removeAccount("old")
        #expect(!value.isSnapshotStale(accountId: "recent", now: now))
        await value.clearCache()
        #expect(value.isSnapshotStale(accountId: "recent", now: now))
    }

    @Test func failedOrPartialRefreshCannotRenewOldDataTimestamps() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date.now
        let snapshot = try snapshot()
        let history = try history()
        let cache = PerpsReadCache(url: url)
        cache.save(["a": .init(snapshot: snapshot, snapshotFetchedAt: now.addingTimeInterval(-61),
                               history: history, historyFetchedAt: now.addingTimeInterval(-301),
                               charts: ["BTC/1D": .init(points: [[1, 60_000]], fetchedAt: now.addingTimeInterval(-301))])])
        await cache.flush()
        var complete = false
        var response: CheckedContinuation<ApiPerpsSnapshot, Error>?
        var client = client()
        client.snapshot = { _ in
            if complete { return snapshot }
            return try await withCheckedThrowingContinuation { response = $0 }
        }
        client.history = { _ in
            guard complete else { throw PerpsError.invalidResponse }
            return history
        }
        client.candles = { _, _ in throw PerpsError.invalidResponse }
        let value = store(client: client, url: url)
        await value.loadFromCache(accountIds: ["a"])
        let refresh = Task { await value.refresh(accountId: "a") }
        while response == nil { await Task.yield() }
        #expect(value.isSnapshotStale(accountId: "a"))
        var partial = snapshot
        partial.unavailableDexs = ["xyz"]
        response?.resume(returning: partial)
        await refresh.value
        await value.refreshChart(accountId: "a", assetId: "BTC", period: "1D")
        #expect(value.snapshots["a"] == snapshot)
        #expect(value.isSnapshotStale(accountId: "a"))
        #expect(value.isHistoryStale(accountId: "a"))
        #expect(value.isChartRestored(accountId: "a", assetId: "BTC", period: "1D"))
        let restored = store(client: self.client(), url: url)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.isSnapshotStale(accountId: "a"))
        #expect(restored.isHistoryStale(accountId: "a"))

        complete = true
        await value.refresh(accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(!value.isHistoryStale(accountId: "a"))
    }

    @Test func capabilityUnknownAllowsCachedReadButNeverTradingOrUncachedAccounts() async throws {
        let account = MAccount(id: "a-mainnet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        let other = MAccount(id: "b-mainnet", title: "Wallet", type: .mnemonic,
                             byChain: [.arbitrum: AccountChain(address: "0x5678")])
        let snapshot = try snapshot()
        var supported = false
        var fail = true
        var client = client()
        client.snapshot = { _ in snapshot }
        client.supported = { if fail { throw PerpsError.invalidResponse }; return supported }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        await value.refresh(accountId: account.id)
        #expect(!PerpsAvailability.canRead(account, store: value))
        await value.loadCapabilities()
        #expect(!PerpsAvailability.canRead(account, store: value))
        fail = false
        supported = true
        await value.loadCapabilities()
        #expect(!PerpsAvailability.canRead(account, store: value))
        #expect(!PerpsAvailability.canRead(other, store: value))
        #expect(!PerpsAvailability.canTrade(account, store: value))
    }

    @Test func chartsRestoreByAccountAndPeriodAndRemainVisibleAfterFailure() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let points = [[1.0, 60_000.0], [2.0, 61_000.0]]
        var client = client()
        client.candles = { _, _ in points }
        let value = store(client: client, url: url)
        await value.refreshChart(accountId: "a", assetId: "BTC", period: "1D")
        #expect(value.isChartFresh(accountId: "a", assetId: "BTC", period: "1D", maxAge: 300))
        client.candles = { _, _ in throw PerpsError.invalidResponse }
        let restored = store(client: client, url: url)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.chart(accountId: "a", assetId: "BTC", period: "1D") == points)
        #expect(restored.chart(accountId: "b", assetId: "BTC", period: "1D") == nil)
        #expect(restored.chart(accountId: "a", assetId: "BTC", period: "7D") == nil)
        #expect(!restored.isChartRestored(accountId: "a", assetId: "BTC", period: "1D"))
        await restored.refreshChart(accountId: "a", assetId: "BTC", period: "1D")
        #expect(restored.chart(accountId: "a", assetId: "BTC", period: "1D") == points)
        #expect(restored.isChartFresh(accountId: "a", assetId: "BTC", period: "1D", maxAge: 300))
        #expect(restored.isChartRestored(accountId: "a", assetId: "BTC", period: "1D", now: .now.addingTimeInterval(301)))
    }

    @Test(arguments: [false, true])
    func clearingOrDeletingDuringChartFetchCannotRestoreItsData(delete: Bool) async {
        var response: CheckedContinuation<[[Double]], Error>?
        var client = client()
        client.candles = { _, _ in try await withCheckedThrowingContinuation { response = $0 } }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        let request = Task { await value.refreshChart(accountId: "a", assetId: "BTC", period: "1D") }
        while response == nil { await Task.yield() }
        if delete { value.removeAccount("a") } else { await value.clearCache() }
        response?.resume(returning: [[1, 60_000]])
        await request.value
        #expect(value.chart(accountId: "a", assetId: "BTC", period: "1D") == nil)
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
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        await value.refreshChart(accountId: "a", assetId: "BTC", period: "ALL")
        let chart = value.chart(accountId: "a", assetId: "BTC", period: "ALL")
        #expect(chart?.count == PerpsCachedAccount.chartPointLimit)
        #expect(chart?.first == points.first)
        #expect(chart?.last == points.last)
        deferChart = true
        let refresh = Task { await value.refreshChart(accountId: "a", assetId: "BTC", period: "ALL") }
        while response == nil { await Task.yield() }
        #expect(!value.isChartRestored(accountId: "a", assetId: "BTC", period: "ALL"))
        #expect(value.chart(accountId: "a", assetId: "BTC", period: "ALL") == chart)
        response?.resume(returning: points)
        await refresh.value
        #expect(!value.isChartRestored(accountId: "a", assetId: "BTC", period: "ALL"))
    }

    @Test func assetDescriptionsPersistWithoutClaimingTheWholeAccountIsFresh() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try snapshot()
        var asset = try #require(snapshot.assets.first)
        asset.description = "Bitcoin perpetual futures."
        var client = client()
        client.snapshot = { _ in snapshot }
        client.assetDetail = { _, _, _ in .init(asset: asset, history: .init(fills: [], cashFlows: [])) }
        let cache = PerpsReadCache(url: url)
        cache.save(["a": .init(snapshot: snapshot, snapshotFetchedAt: .distantPast,
                               history: .init(fills: [], cashFlows: []), historyFetchedAt: .distantPast)])
        await cache.flush()
        let restored = store(client: client, url: url)
        await restored.loadFromCache(accountIds: ["a"])
        await restored.refreshAsset(accountId: "a", assetId: asset.id)
        await restored.loadFromCache(accountIds: ["a"])
        #expect(restored.isSnapshotStale(accountId: "a"))
        #expect(restored.isHistoryStale(accountId: "a"))
        let reopened = store(client: client, url: url)
        await reopened.loadFromCache(accountIds: ["a"])
        #expect(reopened.snapshots["a"]?.assets.first?.description == asset.description)
    }

    @Test func clearingDuringAnAssetOnlyFetchInvalidatesItsGeneration() async throws {
        let asset = try #require(snapshot().assets.first)
        var response: CheckedContinuation<ApiPerpsAssetDetail, Error>?
        var client = client()
        client.assetDetail = { _, _, _ in try await withCheckedThrowingContinuation { response = $0 } }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        let request = Task { await value.refreshAsset(accountId: "a", assetId: asset.id) }
        while response == nil { await Task.yield() }
        await value.clearCache()
        response?.resume(returning: .init(asset: asset, history: try history()))
        await request.value
        #expect(value.fills["a"] == nil)
        #expect(value.cashFlows["a"] == nil)
    }

    @Test func marketFreshnessUsesTheCatalogueFetchTimeIndependentlyOfPositions() async throws {
        let now = Date.now
        var response = try snapshot()
        response.assetsFetchedAt = Int64(now.addingTimeInterval(-120).timeIntervalSince1970 * 1_000)
        var client = client()
        client.snapshot = { _ in response }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        await value.refresh(accountId: "a")
        #expect(!value.isSnapshotStale(accountId: "a"))
        #expect(value.isMarketStale(accountId: "a", now: now))

        response.assetsFetchedAt = Int64(now.addingTimeInterval(-119).timeIntervalSince1970 * 1_000)
        await value.refresh(accountId: "a")
        #expect(!value.isMarketStale(accountId: "a", now: now))
        #expect(value.isMarketStale(accountId: "a", now: now.addingTimeInterval(2)))

        response.assetsFetchedAt = nil
        await value.refresh(accountId: "a")
        #expect(value.isMarketStale(accountId: "a", now: now))
    }

    @Test func pushedMarketUpdatesAllCachedAccountsWithoutRefreshingPositionsOrHistory() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date.now
        let fetchedAt = Int64(now.timeIntervalSince1970 * 1_000)
        var original = try snapshot()
        original.assetsFetchedAt = fetchedAt - 180_000
        original.assets[0].description = "Bitcoin description"
        var updatedAsset = original.assets[0]
        updatedAsset.description = nil
        updatedAsset.context.markPx = "61000"
        updatedAsset.context.percentChange24h = 1.6667
        updatedAsset.sparkline = [60000, 61000]
        let market = ApiPerpsMarketSnapshot(assets: [updatedAsset], marketSections: [], assetsFetchedAt: fetchedAt)
        let cache = PerpsReadCache(url: url)
        cache.save([
            "a": .init(snapshot: original, snapshotFetchedAt: now.addingTimeInterval(-61)),
            "b": .init(snapshot: original, snapshotFetchedAt: now),
        ])
        await cache.flush()
        var client = client()
        var reads = 0
        client.marketSnapshot = { reads += 1; return market }
        client.snapshot = { _ in Issue.record("Market pushes must not fetch positions"); return original }
        client.history = { _ in Issue.record("Market pushes must not fetch history"); return .init(fills: [], cashFlows: []) }
        let value = store(client: client, url: url)
        await value.loadFromCache(accountIds: ["a", "b"], now: now)
        let update = try JSONDecoder().decode(ApiUpdate.UpdatePerpsAssets.self, from: Data("""
        {"type":"updatePerpsAssets","assets":{"assetsByChain":{}},"fetchedAt":\(fetchedAt)}
        """.utf8))
        await value.receiveAssetsUpdate(update)
        await value.receiveAssetsUpdate(update)
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: fetchedAt - 1))
        await value.receiveAssetsUpdate(.init(langCode: "unsupported-language", fetchedAt: fetchedAt + 1))
        #expect(reads == 1)
        #expect(value.isSnapshotStale(accountId: "a", now: now))
        #expect(!value.isSnapshotStale(accountId: "b", now: now))
        for account in ["a", "b"] {
            #expect(value.snapshots[account]?.assets.first?.context.markPx == "61000")
            #expect(value.snapshots[account]?.assets.first?.context.percentChange24h == 1.6667)
            #expect(value.snapshots[account]?.assets.first?.description == "Bitcoin description")
            #expect(value.snapshots[account]?.assets.first?.sparkline == [60000, 61000])
            #expect(!value.isMarketStale(accountId: account, now: now))
        }
        let restored = store(client: client, url: url)
        await restored.loadFromCache(accountIds: ["a", "b"], now: now)
        #expect(restored.snapshots["a"] == value.snapshots["a"])
        #expect(!restored.isMarketStale(accountId: "a", now: now))
        #expect(restored.isSnapshotStale(accountId: "a", now: now))
    }

    @Test func delayedAccountSnapshotCannotReplaceANewerMarketPush() async throws {
        var original = try snapshot()
        original.assetsFetchedAt = 100
        var asset = original.assets[0]
        asset.context.markPx = "61000"
        let market = ApiPerpsMarketSnapshot(assets: [asset], marketSections: [], assetsFetchedAt: 200)
        var response: CheckedContinuation<ApiPerpsSnapshot, Error>?
        var client = client()
        client.snapshot = { _ in try await withCheckedThrowingContinuation { response = $0 } }
        client.marketSnapshot = { market }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        let request = Task { await value.refresh(accountId: "a") }
        while response == nil { await Task.yield() }
        await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: 200))
        response?.resume(returning: original)
        await request.value
        #expect(value.snapshots["a"]?.assets.first?.context.markPx == "61000")
        #expect(value.snapshots["a"]?.assetsFetchedAt == 200)
        #expect(value.snapshots["a"]?.totalEquity == original.totalEquity)
    }

    @Test func clearingDuringAMarketPushDiscardsItsResponse() async throws {
        let original = try snapshot()
        let market = ApiPerpsMarketSnapshot(assets: original.assets, assetsFetchedAt: 200)
        var response: CheckedContinuation<ApiPerpsMarketSnapshot, Error>?
        var client = client()
        client.snapshot = { _ in original }
        client.marketSnapshot = { try await withCheckedThrowingContinuation { response = $0 } }
        let value = PerpsStore(client: client, load: { [] }, save: { _ in })
        let request = Task { await value.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: 200)) }
        while response == nil { await Task.yield() }
        await value.clearCache()
        response?.resume(returning: market)
        await request.value
        await value.refresh(accountId: "a")
        #expect(value.snapshots["a"]?.assetsFetchedAt == nil)
    }

    private func cacheURL() -> URL {
        URL.temporaryDirectory.appending(components: UUID().uuidString, "perps.json")
    }

    private func store(client: PerpsClient, url: URL) -> PerpsStore {
        PerpsStore(client: client, cacheURL: url, load: { [] }, save: { _ in },
                   loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
    }

    private func client() -> PerpsClient {
        var client = PerpsClient()
        client.snapshot = { _ in throw PerpsError.invalidResponse }
        client.history = { _ in throw PerpsError.invalidResponse }
        client.receiptDetails = { _ in .init() }
        return client
    }

    private func snapshot() throws -> ApiPerpsSnapshot {
        try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
        "dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"60000","prevDayPx":"60000"}}],
        "marketSections":[],"positions":[],"totalEquity":"100","totalPnl":"2","timestamp":1,"unavailableDexs":[]}
        """.utf8))
    }

    private func history() throws -> ApiPerpsActivityHistory {
        try JSONDecoder().decode(ApiPerpsActivityHistory.self, from: Data("""
        {"fills":[{"coin":"BTC","tid":10,"oid":20,"time":1,"px":"60000","sz":"0.01","side":"B","dir":"Open Long",
        "startPosition":"0","closedPnl":"0","fee":"0.2","feeToken":"USDC","eventKind":"opened","positionSize":"0.01"}],
        "cashFlows":[{"id":"deposit/1","kind":"deposit","direction":"incoming","time":1,
        "amount":"10.1","token":"USDC","fees":[]}]}
        """.utf8))
    }
}

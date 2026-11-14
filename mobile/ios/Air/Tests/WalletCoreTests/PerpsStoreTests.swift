import Foundation
import Testing
import WalletContext
@testable import WalletCore

@Suite @MainActor
struct PerpsStoreTests {
    /// One saved record this version cannot read must not discard pending trades or withdrawals awaiting recovery.
    @Test func savedOperationsSurviveARecordThatCannotBeRead() throws {
        let kept = ApiPerpsOperation(id: "kept", accountId: "a", assetId: "hyperliquid:hl:BTC", kind: "close", createdAt: 0)
        var records = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([kept, kept])) as? [[String: Any]])
        records[0]["id"] = "unreadable"
        records[0]["createdAt"] = "yesterday"
        let decoded = PerpsStore.decodeOperations(try JSONSerialization.data(withJSONObject: records))
        #expect(decoded.map(\.id) == ["kept"])
    }

    @Test func filledWithdrawalBlocksOnlyUnsafeNewOrders() async throws {
        var partial = ApiPerpsOperation(id: "withdraw", accountId: "a", assetId: "hyperliquid:hl:BTC", kind: "close", createdAt: 0)
        partial.state = "partial"
        partial.stage = "finished"
        partial.orderStatus = "filled"
        partial.orderId = 42
        let store = PerpsStore(client: client(), load: { [partial] }, save: { _ in })
        #expect(store.pendingOperation(accountId: "a")?.id == partial.id)
        #expect(store.visibleOperationStatus(accountId: "a")?.id == partial.id)
        #expect(store.pendingOperation(accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "reduce") == nil)
        #expect(store.pendingOperation(accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "close") == nil)
        #expect(store.pendingOperation(accountId: "a", assetId: partial.assetId, kind: "close")?.id == partial.id)
        #expect(store.pendingOperation(accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "increase")?.id == partial.id)
        #expect(store.pendingOperation(accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "open")?.id == partial.id)

        for state in ["unknown", "running"] {
            partial.state = state
            let uncertain = PerpsStore(client: client(), load: { [partial] }, save: { _ in })
            #expect(uncertain.pendingOperation(accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "close") != nil)
        }
        partial.state = "partial"
        partial.orderStatus = nil
        let unconfirmed = PerpsStore(client: client(), load: { [partial] }, save: { _ in })
        #expect(unconfirmed.pendingOperation(accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "close") != nil)
    }

    @Test func anotherPositionCanBeReducedWhileFilledWithdrawalRemainsTracked() async throws {
        var partial = ApiPerpsOperation(id: "withdraw", accountId: "a", assetId: "hyperliquid:hl:ETH", kind: "close", createdAt: 0)
        partial.state = "partial"
        partial.orderStatus = "filled"
        partial.orderId = 42
        var client = client()
        var didExecute = false
        client.execute = { account, _, _, id in
            didExecute = true
            var completed = ApiPerpsOperation(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "reduce", createdAt: 1)
            completed.state = "completed"
            completed.stage = "finished"
            return completed
        }
        let store = PerpsStore(client: client, load: { [partial] }, save: { _ in })
        var review = try quote()
        review.kind = "reduce"
        #expect(try await store.execute(quote: review, enclaveToken: "test").state == "completed")
        #expect(didExecute)
        #expect(store.operations[partial.id]?.state == "partial")
    }

    @Test func backendPagesDeduplicateAndSurvivePolling() async throws {
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"BTC/42","assetId":"hyperliquid:hl:BTC","coin":"BTC","oid":42,
        "time":2000,"eventKind":"increased","positionSide":"long","feeToken":"USDC"}
        """.utf8))
        #expect(fill.id == "BTC/42")
        #expect(fill.positionSize == nil)
        #expect(fill.fee == nil)
        var older = fill
        older.activityId = "BTC/41"
        older.time = 1000
        var client = client()
        client.history = { _ in .init(fills: [fill], nextCursor: "page2") }
        var pages = 0
        client.historyPage = { account, cursor in
            #expect(account == "a")
            #expect(cursor == "page2")
            pages += 1
            return .init(fills: [fill, older])
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        await store.loadMoreHistory(accountId: "a")
        await store.refresh(accountId: "a")
        await store.loadMoreHistory(accountId: "a")
        #expect(pages == 1)
        #expect(store.fills["a"]?.map(\.id) == ["BTC/42", "BTC/41"])
        #expect(store.historyCursors["a"] == nil)
    }

    @Test func deletingAccountDiscardsPendingHistoryPage() async throws {
        var client = client()
        client.history = { _ in .init(fills: [], nextCursor: "page2") }
        var response: CheckedContinuation<ApiPerpsActivityHistory, Never>?
        client.historyPage = { _, _ in await withCheckedContinuation { response = $0 } }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        let task = Task { await store.loadMoreHistory(accountId: "a") }
        while response == nil { await Task.yield() }
        store.removeAccount("a")
        response?.resume(returning: .init(fills: [], nextCursor: "page3"))
        await task.value
        #expect(store.fills["a"] == nil)
        #expect(store.historyCursors["a"] == nil)
    }

    @Test func historyIsAccountScopedAndFailedRefreshPreservesIt() async throws {
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"BTC/42","coin":"BTC","oid":42,"time":1,"eventKind":"opened","positionSide":"long","feeToken":"USDC"}
        """.utf8))
        var client = client()
        var fail = false
        client.positions = { _ in .init(positions: [], totalEquity: "0", totalPnl: "0", timestamp: 1, unavailableDexs: []) }
        client.history = { account in
            if fail { throw PerpsError.invalidResponse }
            return .init(fills: account == "a" ? [fill, fill] : [])
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        await store.refresh(accountId: "b")
        #expect(store.fills["a"] == [fill])
        #expect(store.fills["b"] == [])
        fail = true
        await store.refresh(accountId: "a")
        #expect(store.fills["a"] == [fill])
        store.removeAccount("a")
        #expect(store.fills["a"] == nil)
    }

    @Test func walletRefreshReadsPositionsOnlyAndFuturesStillReadsActivity() async throws {
        var historyReads = 0
        var client = client()
        client.positions = { _ in .init(positions: [], totalEquity: "0", totalPnl: "0", timestamp: 1, unavailableDexs: []) }
        client.history = { _ in
            historyReads += 1
            return .init(fills: [])
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a", includesHistory: false)
        #expect(store.snapshots["a"] != nil)
        #expect(historyReads == 0)
        await store.refresh(accountId: "a")
        #expect(historyReads == 1)
    }

    @Test func completedReceiptIsComputedAgainOnlyWhenItsFillChanges() async throws {
        func fill(fee: String) throws -> ApiPerpsFill {
            try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
            {"activityId":"BTC/7","coin":"BTC","oid":7,"time":1,"eventKind":"opened","positionSide":"long","fee":"\(fee)","feeToken":"USDC"}
            """.utf8))
        }
        var history = [try fill(fee: "0.1")]
        var operation = ApiPerpsOperation(id: "done", accountId: "a", assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
        operation.state = "completed"
        operation.stage = "finished"
        operation.orderId = 7
        operation.reviewedQuote = try quote()
        var receiptReads = 0
        var client = client()
        client.history = { _ in .init(fills: history) }
        client.receiptDetails = { input in
            receiptReads += 1
            return .init(receiveAmount: input.fill?.fee)
        }
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        await store.refresh(accountId: "a")
        await store.refresh(accountId: "a")
        #expect(receiptReads == 1)
        history = [try fill(fee: "0.2")]
        await store.refresh(accountId: "a")
        #expect(receiptReads == 2)
        #expect(store.operations["done"]?.receiptDetails?.receiveAmount == "0.2")
    }

    @Test func marketPagesStayOutOfAccountActivity() async throws {
        let snapshot = ApiPerpsAccountSnapshot(positions: [], totalEquity: "0", totalPnl: "0", timestamp: 1, unavailableDexs: [])
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"1"}}
        """.utf8))
        func fill(_ id: String, time: Int64) throws -> ApiPerpsFill {
            try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
            {"activityId":"\(id)","coin":"BTC","time":\(time),"eventKind":"opened","positionSide":"long","feeToken":"USDC"}
            """.utf8))
        }
        let recent = try fill("recent", time: 2)
        let older = try fill("older", time: 1)
        // The market page was read before the account refresh updated the same activity.
        let staleRecent = try fill("recent", time: 0)
        var refreshDuringMarketRead: () async -> Void = {}
        var client = client()
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: [recent]) }
        client.assetDetail = { _, _, _ in
            await refreshDuringMarketRead()
            return .init(asset: asset, history: .init(fills: [older, staleRecent]))
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        refreshDuringMarketRead = { await store.refresh(accountId: "a") }
        await store.refreshAsset(accountId: "a", assetId: asset.id)
        #expect(store.fills["a"]?.map(\.id) == ["recent"])
        #expect(store.fills(accountId: "a", assetId: asset.id)?.map(\.id) == ["recent", "older"])
        #expect(store.fills(accountId: "a", assetId: asset.id)?.first?.time == 2)
        #expect(store.fill(accountId: "a", id: "older")?.time == 1)
        #expect(store.hasActivityHistory["a"] == true)
        store.removeAccount("a")
        #expect(store.fills(accountId: "a", assetId: asset.id) == nil)
    }

    /// An old trade leaves the account's refreshed first page, so a market read is the only one that sees it settle.
    @Test func marketReadUpdatesTheAccountCopyOfATrade() async throws {
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"1"}}
        """.utf8))
        func fill(status: String) throws -> ApiPerpsFill {
            try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
            {"activityId":"trade","coin":"BTC","time":1,"eventKind":"closed","positionSide":"long","feeToken":"USDC",
            "withdrawal":{"amount":"1","bridgeFee":"0.2","receivedAmount":"0.8","status":"\(status)"}}
            """.utf8))
        }
        let pending = try fill(status: "pending")
        var client = client()
        client.history = { _ in .init(fills: [pending]) }
        client.assetDetail = { _, _, _ in .init(asset: asset, history: .init(fills: [try fill(status: "completed")])) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        #expect(store.fill(accountId: "a", id: "trade")?.withdrawal?.status == "pending")
        await store.refreshAsset(accountId: "a", assetId: asset.id)
        #expect(store.fills["a"]?.first?.withdrawal?.status == "completed")
        #expect(store.fill(accountId: "a", id: "trade")?.withdrawal?.status == "completed")
        #expect(store.fills(accountId: "a", assetId: asset.id)?.first?.withdrawal?.status == "completed")
    }

    @Test func catalogueKeepsAnAssetItStopsListingWhileAPositionIsOpen() async throws {
        func asset(_ name: String) throws -> ApiPerpsAsset {
            try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
            {"id":"hyperliquid:hl:\(name)","name":"\(name)","symbol":"\(name)","dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"1"}}
            """.utf8))
        }
        let position = try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
        "collateral":"99.8","equity":"100","raw":{"coin":"BTC","entryPx":"60000","liquidationPx":"30000",
        "leverage":{"type":"isolated","value":2},"marginUsed":"100","positionValue":"600","returnOnEquity":"0",
        "szi":"0.01","unrealizedPnl":"0.2"}}
        """.utf8))
        let (btc, eth, sol) = (try asset("BTC"), try asset("ETH"), try asset("SOL"))
        var catalogue = ApiPerpsMarketSnapshot(assets: [btc, eth, sol], assetsFetchedAt: 1)
        var positions = [position]
        var client = client()
        client.marketSnapshot = { catalogue }
        client.positions = { _ in .init(positions: positions, totalEquity: "100", totalPnl: "0", timestamp: 1, unavailableDexs: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")

        catalogue = .init(assets: [sol], assetsFetchedAt: 2)
        await store.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: 2))
        #expect(store.market?.assetsFetchedAt == 2)
        #expect(store.asset(id: btc.id)?.name == "BTC")
        #expect(store.asset(named: "BTC")?.id == btc.id)
        #expect(store.asset(id: eth.id) == nil)

        positions = []
        await store.refresh(accountId: "a")
        catalogue = .init(assets: [sol], assetsFetchedAt: 3)
        await store.receiveAssetsUpdate(.init(langCode: nil, fetchedAt: 3))
        #expect(store.asset(id: btc.id) == nil)
        #expect(store.asset(id: sol.id)?.name == "SOL")
    }

    @Test func expiredReviewNeverStartsExecutionAndErrorsRemainActionable() async throws {
        var client = client()
        client.execute = { _, _, _, _ in Issue.record("Expired quote must not reach the SDK"); throw PerpsError.expired }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        var quote = try quote()
        quote.expiresAt = 0
        do {
            _ = try await store.execute(quote: quote, enclaveToken: "test")
            Issue.record("Expected expiry rejection")
        } catch {
            #expect(error.localizedDescription == lang("PerpsQuoteExpired"))
            #expect(PerpsFormatting.error(error) == lang("PerpsQuoteExpired"))
        }
        #expect(store.operations.isEmpty)
        #expect(PerpsFormatting.errorMessage("PerpsInsufficientGas") == lang("PerpsInsufficientGas"))
        #expect(PerpsFormatting.errorMessage("PerpsInsufficientBalance") == lang("PerpsInsufficientBalance"))
        #expect(PerpsFormatting.errorMessage("PerpsMarketNeedsUnifiedAccount") == lang("PerpsMarketNeedsUnifiedAccount"))
        #expect(PerpsFormatting.errorMessage("InsufficientBalance") == ApiAnyDisplayError.insufficientBalance.toLocalized)
        #expect(PerpsFormatting.errorMessage("EvmUserOperationMismatch") == lang("EvmUserOperationMismatch"))
        #expect(PerpsError.pending.localizedDescription == lang("PerpsOperationPending"))
    }

    @Test func confirmedRejectionRetainsVenueReasonWithoutLockingAnotherReview() async throws {
        var client = client()
        client.execute = { account, _, _, id in
            var result = ApiPerpsOperation(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "reduce", createdAt: 0)
            result.state = "failed"
            result.stage = "finished"
            result.orderStatus = "error: Order must have minimum value of $10. asset=0"
            result.error = "PerpsOrderTooSmall"
            return result
        }
        var saved: [ApiPerpsOperation] = []
        let store = PerpsStore(client: client, load: { [] }, save: { saved = $0 })
        var review = try quote()
        review.kind = "reduce"
        let result = try await store.execute(quote: review, enclaveToken: "test")
        #expect(result.state == "failed")
        #expect(store.pendingOperation(accountId: "a") == nil)
        #expect(saved.first?.orderStatus == result.orderStatus)
        #expect(saved.first?.reviewedQuote == review)
        #expect(PerpsFormatting.operationMessage(result) == lang("PerpsOrderTooSmall"))
        let restored = try JSONDecoder().decode(ApiPerpsOperation.self, from: JSONEncoder().encode(result))
        #expect(restored == result)
    }

    @Test(arguments: [false, true])
    func receiptContextSurvivesProgressAndRestartWithoutUsingAnotherOrdersPosition(grouped: Bool) async throws {
        var client = client()
        var quote = try quote()
        quote.leverage = 2
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
        "dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"60000","prevDayPx":"60000"}}
        """.utf8))
        let position = try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
        "collateral":"99.8","equity":"100","raw":{"coin":"BTC","entryPx":"60000","liquidationPx":"30000",
        "leverage":{"type":"isolated","value":2},"marginUsed":"100","positionValue":"600","returnOnEquity":"0",
        "szi":"0.01","unrealizedPnl":"0.2"}}
        """.utf8))
        var fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"BTC","tid":10,"oid":999,"time":1792866000000,"px":"60000","sz":"0.01","side":"B","dir":"Open Long",
        "startPosition":"0","closedPnl":"0","fee":"0.2","feeToken":"USDC","eventKind":"opened","positionSide":"long","positionSize":"0.01"}
        """.utf8))
        var operation = ApiPerpsOperation(id: "receipt", accountId: "a", assetId: asset.id, kind: quote.kind, createdAt: 1)
        operation.state = "completed"
        operation.orderId = 20
        operation.reviewedQuote = quote
        if grouped {
            fill.positionSize = nil
            fill.activityId = "BTC/42"
            operation.positionSize = position.size
        }
        client.marketSnapshot = { .init(assets: [asset], assetsFetchedAt: 1) }
        client.positions = { _ in .init(positions: [position], totalEquity: "100", totalPnl: "0", timestamp: 2, unavailableDexs: []) }
        client.history = { _ in .init(fills: [fill]) }
        var saved: [ApiPerpsOperation] = []
        let store = PerpsStore(client: client, load: { [operation] }, save: { saved = $0 })
        await store.refresh(accountId: "a")
        #expect(store.operations[operation.id]?.receiptPosition == nil)
        fill.oid = 20
        await store.refresh(accountId: "a")
        #expect(store.operations[operation.id]?.receiptPosition == position)
        let persisted = try JSONDecoder().decode([ApiPerpsOperation].self, from: JSONEncoder().encode(saved))
        let restored = PerpsStore(client: client, load: { persisted }, save: { _ in })
        #expect(restored.operations[operation.id]?.reviewedQuote == quote)
        #expect(restored.operations[operation.id]?.receiptPosition == position)
    }

    @Test func receiptPositionIsCapturedFromThePositionsPushThatFollowsItsFill() async throws {
        var quote = try quote()
        quote.leverage = 2
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"60000"}}
        """.utf8))
        let position = try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"a/hyperliquid:hl:BTC","assetId":"hyperliquid:hl:BTC","dex":"","side":"long","size":"0.01",
        "collateral":"99.8","equity":"100","raw":{"coin":"BTC","leverage":{"type":"isolated","value":2},
        "marginUsed":"100","positionValue":"600","returnOnEquity":"0","szi":"0.01","unrealizedPnl":"0.2"}}
        """.utf8))
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"BTC/20","coin":"BTC","oid":20,"time":2,"feeToken":"USDC","eventKind":"opened","positionSide":"long",
         "positionSize":"0.01"}
        """.utf8))
        var operation = ApiPerpsOperation(id: "receipt", accountId: "a", assetId: asset.id, kind: quote.kind, createdAt: 10)
        operation.state = "completed"
        operation.orderId = 20
        operation.reviewedQuote = quote
        var receiptReads = 0
        var client = client()
        client.marketSnapshot = { .init(assets: [asset], assetsFetchedAt: 1) }
        client.history = { _ in .init(fills: [fill]) }
        client.receiptDetails = { _ in
            receiptReads += 1
            return .init(receiveAmount: "\(receiptReads)")
        }
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        // The positions read before the operation finished cannot settle its receipt.
        await store.refresh(accountId: "a")
        #expect(store.operations[operation.id]?.receiptPosition == nil)
        #expect(receiptReads == 1)
        store.walletCore(event: .updatePerpsPositions(.init(accountId: "a", snapshot: .init(
            positions: [position], totalEquity: "100", totalPnl: "0", timestamp: 11, unavailableDexs: []))))
        #expect(store.operations[operation.id]?.receiptPosition == position)
        while receiptReads < 2 { await Task.yield() }
        while store.operations[operation.id]?.receiptDetails?.receiveAmount != "2" { await Task.yield() }
        store.walletCore(event: .updatePerpsPositions(.init(accountId: "a", snapshot: .init(
            positions: [position], totalEquity: "101", totalPnl: "1", timestamp: 12, unavailableDexs: []))))
        for _ in 0..<10 { await Task.yield() }
        #expect(receiptReads == 2)
    }

    @Test func afterAnOperationTheActiveAccountReadsActivityWhileTheSDKPushesItsPositions() async throws {
        var positionReads = 0
        var historyReads = 0
        var client = client()
        client.positions = { _ in
            positionReads += 1
            return .init(positions: [], totalEquity: "0", totalPnl: "0", timestamp: 0, unavailableDexs: [])
        }
        client.history = { _ in
            historyReads += 1
            return .init(fills: [])
        }
        client.execute = { account, _, _, id in
            var result = ApiPerpsOperation(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
            result.state = "completed"
            result.stage = "finished"
            return result
        }
        let store = PerpsStore(client: client, currentAccountId: { "a" }, load: { [] }, save: { _ in })
        store.walletCore(event: .updatePerpsPositions(.init(accountId: "a", snapshot: .init(
            positions: [], totalEquity: "0", totalPnl: "0", timestamp: 0, unavailableDexs: []))))
        #expect(try await store.execute(quote: quote(), enclaveToken: "test").state == "completed")
        while historyReads == 0 || store.loading.contains("a") { await Task.yield() }
        #expect(historyReads == 1)
        #expect(positionReads == 0)
    }

    /// Screens share one loop per account. It reads at the shortest interval its live watchers ask for.
    @Test func watchersShareOneLoopAtTheShortestIntervalWhileTheyAreAlive() async throws {
        var reads = 0
        var client = client()
        client.history = { _ in
            reads += 1
            return .init(fills: [])
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        store.isApplicationActive = { true }
        let tab = NSObject()
        var receipt: NSObject? = NSObject()
        store.watch(accountId: "a", every: .seconds(60), by: tab)
        while reads < 1 { await Task.yield() }
        store.watch(accountId: "a", every: .milliseconds(10), by: try #require(receipt))
        while reads < 4 { await Task.yield() }
        receipt = nil
        // The released receipt's interval serves at most one more read before the loop returns to the tab's.
        try await Task.sleep(for: .milliseconds(100))
        let afterRelease = reads
        try await Task.sleep(for: .milliseconds(200))
        #expect(reads == afterRelease)
        store.unwatch(by: tab)
    }

    @Test func dismissingUnknownStatusPersistsWithoutUnlockingOrResubmitting() async throws {
        var client = client()
        let initial = ApiPerpsOperation(id: "interrupted", accountId: "a", assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
        var updated = initial
        updated.state = "unknown"
        client.reconcile = { _, _ in updated }
        client.execute = { _, _, _, _ in Issue.record("Dismissal must not permit execution"); return initial }
        var dismissed: Set<String> = []
        let store = PerpsStore(client: client, load: { [initial] }, save: { _ in },
                              loadDismissedStatuses: { dismissed }, saveDismissedStatuses: { dismissed = $0 })
        store.dismissOperationStatus(id: initial.id, accountId: "another-wallet")
        #expect(store.visibleOperationStatus(accountId: "a") != nil)
        store.dismissOperationStatus(id: initial.id, accountId: "a")
        #expect(store.visibleOperationStatus(accountId: "a") == nil)
        #expect(store.pendingOperation(accountId: "a")?.id == initial.id)
        await #expect(throws: PerpsError.self) { try await store.execute(quote: self.quote(), enclaveToken: "test") }
        await store.reconcile(accountId: "a")
        #expect(store.visibleOperationStatus(accountId: "a") == nil)
        let restored = PerpsStore(client: client, load: { [updated] }, save: { _ in },
                                 loadDismissedStatuses: { dismissed }, saveDismissedStatuses: { dismissed = $0 })
        #expect(restored.visibleOperationStatus(accountId: "a") == nil)
        #expect(restored.pendingOperation(accountId: "a") != nil)
        updated.state = "partial"
        await restored.reconcile(accountId: "a")
        #expect(restored.visibleOperationStatus(accountId: "a")?.state == "partial")
        #expect(dismissed.isEmpty)
    }

    private func client() -> PerpsClient {
        var client = PerpsClient()
        client.marketSnapshot = { throw PerpsError.invalidResponse }
        client.positions = { _ in .init(positions: [], totalEquity: "0", totalPnl: "0", timestamp: 0, unavailableDexs: []) }
        client.history = { _ in .init(fills: []) }
        client.receiptDetails = { _ in .init() }
        return client
    }

    @Test func explicitAcknowledgementPreservesHistoryAcrossRestartAndUnlocksFreshOrders() async throws {
        var client = client()
        var initial = ApiPerpsOperation(id: "unknown", accountId: "a", assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
        initial.state = "unknown"
        initial.depositTxHash = "0xdeposit"
        var calls = 0
        client.acknowledge = { account, saved in
            #expect(account == "a" && saved == initial)
            calls += 1
            var updated = saved
            updated.acknowledgedAt = 100
            return updated
        }
        client.reconcile = { _, saved in saved }
        var persisted = [initial]
        let store = PerpsStore(client: client, load: { persisted }, save: { persisted = $0 })
        await #expect(throws: PerpsError.self) { try await store.acknowledgeUnknownOperation(id: initial.id, accountId: "other") }
        #expect(calls == 0)
        try await store.acknowledgeUnknownOperation(id: initial.id, accountId: "a")
        #expect(calls == 1)
        #expect(store.pendingOperation(accountId: "a") == nil)
        #expect(store.visibleOperationStatus(accountId: "a") == nil)
        #expect(store.operations[initial.id]?.needsReconciliation == true)
        #expect(persisted.first?.depositTxHash == "0xdeposit")
        #expect(persisted.first?.state == "unknown")
        client.execute = { account, _, _, id in
            #expect(id != initial.id)
            var result = ApiPerpsOperation(id: id, accountId: account, assetId: initial.assetId, kind: "open", createdAt: 1)
            result.state = "completed"
            return result
        }
        let restored = PerpsStore(client: client, load: { persisted }, save: { persisted = $0 })
        await restored.reconcile(accountId: "a")
        #expect(restored.pendingOperation(accountId: "a") == nil)
        #expect(try await restored.execute(quote: quote(), enclaveToken: "test").state == "completed")
        #expect(restored.operations[initial.id]?.acknowledgedAt == 100)
    }

    @Test func acknowledgementRejectsPartialOrUnacknowledgedResponses() async {
        var client = client()
        var initial = ApiPerpsOperation(id: "pending", accountId: "a", assetId: "BTC", kind: "close", createdAt: 0)
        initial.state = "partial"
        var calls = 0
        client.acknowledge = { _, saved in calls += 1; return saved }
        let partial = PerpsStore(client: client, load: { [initial] }, save: { _ in })
        await #expect(throws: PerpsError.self) { try await partial.acknowledgeUnknownOperation(id: initial.id, accountId: "a") }
        #expect(calls == 0)
        initial.state = "unknown"
        let unknown = PerpsStore(client: client, load: { [initial] }, save: { _ in })
        await #expect(throws: PerpsError.self) { try await unknown.acknowledgeUnknownOperation(id: initial.id, accountId: "a") }
        #expect(calls == 1)
        #expect(unknown.pendingOperation(accountId: "a") != nil)
    }

    @Test func lateReconciliationCannotOverwriteAcknowledgement() async throws {
        var client = client()
        var initial = ApiPerpsOperation(id: "recovering", accountId: "a", assetId: "BTC", kind: "open", createdAt: 0)
        initial.state = "unknown"
        var response: CheckedContinuation<ApiPerpsOperation, Error>?
        client.reconcile = { _, _ in try await withCheckedThrowingContinuation { response = $0 } }
        client.acknowledge = { _, saved in var updated = saved; updated.acknowledgedAt = 100; return updated }
        let store = PerpsStore(client: client, load: { [initial] }, save: { _ in })
        let reconciliation = Task { await store.reconcile(accountId: "a") }
        while response == nil { await Task.yield() }
        try await store.acknowledgeUnknownOperation(id: initial.id, accountId: "a")
        response?.resume(returning: initial)
        await reconciliation.value
        #expect(store.operations[initial.id]?.acknowledgedAt == 100)
        #expect(store.pendingOperation(accountId: "a") == nil)
    }
    private func withdrawalQuote(expiresAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000) + 60000) -> ApiPerpsBalanceWithdrawalQuote {
        .init(id: "withdrawal", accountId: "a", destination: "0xwallet", balance: "1.5", amount: "1.47",
              bridgeFee: "0.2", receiveAmount: "1.27", expiresAt: expiresAt)
    }

    @Test func snapshotDecodesTheWithdrawalPreviewAndOldCachesWithoutIt() throws {
        let body = #""positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]"#
        let preview = #""balanceWithdrawal":{"balance":"1.5","amount":"1.47","bridgeFee":"0.2","receiveAmount":"1.27"}"#
        let offered = try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("{\(body),\(preview)}".utf8))
        #expect(offered.balanceWithdrawal?.receiveAmount == "1.27")
        let old = try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("{\(body)}".utf8))
        #expect(old.balanceWithdrawal == nil)
    }

    @Test func balanceWithdrawalIsTrackedFromSubmissionToSettlementAndSurvivesARestart() async throws {
        var client = client()
        var continuation: CheckedContinuation<ApiPerpsOperation, Error>?
        var requested: (token: EnclaveToken, quoteId: String)?
        client.executeBalanceWithdrawal = { _, token, quoteId, _ in
            guard requested == nil else { throw PerpsError.invalidResponse }
            requested = (token, quoteId)
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        var persisted: [ApiPerpsOperation] = []
        let store = PerpsStore(client: client, load: { [] }, save: { persisted = $0 })
        let review = withdrawalQuote()
        let confirmation = Task { try await store.executeBalanceWithdrawal(quote: review, enclaveToken: "fresh") }
        while continuation == nil { await Task.yield() }
        #expect(requested?.token == "fresh")
        #expect(requested?.quoteId == "withdrawal")
        var update = try #require(store.operations.values.first)
        #expect(update.kind == "withdraw")
        #expect(update.assetId == "USDC")
        #expect(update.balanceWithdrawal == review)
        #expect(store.pendingOperation(accountId: "a")?.id == update.id)
        _ = try await #require(throws: PerpsError.self) { try await store.executeBalanceWithdrawal(quote: review, enclaveToken: "fresh") }

        update.stage = "withdrawal"
        store.walletCore(event: .perpsOperationUpdated(.init(operation: update)))
        #expect(try await confirmation.value == update)
        #expect(PerpsFormatting.operationMessage(update) == lang("PerpsWithdrawalProcessing"))

        let restored = PerpsStore(client: self.client(), load: { persisted }, save: { _ in })
        #expect(restored.operations[update.id]?.state == "unknown")
        #expect(restored.operations[update.id]?.balanceWithdrawal == review)
        #expect(PerpsFormatting.operationMessage(try #require(restored.operations[update.id])) == lang("PerpsWithdrawalUnknown"))

        update.state = "completed"
        update.stage = "finished"
        continuation?.resume(returning: update)
        while store.pendingOperation(accountId: "a") != nil { await Task.yield() }
        #expect(store.operations[update.id] == update)
        #expect(PerpsFormatting.operationMessage(update) == lang("PerpsWithdrawalOnItsWay"))
    }

    @Test func expiredWithdrawalQuoteNeverReachesTheSDK() async throws {
        var client = client()
        client.executeBalanceWithdrawal = { _, _, _, _ in Issue.record("Expired quote must not reach the SDK"); throw PerpsError.expired }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await #expect(throws: PerpsError.self) {
            try await store.executeBalanceWithdrawal(quote: withdrawalQuote(expiresAt: 0), enclaveToken: "test")
        }
        #expect(store.operations.isEmpty)
    }

    @Test(arguments: [("PerpsQuoteExpired", "failed"), ("PerpsOperationPending", "failed"), ("connection lost", "unknown")])
    func withdrawalErrorsFailOnlyWhenTheSDKRefusedIt(_ message: String, _ state: String) async throws {
        var client = client()
        client.executeBalanceWithdrawal = { _, _, _, _ in throw NSError(domain: message, code: 0) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        let result = try await store.executeBalanceWithdrawal(quote: withdrawalQuote(), enclaveToken: "test")
        #expect(result.state == state)
        #expect((store.pendingOperation(accountId: "a") != nil) == (state == "unknown"))
    }

    @Test func aResponseForAnotherOperationIsNeverTakenAsTheWithdrawalsResult() async throws {
        var client = client()
        client.executeBalanceWithdrawal = { account, _, _, id in
            var result = ApiPerpsOperation(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "close", createdAt: 0)
            result.state = "completed"
            return result
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        let result = try await store.executeBalanceWithdrawal(quote: withdrawalQuote(), enclaveToken: "test")
        #expect(result.state == "unknown")
        #expect(result.kind == "withdraw")
        #expect(store.pendingOperation(accountId: "a")?.id == result.id)
    }

    @Test func withdrawalRefusalsAreLocalized() {
        #expect(PerpsFormatting.errorMessage("PerpsNothingToWithdraw") == lang("PerpsNothingToWithdraw"))
        #expect(PerpsFormatting.errorMessage("PerpsWithdrawalRejected: [HL_EXCHANGE_ERROR] nope") == lang("PerpsWithdrawalRejected"))
        var operation = ApiPerpsOperation(id: "withdrawal", accountId: "a", assetId: "USDC", kind: "withdraw", createdAt: 0)
        #expect(PerpsFormatting.operationTitle(operation, symbol: "USDC") == lang("Withdrawal") + " · USDC")
        operation.state = "failed"
        operation.error = "PerpsWithdrawalRejected: [HL_EXCHANGE_ERROR] nope"
        #expect(PerpsFormatting.operationMessage(operation) == lang("PerpsWithdrawalRejected"))
    }

    private func quote(account: String = "a") throws -> ApiPerpsQuote {
        let json = """
        {"id":"quote", "accountId":"\(account)", "assetId":"hyperliquid:hl:BTC", "kind":"open", "side":"long", "leverage":10,
         "inputAmount":"50", "collateral":"50", "size":"0.005", "notional":"500", "markPrice":"100000", "paymentAmount":"50.2",
         "bridgeFee":"0.2", "expiresAt":\(Int64(Date().timeIntervalSince1970 * 1000) + 60000), "createdAt":0}
        """
        return try JSONDecoder().decode(ApiPerpsQuote.self, from: Data(json.utf8))
    }

    @Test(arguments: ["open", "increase", "reduce", "close", "leverage"])
    func submissionUpdateReleasesConfirmationWhileExecutionRemainsOwned(_ kind: String) async throws {
        var client = client()
        var continuation: CheckedContinuation<ApiPerpsOperation, Error>?
        var pending: ApiPerpsOperation?
        client.execute = { account, _, _, id in
            pending = .init(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: kind, createdAt: 0)
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        var persisted: [ApiPerpsOperation] = []
        let store = PerpsStore(client: client, load: { [] }, save: { persisted = $0 })
        var review = try quote()
        review.kind = kind
        var returned = false
        let confirmation = Task { let value = try await store.execute(quote: review, enclaveToken: "test"); returned = true; return value }
        while continuation == nil { await Task.yield() }
        var update = try #require(pending)
        update.stage = ["open", "increase"].contains(kind) ? "deposit" : "trade"
        var other = update
        other.accountId = "another-wallet"
        store.walletCore(event: .perpsOperationUpdated(.init(operation: other)))
        other = update; other.assetId = "another-asset"
        store.walletCore(event: .perpsOperationUpdated(.init(operation: other)))
        other = update; other.kind = "another-kind"
        store.walletCore(event: .perpsOperationUpdated(.init(operation: other)))
        store.walletCore(event: .perpsOperationUpdated(.init(operation: try #require(pending))))
        await Task.yield()
        #expect(!returned)
        // Exercise the same event path as the bridge, before the SDK call resolves.
        store.walletCore(event: .perpsOperationUpdated(.init(operation: update)))
        update.reviewedQuote = review
        #expect(try await confirmation.value == update)
        #expect(persisted.first == update)
        #expect(store.pendingOperation(accountId: "a")?.id == update.id)
        await #expect(throws: PerpsError.self) { try await store.execute(quote: review, enclaveToken: "test") }
        update.state = "failed"
        update.stage = "finished"
        update.error = "PerpsOrderTooSmall"
        store.walletCore(event: .perpsOperationUpdated(.init(operation: update)))
        #expect(store.pendingOperation(accountId: "a") == nil)
        continuation?.resume(returning: update)
        #expect(store.operations[update.id] == update)
        #expect(persisted.first?.error == "PerpsOrderTooSmall")
    }

    @Test func completionDoesNotWaitForBalanceRefresh() async throws {
        var client = client()
        var refresh: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
        client.positions = { _ in try await withCheckedThrowingContinuation { refresh = $0 } }
        client.execute = { account, _, _, id in
            var value = ApiPerpsOperation(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
            value.state = "completed"
            value.stage = "finished"
            return value
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        let result = try await store.execute(quote: quote(), enclaveToken: "test")
        #expect(result.state == "completed")
        while refresh == nil { await Task.yield() }
        #expect(store.loading.contains("a"))
        refresh?.resume(throwing: PerpsError.invalidResponse)
    }

    @Test func withdrawalSubmissionContinuesAfterConfirmationReturns() async throws {
        var client = client()
        var operation = ApiPerpsOperation(id: "retry-background", accountId: "a", assetId: "BTC", kind: "close", createdAt: 0)
        operation.state = "partial"
        operation.stage = "withdrawal"
        var completion: CheckedContinuation<ApiPerpsOperation, Error>?
        client.retryWithdrawal = { _, _, _ in try await withCheckedThrowingContinuation { completion = $0 } }
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        let confirmation = Task { try await store.retryWithdrawal(operation: operation, enclaveToken: "fresh") }
        while completion == nil { await Task.yield() }
        #expect(store.operations[operation.id]?.stage == "preparing")
        operation.state = "running"
        store.walletCore(event: .perpsOperationUpdated(.init(operation: operation)))
        #expect(try await confirmation.value.state == "running")
        #expect(store.pendingOperation(accountId: "a") != nil)
        operation.state = "completed"
        operation.stage = "finished"
        completion?.resume(returning: operation)
        while store.operations[operation.id]?.state == "running" { await Task.yield() }
        #expect(store.pendingOperation(accountId: "a") == nil)
    }

    @Test func concurrentReadsCoalesceAndDeletedAccountCannotReappear() async {
        var client = client()
        var reads = 0
        var continuation: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
        client.positions = { _ in
            reads += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        let first = Task { await store.refresh(accountId: "a") }
        while continuation == nil { await Task.yield() }
        var secondStarted = false
        let second = Task { secondStarted = true; await store.refresh(accountId: "a") }
        while !secondStarted { await Task.yield() }
        store.removeAccount("a")
        continuation?.resume(returning: .init(positions: [], totalEquity: "100", totalPnl: "5", timestamp: 0, unavailableDexs: []))
        await first.value; await second.value
        #expect(reads == 1)
        #expect(store.snapshots["a"] == nil)
        #expect(!store.loading.contains("a"))
    }

    @Test func submissionIsOwnedByStoreAndSerializesOnlyItsAccount() async throws {
        var client = client()
        var continuation: CheckedContinuation<ApiPerpsOperation, Error>?
        var pending: ApiPerpsOperation?
        client.execute = { account, _, _, id in
            pending = .init(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        var persisted: [ApiPerpsOperation] = []
        let store = PerpsStore(client: client, load: { [] }, save: { persisted = $0 })
        let quote = try quote()
        let task = Task { try await store.execute(quote: quote, enclaveToken: "test") }
        while continuation == nil { await Task.yield() }
        #expect(store.pendingOperation(accountId: "a") != nil)
        #expect(store.pendingOperation(accountId: "b") == nil)
        #expect(persisted.first?.state == "running")
        do {
            _ = try await store.execute(quote: quote, enclaveToken: "test")
            Issue.record("Duplicate submission must fail")
        } catch { #expect(error is PerpsError) }
        task.cancel()
        var completed = try #require(pending)
        completed.state = "completed"
        continuation?.resume(returning: completed)
        #expect(try await task.value.state == "completed")
        #expect(store.pendingOperation(accountId: "a") == nil)
    }

    @Test func restoredOperationsReconcileWithSavedIdentityAndKeepUnknownLocked() async {
        var client = client()
        var initial = ApiPerpsOperation(id: "saved", accountId: "a", assetId: "BTC", kind: "close", createdAt: 0)
        initial.depositTxHash = "0xdeposit"
        var received: ApiPerpsOperation?
        client.reconcile = { _, saved in received = saved; return saved }
        let store = PerpsStore(client: client, load: { [initial] }, save: { _ in })
        #expect(store.operations["saved"]?.state == "unknown")
        await store.reconcile(accountId: "a")
        #expect(received?.depositTxHash == "0xdeposit")
        #expect(store.pendingOperation(accountId: "a")?.id == "saved")
    }

    @Test func partialTradeRetriesOnlyWithdrawalWithFreshAuthentication() async throws {
        var client = client()
        var initial = ApiPerpsOperation(id: "closed", accountId: "a", assetId: "BTC", kind: "close", createdAt: 0)
        initial.state = "partial"
        initial.orderId = 123
        var calls = 0
        client.execute = { _, _, _, _ in Issue.record("Must not place another order"); return initial }
        client.retryWithdrawal = { account, token, id in
            #expect(account == "a" && token == "fresh" && id == "closed")
            calls += 1
            var result = initial; result.state = "completed"; return result
        }
        let store = PerpsStore(client: client, load: { [initial] }, save: { _ in })
        let result = try await store.retryWithdrawal(operation: initial, enclaveToken: "fresh")
        #expect(calls == 1 && result.orderId == 123 && result.state == "completed")
    }

    @Test func knownRejectionAndTransportFailureHaveDifferentRetrySemantics() async throws {
        struct Rejection: Error, CustomStringConvertible { let description: String }
        for code in ["PerpsQuoteExpired", "Connection lost"] {
            var client = client()
            client.execute = { _, _, _, _ in throw Rejection(description: code) }
            let store = PerpsStore(client: client, load: { [] }, save: { _ in })
            let result = try await store.execute(quote: quote(), enclaveToken: "test")
            #expect(result.state == (code == "PerpsQuoteExpired" ? "failed" : "unknown"))
        }
    }

    @Test func decimalFormattingDoesNotRoundThroughDouble() {
        #expect(PerpsFormatting.usd("12345678901234.12345678").optionalAmount != nil)
        #expect(PerpsFormatting.usd(nil).optionalAmount == nil)
        #expect(PerpsFormatting.usd("invalid").optionalAmount == nil)
        #expect(PerpsFormatting.usd("-0.125").amount < 0)
    }

    @Test func refreshPreservesSDKExecutionOrderWithinOneTimestampAndDeduplicatesFirstRecord() async throws {
        func fill(_ id: Int64, price: String) throws -> ApiPerpsFill {
            try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
            {"activityId":"\(id)","coin":"BTC","oid":42,"time":1786454400000,"px":"\(price)","sz":"0.1","fee":"0","feeToken":"USDC",
             "eventKind":"opened","positionSide":"long"}
            """.utf8))
        }
        let history = [try fill(30, price: "103"), try fill(10, price: "101"), try fill(20, price: "102"), try fill(10, price: "999")]
        var client = client()
        client.history = { _ in .init(fills: history) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        #expect(store.fills["a"]?.map(\.id) == ["30", "10", "20"])
        #expect(store.fills["a"]?.map(\.px) == ["103", "101", "102"])
    }

    @Test(arguments: [false, true])
    func operationRefreshWaitsForOldReadThenFetchesPostOperationSnapshot(retryingWithdrawal: Bool) async throws {
        var client = client()
        var snapshotReads = 0
        var oldRead: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
        client.positions = { _ in
            snapshotReads += 1
            if snapshotReads == 1 {
                return try await withCheckedThrowingContinuation { oldRead = $0 }
            }
            return .init(positions: [], totalEquity: "200", totalPnl: "0", timestamp: 2, unavailableDexs: [])
        }
        var initial = ApiPerpsOperation(id: "withdrawal", accountId: "a", assetId: "hyperliquid:hl:BTC", kind: "close", createdAt: 0)
        initial.state = "partial"
        var didExecute = false
        client.execute = { account, _, _, id in
            didExecute = true
            var result = ApiPerpsOperation(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
            result.state = "completed"
            return result
        }
        client.retryWithdrawal = { _, _, _ in
            didExecute = true
            var result = initial
            result.state = "completed"
            return result
        }
        let store = PerpsStore(client: client, load: { retryingWithdrawal ? [initial] : [] }, save: { _ in })
        let priorRefresh = Task { await store.refresh(accountId: "a") }
        while oldRead == nil { await Task.yield() }
        let quote = try quote()
        let execution = Task {
            if retryingWithdrawal {
                return try await store.retryWithdrawal(operation: initial, enclaveToken: "test")
            }
            return try await store.execute(quote: quote, enclaveToken: "test")
        }
        while !didExecute { await Task.yield() }
        oldRead?.resume(returning: .init(positions: [], totalEquity: "100", totalPnl: "0", timestamp: 1, unavailableDexs: []))
        await priorRefresh.value
        #expect(try await execution.value.state == "completed")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while store.snapshots["a"]?.timestamp != 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(snapshotReads == 2)
        #expect(store.snapshots["a"]?.totalEquity == "200")
        #expect(store.snapshots["a"]?.timestamp == 2)
    }

    @Test func forcedRefreshAfterPendingReadStillHonorsAccountDeletion() async {
        var client = client()
        var reads = 0
        var continuation: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
        client.positions = { _ in
            reads += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        let oldRead = Task { await store.refresh(accountId: "a") }
        while continuation == nil { await Task.yield() }
        var forcedStarted = false
        let forced = Task { forcedStarted = true; await store.refresh(accountId: "a", force: true) }
        while !forcedStarted { await Task.yield() }
        store.removeAccount("a")
        continuation?.resume(returning: .init(positions: [], totalEquity: "100", totalPnl: "0", timestamp: 0, unavailableDexs: []))
        await oldRead.value
        await forced.value
        #expect(reads == 1)
        #expect(store.snapshots["a"] == nil)
        #expect(!store.loading.contains("a"))
    }

    @Test(arguments: [false, true])
    func staleReconciliationCannotOverwriteWithdrawalRetry(reconcileAfterCompletion: Bool) async throws {
        var client = client()
        var initial = ApiPerpsOperation(id: "withdrawal", accountId: "a", assetId: "BTC", kind: "close", createdAt: 0)
        initial.state = "partial"
        var reconciliationResponse: CheckedContinuation<ApiPerpsOperation, Error>?
        var withdrawalResponse: CheckedContinuation<ApiPerpsOperation, Error>?
        client.reconcile = { _, _ in try await withCheckedThrowingContinuation { reconciliationResponse = $0 } }
        client.retryWithdrawal = { _, _, _ in try await withCheckedThrowingContinuation { withdrawalResponse = $0 } }
        let store = PerpsStore(client: client, load: { [initial] }, save: { _ in })
        let reconciliation = Task { await store.reconcile(accountId: "a") }
        while reconciliationResponse == nil { await Task.yield() }
        let withdrawal = Task { try await store.retryWithdrawal(operation: initial, enclaveToken: "test") }
        while withdrawalResponse == nil { await Task.yield() }
        var completed = initial
        completed.state = "completed"
        if reconcileAfterCompletion {
            withdrawalResponse?.resume(returning: completed)
            _ = try await withdrawal.value
        }
        reconciliationResponse?.resume(returning: initial)
        await reconciliation.value
        #expect(store.operations[initial.id]?.state == (reconcileAfterCompletion ? "completed" : "running"))
        if !reconcileAfterCompletion {
            withdrawalResponse?.resume(returning: completed)
            _ = try await withdrawal.value
        }
        #expect(store.operations[initial.id]?.state == "completed")
        #expect(store.pendingOperation(accountId: "a") == nil)
    }
}

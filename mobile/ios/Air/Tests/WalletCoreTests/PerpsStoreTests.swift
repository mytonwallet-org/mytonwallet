import Foundation
import Testing
import WalletContext
@testable import WalletCore

@Suite @MainActor
struct PerpsStoreTests {
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
        client.history = { _ in .init(fills: [fill], cashFlows: [], nextCursor: "page2") }
        var pages = 0
        client.historyPage = { account, cursor in
            #expect(account == "a")
            #expect(cursor == "page2")
            pages += 1
            return .init(fills: [fill, older], cashFlows: [])
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
        client.history = { _ in .init(fills: [], cashFlows: [], nextCursor: "page2") }
        var response: CheckedContinuation<ApiPerpsActivityHistory, Never>?
        client.historyPage = { _, _ in await withCheckedContinuation { response = $0 } }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        let task = Task { await store.loadMoreHistory(accountId: "a") }
        while response == nil { await Task.yield() }
        store.removeAccount("a")
        response?.resume(returning: .init(fills: [], cashFlows: [], nextCursor: "page3"))
        await task.value
        #expect(store.fills["a"] == nil)
        #expect(store.historyCursors["a"] == nil)
    }

    @Test func cashFlowsAreAccountScopedAndFailedRefreshPreservesHistory() async throws {
        let flow = try JSONDecoder().decode(ApiPerpsCashFlow.self, from: Data("""
        {"id":"deposit/1","kind":"deposit","direction":"incoming","time":1,"amount":"10.1","token":"USDC","fees":[]}
        """.utf8))
        var client = client()
        var fail = false
        client.snapshot = { _ in .init(assets: [], positions: [], totalEquity: "0", totalPnl: "0", timestamp: 1, unavailableDexs: []) }
        client.history = { account in
            if fail { throw PerpsError.invalidResponse }
            return .init(fills: [], cashFlows: account == "a" ? [flow, flow] : [])
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        await store.refresh(accountId: "b")
        #expect(store.cashFlows["a"] == [flow])
        #expect(store.cashFlows["b"] == [])
        fail = true
        await store.refresh(accountId: "a")
        #expect(store.cashFlows["a"] == [flow])
        store.removeAccount("a")
        #expect(store.cashFlows["a"] == nil)
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
        #expect(PerpsFormatting.errorMessage("InsufficientBalance") == ApiAnyDisplayError.insufficientBalance.toLocalized)
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
        "startPosition":"0","closedPnl":"0","fee":"0.2","feeToken":"USDC","eventKind":"opened","positionSize":"0.01"}
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
        client.snapshot = { _ in .init(assets: [asset], positions: [position], totalEquity: "100", totalPnl: "0", timestamp: 2, unavailableDexs: []) }
        client.history = { _ in .init(fills: [fill], cashFlows: []) }
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
        client.snapshot = { _ in .init(assets: [], positions: [], totalEquity: "0", totalPnl: "0", timestamp: 0, unavailableDexs: []) }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        client.operation = { _, _ in nil }
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
        store.receiveOperationUpdate(other)
        other = update; other.assetId = "another-asset"
        store.receiveOperationUpdate(other)
        other = update; other.kind = "another-kind"
        store.receiveOperationUpdate(other)
        store.receiveOperationUpdate(try #require(pending))
        await Task.yield()
        #expect(!returned)
        // Exercise the same event path as the bridge, before the SDK call resolves.
        store.walletCore(event: .perpsOperationUpdated(.init(operation: update)))
        update.reviewedQuote = review
        #expect(try await confirmation.value == update)
        #expect(persisted.first == update)
        #expect(store.pendingOperation(accountId: "a")?.id == update.id)
        await #expect(throws: PerpsError.self) { try await store.execute(quote: review, enclaveToken: "test") }
        // An older poll must not move the operation back into preparation.
        store.receiveOperationUpdate(try #require(pending))
        #expect(store.operations[update.id]?.stage == update.stage)
        update.state = "failed"
        update.stage = "finished"
        update.error = "PerpsOrderTooSmall"
        store.receiveOperationUpdate(update)
        #expect(store.pendingOperation(accountId: "a") == nil)
        continuation?.resume(returning: update)
        #expect(store.operations[update.id] == update)
        #expect(persisted.first?.error == "PerpsOrderTooSmall")
    }

    @Test func completionDoesNotWaitForBalanceRefresh() async throws {
        var client = client()
        var refresh: CheckedContinuation<ApiPerpsSnapshot, Error>?
        client.snapshot = { _ in try await withCheckedThrowingContinuation { refresh = $0 } }
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
        store.receiveOperationUpdate(operation)
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
        var continuation: CheckedContinuation<ApiPerpsSnapshot, Error>?
        client.snapshot = { _ in
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
        continuation?.resume(returning: .init(assets: [], positions: [], totalEquity: "100", totalPnl: "5", timestamp: 0, unavailableDexs: []))
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
            {"coin":"BTC","tid":\(id),"oid":42,"time":1786454400000,"px":"\(price)","sz":"0.1","side":"B",
             "dir":"Open Long","startPosition":"0","closedPnl":"0","fee":"0","feeToken":"USDC"}
            """.utf8))
        }
        let history = [try fill(30, price: "103"), try fill(10, price: "101"), try fill(20, price: "102"), try fill(10, price: "999")]
        var client = client()
        client.history = { _ in .init(fills: history, cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        #expect(store.fills["a"]?.map(\.tid) == [30, 10, 20])
        #expect(store.fills["a"]?.map(\.px) == ["103", "101", "102"])
    }

    @Test(arguments: [false, true])
    func operationRefreshWaitsForOldReadThenFetchesPostOperationSnapshot(retryingWithdrawal: Bool) async throws {
        var client = client()
        var snapshotReads = 0
        var oldRead: CheckedContinuation<ApiPerpsSnapshot, Error>?
        client.snapshot = { _ in
            snapshotReads += 1
            if snapshotReads == 1 {
                return try await withCheckedThrowingContinuation { oldRead = $0 }
            }
            return .init(assets: [], positions: [], totalEquity: "200", totalPnl: "0", timestamp: 2, unavailableDexs: [])
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
        oldRead?.resume(returning: .init(assets: [], positions: [], totalEquity: "100", totalPnl: "0", timestamp: 1, unavailableDexs: []))
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
        var continuation: CheckedContinuation<ApiPerpsSnapshot, Error>?
        client.snapshot = { _ in
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
        continuation?.resume(returning: .init(assets: [], positions: [], totalEquity: "100", totalPnl: "0", timestamp: 0, unavailableDexs: []))
        await oldRead.value
        await forced.value
        #expect(reads == 1)
        #expect(store.snapshots["a"] == nil)
        #expect(!store.loading.contains("a"))
    }

    @Test func lateProgressResponseCannotOverwriteCompletedOperationWhileRefreshing() async throws {
        var client = client()
        var executeResponse: CheckedContinuation<ApiPerpsOperation, Error>?
        var progressResponse: CheckedContinuation<ApiPerpsOperation?, Error>?
        var snapshotResponse: CheckedContinuation<ApiPerpsSnapshot, Error>?
        var initial: ApiPerpsOperation?
        client.execute = { account, _, _, id in
            initial = .init(id: id, accountId: account, assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
            return try await withCheckedThrowingContinuation { executeResponse = $0 }
        }
        client.operation = { _, _ in try await withCheckedThrowingContinuation { progressResponse = $0 } }
        client.snapshot = { _ in try await withCheckedThrowingContinuation { snapshotResponse = $0 } }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        let quote = try quote()
        let task = Task { try await store.execute(quote: quote, enclaveToken: "test") }
        while progressResponse == nil { await Task.yield() }
        let running = try #require(initial)
        var completed = running
        completed.state = "completed"
        executeResponse?.resume(returning: completed)
        while snapshotResponse == nil { await Task.yield() }
        progressResponse?.resume(returning: running)
        // Let the in-flight progress response reach the cancellation check before releasing the refresh.
        for _ in 0..<10 { await Task.yield() }
        #expect(store.operations[running.id]?.state == "completed")
        #expect(store.pendingOperation(accountId: "a") == nil)
        snapshotResponse?.resume(returning: .init(assets: [], positions: [], totalEquity: "0", totalPnl: "0", timestamp: 0, unavailableDexs: []))
        #expect(try await task.value.state == "completed")
        #expect(store.operations[running.id]?.state == "completed")
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

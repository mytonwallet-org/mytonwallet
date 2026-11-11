import Testing
import UIKit
import UIComponents
import WalletContext
import WalletCore
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsOperationPresentationTests {
    @Test func interruptedOrderExplainsUncertaintyAndRequiresExplicitRecoveryConfirmation() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let operation = ApiPerpsOperation(id: "interrupted-ui", accountId: "account", assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 1793089091825)
        var acknowledgements = 0
        var client = PerpsClient()
        client.reconcile = { _, saved in saved }
        client.marketSnapshot = { try self.market() }
        client.positions = { _ in try self.snapshot() }
        client.history = { _ in .init(fills: []) }
        client.acknowledge = { _, saved in
            acknowledgements += 1
            var updated = saved
            updated.acknowledgedAt = 100
            return updated
        }
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in }, loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id, onWithdraw: {}, onReceipt: {})
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.setViewControllers([root, controller], animated: false)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        let message = try #require(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "perps.operation.message" })
        #expect(message.text == lang("PerpsExecutionUnknown"))
        #expect(!message.isHidden)
        #expect(message.bounds.height > 0)
        let recover = try #require(descendants(controller.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
        #expect(recover.title(for: .normal) == lang("PerpsAllowNewOrders"))
        let actions = controller.acknowledgementActions()
        #expect(actions.map(\.title) == [lang("Cancel"), lang("PerpsAllowNewOrders")])
        #expect(acknowledgements == 0)
        actions[0].handler()
        #expect(acknowledgements == 0)
        #expect(store.pendingOperation(accountId: "account")?.id == operation.id)
        actions[1].handler()
        for _ in 0..<100 where store.pendingOperation(accountId: "account") != nil { await Task.yield() }
        #expect(acknowledgements == 1)
        #expect(store.pendingOperation(accountId: "account") == nil)
        #expect(store.operations[operation.id]?.state == "unknown")
        #expect(navigation.viewControllers.count == 1)
    }

    private func withdrawalQuote() throws -> ApiPerpsBalanceWithdrawalQuote {
        try JSONDecoder().decode(ApiPerpsBalanceWithdrawalQuote.self, from: Data("""
        {"id":"quote","accountId":"account","destination":"0xwallet","balance":"1.5","amount":"1.47",
         "bridgeFee":"0.2","receiveAmount":"1.27","expiresAt":\(Int64(Date.now.timeIntervalSince1970 * 1000) + 60_000)}
        """.utf8))
    }

    private func expectWithdrawalStatus(store: PerpsStore, operationId: String, title: String, message: String, action: String) throws {
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operationId, onWithdraw: {}, onReceipt: {})
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        let labels = descendants(controller.view).compactMap { $0 as? UILabel }
        #expect(controller.title == lang("PerpsWithdrawalStatus"))
        #expect(labels.first { $0.accessibilityIdentifier == "perps.operation.status" }?.text == lang(title))
        #expect(labels.first { $0.accessibilityIdentifier == "perps.operation.message" }?.text == lang(message))
        let button = try #require(descendants(controller.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
        #expect(button.title(for: .normal) == lang(action))
    }

    @Test(arguments: [
        ("completed", "PerpsWithdrawalCompleted", "PerpsWithdrawalOnItsWay", "Close"),
        ("unknown", "PerpsWithdrawalStatus", "PerpsWithdrawalUnknown", "PerpsAllowNewOrders"),
        ("failed", "PerpsWithdrawalStatus", "PerpsWithdrawalRejected", "Close"),
    ])
    func settledWithdrawalSpeaksAboutTheWithdrawal(state: String, title: String, message: String, action: String) throws {
        _ = WalletResourcesBundle.bundle.load()
        var withdrawal = ApiPerpsOperation(id: "withdrawal-\(state)", accountId: "account", assetId: "USDC", kind: "withdraw", createdAt: 0)
        withdrawal.balanceWithdrawal = try withdrawalQuote()
        withdrawal.state = state
        if state == "failed" { withdrawal.error = "PerpsWithdrawalRejected: [HL_EXCHANGE_ERROR] nope" }
        let store = PerpsStore(client: PerpsClient(), load: { [withdrawal] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        try expectWithdrawalStatus(store: store, operationId: withdrawal.id, title: title, message: message, action: action)
    }

    @Test func runningWithdrawalSpeaksAboutTheWithdrawal() async throws {
        _ = WalletResourcesBundle.bundle.load()
        var client = PerpsClient()
        var response: CheckedContinuation<ApiPerpsOperation, Error>?
        client.executeBalanceWithdrawal = { _, _, _, _ in try await withCheckedThrowingContinuation { response = $0 } }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        let quote = try withdrawalQuote()
        let submission = Task { try await store.executeBalanceWithdrawal(quote: quote, enclaveToken: "test") }
        while response == nil { await Task.yield() }
        var operation = try #require(store.operations.values.first)
        try expectWithdrawalStatus(store: store, operationId: operation.id,
                                   title: "PerpsWithdrawalStatus", message: "PerpsWithdrawalProcessing", action: "Hide")
        operation.state = "failed"
        operation.stage = "finished"
        response?.resume(returning: operation)
        _ = try await submission.value
    }

    private func operation() -> ApiPerpsOperation {
        var operation = ApiPerpsOperation(id: "operation", accountId: "account", assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
        operation.state = "completed"
        operation.orderId = 42
        return operation
    }

    private func market() throws -> ApiPerpsMarketSnapshot {
        try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}],"assetsFetchedAt":0}
        """.utf8))
    }

    private func snapshot() throws -> ApiPerpsAccountSnapshot {
        try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]}
        """.utf8))
    }

    private func fill(coin: String = "BTC", orderId: Int64 = 42, kind: ApiPerpsFillEvent = .opened) throws -> ApiPerpsFill {
        try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"\(coin)","oid":\(orderId),"time":1786454400000,"px":"100","sz":"0.1",
         "fee":"0","feeToken":"USDC","eventKind":"\(kind.rawValue)","positionSide":"long"}
        """.utf8))
    }

    @Test func completedOperationOffersOnlyTheReceiptOfItsOwnFill() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let snapshot = try snapshot()
        let market = try market()
        var fills: [ApiPerpsFill] = []
        var client = PerpsClient()
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: fills) }
        let operation = operation()
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        await store.refresh(accountId: "account")
        var receiptOpened = false
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id,
            onWithdraw: {}, onReceipt: { receiptOpened = true })
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        let status = try #require(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "perps.operation.status" })
        #expect(status.textColor == .air.positiveAmount)
        let action = try #require(descendants(controller.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
        #expect(action.title(for: .normal) == lang("Close"))
        controller.viewWillDisappear(false)

        for unrelated in [try fill(orderId: 99), try fill(coin: "ETH")] {
            fills = [unrelated]
            await store.refresh(accountId: "account")
            controller.viewDidAppear(false)
            #expect(action.title(for: .normal) == lang("Close"))
            controller.viewWillDisappear(false)
        }
        fills = [try fill()]
        await store.refresh(accountId: "account")
        controller.viewDidAppear(false)
        #expect(action.title(for: .normal) == lang("Details"))
        action.sendActions(for: .touchUpInside)
        #expect(receiptOpened)
        controller.viewWillDisappear(false)
    }

    @Test func completedPartialFillKeepsWarningAndOffersReceipt() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let snapshot = try snapshot()
        let market = try market()
        let fill = try fill()
        var client = PerpsClient()
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: [fill]) }
        var operation = operation()
        operation.error = "PerpsPartialFill"
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        await store.refresh(accountId: "account")
        var receiptOpened = false
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id,
            onWithdraw: {}, onReceipt: { receiptOpened = true })
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        let message = try #require(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "perps.operation.message" })
        #expect(message.text == lang("PerpsPartialFill"))
        let details = try #require(descendants(controller.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
        #expect(details.title(for: .normal) == lang("Details"))
        details.sendActions(for: .touchUpInside)
        #expect(receiptOpened)
        controller.viewWillDisappear(false)
    }

    @Test func completedCloseWithARejectedWithdrawalSaysTheMoneyStayedOnTheBalance() throws {
        _ = WalletResourcesBundle.bundle.load()
        var operation = operation()
        operation.state = "completed"
        operation.error = "PerpsWithdrawalRejected: [HL_EXCHANGE_ERROR] Insufficient USDC or HYPE balance"
        let store = PerpsStore(load: { [operation] }, save: { _ in })
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id, onWithdraw: {}, onReceipt: {})
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        let message = try #require(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "perps.operation.message" })
        #expect(message.text == lang("PerpsWithdrawalRejected"))
        controller.viewWillDisappear(false)
    }

    @Test func closePopsAPushedStatusAndScrollingUsesTheWholeViewport() throws {
        _ = WalletResourcesBundle.bundle.load()
        let operation = operation()
        let store = PerpsStore(load: { [operation] }, save: { _ in })
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id, onWithdraw: {}, onReceipt: {})
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.setViewControllers([root, controller], animated: false)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        let layout = try #require(controller.view.subviews.compactMap { $0 as? AssetDetailsView }.first)
        #expect(layout.frame == controller.view.bounds)
        #expect(layout.scrollView.frame == layout.bounds)
        #expect(!layout.scrollView.delaysContentTouches)
        let close = try #require(descendants(controller.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
        #expect(close.title(for: .normal) == lang("Close"))
        close.sendActions(for: .touchUpInside)
        #expect(navigation.viewControllers.count == 1)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

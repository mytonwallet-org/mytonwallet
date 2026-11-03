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
        client.snapshot = { _ in try self.snapshot() }
        client.history = { _ in .init(fills: [], cashFlows: []) }
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

    private func operation() -> ApiPerpsOperation {
        var operation = ApiPerpsOperation(id: "operation", accountId: "account", assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
        operation.state = "completed"
        operation.orderId = 42
        return operation
    }

    private func snapshot() throws -> ApiPerpsSnapshot {
        try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}],
         "positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]}
        """.utf8))
    }

    private func fill(coin: String = "BTC", orderId: Int64 = 42, kind: String? = "opened") throws -> ApiPerpsFill {
        var fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"\(coin)","tid":123,"oid":\(orderId),"time":1786454400000,"px":"100","sz":"0.1","side":"B",
         "dir":"Open Long","startPosition":"0","closedPnl":"0","fee":"0","feeToken":"USDC"}
        """.utf8))
        fill.eventKind = kind
        return fill
    }

    @Test func completionWaitsForMatchingFillAndVisibleScreenThenRoutesOnce() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let snapshot = try snapshot()
        var fills: [ApiPerpsFill] = []
        var client = PerpsClient()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: fills, cashFlows: []) }
        let operation = operation()
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        await store.refresh(accountId: "account")
        var completed: [String] = []
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id,
            onWithdraw: {}, onReceipt: {}, onCompleted: { completed.append($0.id) })
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        #expect(completed.isEmpty)
        let status = try #require(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "perps.operation.status" })
        #expect(status.textColor == .air.positiveAmount)
        controller.viewWillDisappear(false)

        for unrelated in [try fill(orderId: 99), try fill(coin: "ETH"), try fill(kind: nil)] {
            fills = [unrelated]
            await store.refresh(accountId: "account")
            controller.viewDidAppear(false)
            #expect(completed.isEmpty)
            controller.viewWillDisappear(false)
        }
        fills = [try fill()]
        await store.refresh(accountId: "account")
        #expect(completed.isEmpty)
        controller.viewDidAppear(false)
        #expect(completed == [operation.id])
        controller.viewWillDisappear(false)
        controller.viewDidAppear(false)
        #expect(completed == [operation.id])
        controller.viewWillDisappear(false)
    }

    @Test func completedPartialFillKeepsWarningAndOffersReceiptWithoutAutoRouting() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let snapshot = try snapshot()
        let fill = try fill()
        var client = PerpsClient()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [fill], cashFlows: []) }
        var operation = operation()
        operation.error = "PerpsPartialFill"
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in })
        await store.refresh(accountId: "account")
        var completed = false
        var receiptOpened = false
        let controller = PerpsOperationVC(store: store, accountId: "account", operationId: operation.id,
            onWithdraw: {}, onReceipt: { receiptOpened = true }, onCompleted: { _ in completed = true })
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        #expect(!completed)
        let message = try #require(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "perps.operation.message" })
        #expect(message.text == lang("PerpsPartialFill"))
        let details = try #require(descendants(controller.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
        #expect(details.title(for: .normal) == lang("Details"))
        details.sendActions(for: .touchUpInside)
        #expect(receiptOpened)
        #expect(!completed)
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

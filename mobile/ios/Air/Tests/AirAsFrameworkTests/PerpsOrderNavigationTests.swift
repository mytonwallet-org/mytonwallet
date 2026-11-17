import Dependencies
import GRDB
import SwiftUI
import UIKit
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import UIToken
@testable import AirAsFramework
import XCTest

@MainActor
final class PerpsOrderNavigationTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    func testReceiptInfoReturnsToTheSameReceiptWithoutStackingSheets() async throws {
        try await runWithOrder { coordinator, origin, _, fill in
            coordinator.showFill(fill.id, from: origin)
            let navigation = try XCTUnwrap(origin.presentation as? UINavigationController)
            let receipt = try XCTUnwrap(navigation.topViewController as? PerpsPositionReceiptVC)
            navigation.loadViewIfNeeded()

            for _ in 0..<3 {
                try tapReceiptInfo(receipt)
                try tapReceiptInfo(receipt)
                await Task.yield()
                let status = try XCTUnwrap(navigation.topViewController as? PerpsOperationVC)
                XCTAssertEqual(navigation.viewControllers.count, 2)
                XCTAssertNil(navigation.presentedViewController)
                try tapStatusAction(status)
                await Task.yield()
                XCTAssertTrue(navigation.topViewController === receipt)
                XCTAssertEqual(navigation.viewControllers.count, 1)
            }

            try tapReceiptInfo(receipt)
            navigation.popViewController(animated: false)
            XCTAssertTrue(navigation.topViewController === receipt)
        }
    }

    func testStatusInfoReturnsToTheSameStatusAndBackKeepsOneSheet() async throws {
        try await runWithOrder { coordinator, origin, operation, _ in
            coordinator.showOperation(operation, from: origin)
            let navigation = try XCTUnwrap(origin.presentation as? UINavigationController)
            let status = try XCTUnwrap(navigation.topViewController as? PerpsOperationVC)
            navigation.loadViewIfNeeded()

            for _ in 0..<3 {
                try tapStatusAction(status)
                try tapStatusAction(status)
                await Task.yield()
                let receipt = try XCTUnwrap(navigation.topViewController as? PerpsPositionReceiptVC)
                receipt.loadViewIfNeeded()
                XCTAssertEqual(navigation.viewControllers.count, 2)
                XCTAssertNil(navigation.presentedViewController)
                XCTAssertFalse(receipt.navigationItem.hidesBackButton)
                try tapReceiptInfo(receipt)
                await Task.yield()
                XCTAssertTrue(navigation.topViewController === status)
                XCTAssertEqual(navigation.viewControllers.count, 1)
            }

            try tapStatusAction(status)
            navigation.popViewController(animated: false)
            XCTAssertTrue(navigation.topViewController === status)
        }
    }

    func testCompletedReceiptInfoExpandsDetailsWithoutOpeningStatus() async throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Receipt sheet trait overrides require iOS 17") }
        try await runWithOrder(hasNoWarning: true) { coordinator, origin, operation, _ in
            coordinator.showOperation(operation, from: origin)
            let navigation = try XCTUnwrap(origin.presentation as? UINavigationController)
            let status = try XCTUnwrap(navigation.topViewController as? PerpsOperationVC)
            navigation.loadViewIfNeeded()
            status.traitOverrides.horizontalSizeClass = .compact
            status.traitOverrides.verticalSizeClass = .regular
            try tapStatusAction(status)
            let receipt = try XCTUnwrap(navigation.topViewController as? PerpsPositionReceiptVC)
            receipt.prepareForPresentation(from: origin)
            receipt.loadViewIfNeeded()
            receipt.beginAppearanceTransition(true, animated: false)
            receipt.endAppearanceTransition()
            defer {
                receipt.beginAppearanceTransition(false, animated: false)
                receipt.endAppearanceTransition()
            }
            let sheet = try XCTUnwrap(navigation.sheetPresentationController)
            let content = try XCTUnwrap(receipt.children.compactMap { $0 as? UIHostingController<PerpsPositionReceiptView> }.first)
            XCTAssertFalse(content.rootView.presentation.detailsExpanded)
            XCTAssertEqual(sheet.selectedDetentIdentifier, .init("perpsReceipt"))
            XCTAssertTrue(sheet.prefersGrabberVisible)
            try tapReceiptInfo(receipt)
            await Task.yield()
            XCTAssertTrue(content.rootView.presentation.detailsExpanded)
            XCTAssertEqual(sheet.selectedDetentIdentifier, .large)
            XCTAssertFalse(sheet.prefersGrabberVisible)
            for _ in 0..<3 {
                let isInitiallyExpanded = content.rootView.presentation.detailsExpanded
                try tapReceiptInfo(receipt)
                await Task.yield()
                XCTAssertNotEqual(content.rootView.presentation.detailsExpanded, isInitiallyExpanded)
                XCTAssertTrue(navigation.topViewController === receipt)
                XCTAssertEqual(navigation.viewControllers.count, 2)
                XCTAssertNil(navigation.presentedViewController)
            }
        }
    }

    func testRecoveryActionsStayAvailableFromTheReceipt() async throws {
        for (state, actionTitle) in [("unknown", "PerpsAllowNewOrders"), ("partial", "PerpsWithdrawReleased"), ("failed", "Close")] {
            try await runWithOrder(state: state, hasNoFill: state == "failed") { coordinator, origin, operation, fill in
                let activityId = state == "failed"
                    ? PerpsTradeActivity(failedOrder: operation, asset: coordinator.store.asset(id: operation.assetId)!).id : fill.id
                coordinator.showFill(activityId, from: origin)
                let navigation = try XCTUnwrap(origin.presentation as? UINavigationController)
                let receipt = try XCTUnwrap(navigation.topViewController as? PerpsPositionReceiptVC)
                navigation.loadViewIfNeeded()
                try tapReceiptInfo(receipt)
                await Task.yield()
                let status = try XCTUnwrap(navigation.topViewController as? PerpsOperationVC)
                XCTAssertEqual(try findStatusAction(status).title(for: .normal), lang(actionTitle))
                XCTAssertEqual(navigation.viewControllers.count, 2)
                XCTAssertNil(navigation.presentedViewController)
            }
        }
    }

    private func tapReceiptInfo(_ receipt: PerpsPositionReceiptVC) throws {
        receipt.loadViewIfNeeded()
        let content = try XCTUnwrap(receipt.children.compactMap { $0 as? UIHostingController<PerpsPositionReceiptView> }.first)
        content.rootView.onDetails()
    }

    private func tapStatusAction(_ status: PerpsOperationVC) throws {
        try findStatusAction(status).sendActions(for: .touchUpInside)
    }

    private func findStatusAction(_ status: PerpsOperationVC) throws -> WButton {
        status.loadViewIfNeeded()
        return try XCTUnwrap(findDescendants(status.view).compactMap { $0 as? WButton }
            .first { $0.accessibilityIdentifier == "perps.operation.action" })
    }

    private func findDescendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(findDescendants)
    }

    private final class PresentationRecorder: UIViewController {
        var presentation: UIViewController?

        override func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
            presentation = viewControllerToPresent
            completion?()
        }
    }

    private func runWithOrder(state: String = "completed", hasNoFill: Bool = false, hasNoWarning: Bool = false,
                           _ body: (PerpsCoordinator, PresentationRecorder, ApiPerpsOperation, ApiPerpsFill) async throws -> Void) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        SettingsStore.liveValue.use(db: database)
        defer { SettingsStore.liveValue.clean() }
        let account = MAccount(id: "navigation-mainnet", title: "Synthetic order", type: .view,
                               byChain: [.ton: .init(address: "synthetic")])
        try await database.write { try account.insert($0) }
        let accounts = _AccountStore(db: database)
        _ = try await accounts.accountForActivation(accountId: account.id)
        let market = try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:xyz:NVDA","name":"xyz:NVDA","symbol":"NVDA","chain":"hyperliquid",
         "provider":"hyperliquid","dex":"xyz","szDecimals":3,"maxLeverage":10,
         "context":{"markPx":"160.81","prevDayPx":"160"}}],"assetsFetchedAt":0}
        """.utf8))
        let snapshot = try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]}
        """.utf8))
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"xyz:NVDA","oid":42,"time":1794441840000,"px":"160.81","sz":"31.078",
         "fee":"1","feeToken":"USDC","eventKind":"opened","positionSide":"long","leverage":10,"collateralAfter":"495.19"}
        """.utf8))
        var operation = ApiPerpsOperation(id: "navigation", accountId: account.id, assetId: market.assets[0].id,
                                          kind: "open", createdAt: 1794441780000)
        operation.state = state
        operation.stage = "finished"
        operation.orderId = hasNoFill ? nil : 42
        operation.error = state == "completed" && !hasNoWarning ? "PerpsPartialFill" : nil
        operation.filledSize = "31.078"
        operation.averagePrice = "160.81"
        operation.reviewedQuote = try JSONDecoder().decode(ApiPerpsQuote.self, from: Data("""
        {"id":"quote","accountId":"navigation-mainnet","assetId":"hyperliquid:xyz:NVDA","kind":"open","side":"long",
         "leverage":10,"inputAmount":"500","collateral":"500","size":"31.1","notional":"5000","markPrice":"160.81",
         "paymentAmount":"500","bridgeFee":"0","expiresAt":0,"createdAt":1794441780000}
        """.utf8))
        var client = PerpsClient()
        client.supported = { true }
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: hasNoFill ? [] : [fill]) }
        client.reconcile = { _, saved in saved }
        client.candles = { _, _ in [] }
        let store = PerpsStore(client: client, load: { [operation] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await store.refresh(accountId: account.id)
        try await withDependencies {
            $0.accountStore = accounts
        } operation: {
            let coordinator = PerpsCoordinator(accountId: account.id, store: store)
            let origin = PresentationRecorder()
            if #available(iOS 17, *) {
                origin.traitOverrides.horizontalSizeClass = .compact
                origin.traitOverrides.verticalSizeClass = .regular
            }
            try await body(coordinator, origin, operation, fill)
        }
    }
}

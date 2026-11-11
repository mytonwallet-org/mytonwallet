import Dependencies
import GRDB
import SwiftUI
import UIKit
import XCTest
import UIComponents
@testable import UIToken
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

/// Confirming an expired quote prepares the reviewed draft again. The refreshed quote replaces the review only
/// when it trades the same position with the same operation.
@MainActor
final class PerpsReviewRefreshTests: XCTestCase {
    private static let accountId = "wallet"
    private static let assetId = "hyperliquid:hl:BTC"

    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    override func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
        MainActor.assumeIsolated { UIView.setAnimationsEnabled(false) }
    }

    override func tearDown() {
        MainActor.assumeIsolated { UIView.setAnimationsEnabled(true) }
        super.tearDown()
    }

    func testRefreshForTheReviewedPositionAndOperationReplacesTheQuote() async throws {
        let state = try await confirmExpiredClose(refreshedKind: "close", refreshedAccountId: Self.accountId)
        XCTAssertEqual(state.data.status, .ready)
        XCTAssertEqual(state.data.notice, lang("PerpsReviewUpdated"))
        XCTAssertTrue(state.canConfirm)
    }

    func testRefreshForAnotherOperationKeepsTheReviewedQuote() async throws {
        let state = try await confirmExpiredClose(refreshedKind: "reduce", refreshedAccountId: Self.accountId)
        XCTAssertNil(state.data.notice)
        XCTAssertEqual(state.data.mode.operation, .close)
        XCTAssertEqual(state.data.status, .unavailable(lang("PerpsPositionChanged")))
        XCTAssertFalse(state.canConfirm)
    }

    func testRefreshForAnotherPositionKeepsTheReviewedQuote() async throws {
        let state = try await confirmExpiredClose(refreshedKind: "close", refreshedAccountId: "other-wallet")
        XCTAssertNil(state.data.notice)
        XCTAssertEqual(state.data.positionID, Self.accountId + "/" + Self.assetId)
        XCTAssertEqual(state.data.status, .unavailable(lang("PerpsPositionChanged")))
        XCTAssertFalse(state.canConfirm)
    }

    /// Opens the close review of a position with an expired quote, confirms it and returns the review state
    /// once the refresh has answered, with the identity of the data the user reviewed.
    private func confirmExpiredClose(refreshedKind: String, refreshedAccountId: String) async throws
        -> PerpsOrderReviewState {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(id: Self.accountId, title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        try await db.write { try account.insert($0) }
        let accounts = _AccountStore(db: db)
        _ = try await accounts.accountForActivation(accountId: account.id)

        let market = try market()
        let snapshot = try snapshot()
        let initial = try quote(kind: "close", accountId: Self.accountId, expiresAt: 0)
        let refreshed = try quote(kind: refreshedKind, accountId: refreshedAccountId, expiresAt: 4_000_000_000_000)
        var prepared = 0
        var client = PerpsClient()
        client.supported = { true }
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: []) }
        client.candles = { _, _ in [] }
        client.assetDetail = { _, _, _ in throw PerpsError.invalidResponse }
        client.prepare = { _, draft in
            prepared += 1
            XCTAssertEqual(draft.close, true)
            return prepared == 1 ? initial : refreshed
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await store.refresh(accountId: Self.accountId)

        return try await withDependencies {
            $0.accountStore = accounts
        } operation: {
            let coordinator = PerpsCoordinator(accountId: Self.accountId, store: store)
            let origin = UIViewController()
            let navigation = UINavigationController(rootViewController: origin)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            coordinator.showPosition("wallet/btc", from: origin)
            let position = try XCTUnwrap(navigation.topViewController as? PerpsPositionVC)
            try await waitUntil(window) { position.viewIfLoaded?.window != nil && navigation.transitionCoordinator == nil }
            let close = try XCTUnwrap(descendants(position.view).compactMap { $0 as? WButton }
                .first { $0.accessibilityIdentifier == "perps.position.close" })
            close.sendActions(for: .touchUpInside)
            try await waitUntil(window) { position.presentedViewController != nil }
            defer { position.dismiss(animated: false) }
            let review = try XCTUnwrap((position.presentedViewController as? UINavigationController)?
                .viewControllers.first as? PerpsOrderReviewVC)
            review.loadViewIfNeeded()
            XCTAssertNil(review.navigationItem.leftBarButtonItem)
            let state = try XCTUnwrap(review.children.compactMap { $0 as? UIHostingController<PerpsOrderReviewView> }
                .first?.rootView.state)
            XCTAssertEqual(state.data.mode.operation, .close)
            XCTAssertEqual(state.data.positionID, Self.accountId + "/" + Self.assetId)
            XCTAssertTrue(state.canConfirm)

            state.confirm()
            try await waitUntil(window) { prepared == 2 && state.pendingRequestID == nil }
            return state
        }
    }

    private func waitUntil(_ window: UIWindow, _ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func market() throws -> ApiPerpsMarketSnapshot {
        try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[{"id":"\(Self.assetId)","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
          "dex":"","szDecimals":4,"maxLeverage":40,"tradingAvailability":{"isAvailable":true},
          "context":{"markPx":"100","prevDayPx":"100"}}],"assetsFetchedAt":0}
        """.utf8))
    }

    private func snapshot() throws -> ApiPerpsAccountSnapshot {
        try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"tradingAvailability":{"isAvailable":true},
         "positions":[{"id":"wallet/btc","assetId":"\(Self.assetId)","dex":"","side":"long","size":"0.5",
           "collateral":"100","equity":"125","returnOnEquity":"0.25","funding":"0.3",
           "raw":{"coin":"BTC","entryPx":"2000","liquidationPx":"1800","leverage":{"type":"isolated","value":10},
             "marginUsed":"125","positionValue":"1000","returnOnEquity":"0.25","szi":"0.5","unrealizedPnl":"25"}}],
         "totalEquity":"125","totalPnl":"25","timestamp":0,"unavailableDexs":[]}
        """.utf8))
    }

    private func quote(kind: String, accountId: String, expiresAt: Int64) throws -> ApiPerpsQuote {
        try JSONDecoder().decode(ApiPerpsQuote.self, from: Data("""
        {"id":"\(kind)-\(accountId)-\(expiresAt)","accountId":"\(accountId)","assetId":"\(Self.assetId)",
         "kind":"\(kind)","side":"long","leverage":10,"inputAmount":"0","collateral":"0","previousCollateral":"100",
         "size":"0","previousSize":"0.5","notional":"0","previousNotional":"1000","markPrice":"2050",
         "entryPrice":"2000","equity":"125","profitLoss":"25","paymentAmount":"0","bridgeFee":"0",
         "expiresAt":\(expiresAt),"createdAt":0}
        """.utf8))
    }
}

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

/// A balance withdrawal is reviewed from a fresh quote. Confirming an expired one prepares it again and never submits.
@MainActor
final class PerpsBalanceWithdrawalFlowTests: XCTestCase {
    private static let accountId = "wallet"

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

    func testTheRowOpensAFreshReviewAndAnExpiredConfirmationPreparesItAgainWithoutSubmitting() async throws {
        var prepared = 0
        var submitted = 0
        var client = try client()
        client.prepareBalanceWithdrawal = { _ in
            prepared += 1
            return prepared == 1
                ? Self.quote(amount: "1.47", receiveAmount: "1.27", expiresAt: 0)
                : Self.quote(amount: "1.17", receiveAmount: "0.97", expiresAt: 4_000_000_000_000)
        }
        client.executeBalanceWithdrawal = { _, _, _, _ in
            submitted += 1
            throw PerpsError.invalidResponse
        }
        try await withCoordinator(client: client) { coordinator, origin, window, _ in
            coordinator.showBalanceWithdrawal(from: origin)
            try await waitUntil(window) { origin.presentedViewController != nil }
            defer { origin.dismiss(animated: false) }
            let review = try XCTUnwrap((origin.presentedViewController as? UINavigationController)?
                .viewControllers.first as? PerpsBalanceWithdrawalReviewVC)
            review.loadViewIfNeeded()
            let state = try XCTUnwrap(review.children
                .compactMap { $0 as? UIHostingController<PerpsBalanceWithdrawalReviewView> }.first?.rootView.state)
            XCTAssertEqual(state.data.receiveAmount.amount, 1_270_000)
            XCTAssertEqual(state.data.amount, PerpsFormatting.quantity("1.47", symbol: "USDC"))
            XCTAssertEqual(state.data.bridgeFee, PerpsFormatting.quantity("0.2", symbol: "USDC"))
            XCTAssertEqual(state.data.destination, formatStartEndAddress("0x1234567890123456789012345678901234567890"))
            XCTAssertTrue(state.canConfirm)

            state.confirm()
            try await waitUntil(window) { prepared == 2 && state.pendingRequestID == nil }
            XCTAssertEqual(state.data.receiveAmount.amount, 970_000)
            XCTAssertEqual(state.data.notice, lang("PerpsBalanceWithdrawalUpdated"))
            XCTAssertTrue(state.canConfirm)
            XCTAssertEqual(submitted, 0)
        }
    }

    /// Confirming replaces the review with the compact receipt, which keeps following the operation.
    func testAWithdrawalEndsInACompactReceiptThatFollowsTheOperation() async throws {
        let quote = Self.quote(amount: "1.47", receiveAmount: "1.27", expiresAt: 4_000_000_000_000)
        var submitted: CheckedContinuation<ApiPerpsOperation, Error>?
        var client = try client()
        client.executeBalanceWithdrawal = { _, _, _, _ in try await withCheckedThrowingContinuation { submitted = $0 } }
        try await withCoordinator(client: client) { coordinator, origin, window, store in
            let submission = Task { try? await store.executeBalanceWithdrawal(quote: quote, enclaveToken: "test") }
            try await waitUntil(window) { submitted != nil }
            let running = try XCTUnwrap(store.pendingOperation(accountId: Self.accountId))
            let replacement = coordinator.balanceWithdrawalReplacement(running)
            let receipt = try XCTUnwrap(replacement.viewController as? PerpsPositionReceiptVC)
            XCTAssertEqual(receipt.data.status, .pending)
            XCTAssertEqual(receipt.data.title, lang("In Progress"))

            let navigation = WNavigationController(rootViewController: receipt)
            navigation.sheetPresentationController?.detents = [.large()]
            origin.present(navigation, animated: false)
            defer { origin.dismiss(animated: false) }
            try await waitUntil(window) { navigation.presentingViewController != nil }
            replacement.animateAlongside()
            let sheet = try XCTUnwrap(navigation.sheetPresentationController)
            XCTAssertEqual(sheet.selectedDetentIdentifier?.rawValue, "perpsReceipt")
            XCTAssertTrue(sheet.prefersGrabberVisible)

            var completed = running
            completed.state = "completed"
            completed.stage = "finished"
            submitted?.resume(returning: completed)
            _ = await submission.value
            try await waitUntil(window) { receipt.data.status == .completed }
            XCTAssertEqual(receipt.data.title, lang("PerpsWithdrawalCompleted"))
        }
    }

    func testAnOperationWithoutItsQuoteFallsBackToTheStatusScreen() async throws {
        let bare = ApiPerpsOperation(id: "withdrawal", accountId: Self.accountId, assetId: "USDC", kind: "withdraw", createdAt: 0)
        var client = try client()
        client.reconcile = { _, saved in saved }
        try await withCoordinator(client: client) { coordinator, _, _, _ in
            XCTAssertTrue(coordinator.balanceWithdrawalReplacement(bare).viewController is PerpsOperationVC)
        }
    }

    func testAPendingOperationOpensItsStatusInsteadOfAReview() async throws {
        var pending = ApiPerpsOperation(id: "pending", accountId: Self.accountId, assetId: "hyperliquid:hl:BTC", kind: "open", createdAt: 0)
        pending.state = "unknown"
        var prepared = 0
        var client = try client()
        client.prepareBalanceWithdrawal = { _ in
            prepared += 1
            return Self.quote(amount: "1.47", receiveAmount: "1.27", expiresAt: 4_000_000_000_000)
        }
        client.reconcile = { _, saved in saved }
        try await withCoordinator(client: client, saved: [pending]) { coordinator, origin, window, _ in
            coordinator.showBalanceWithdrawal(from: origin)
            try await waitUntil(window) { origin.presentedViewController != nil }
            defer { origin.dismiss(animated: false) }
            XCTAssertTrue((origin.presentedViewController as? UINavigationController)?.viewControllers.first is PerpsOperationVC)
            XCTAssertEqual(prepared, 0)
        }
    }

    func testAnAccountThatCannotSignNeverPrepares() async throws {
        var prepared = 0
        var client = try client(canSign: false)
        client.prepareBalanceWithdrawal = { _ in
            prepared += 1
            return Self.quote(amount: "1.47", receiveAmount: "1.27", expiresAt: 4_000_000_000_000)
        }
        try await withCoordinator(client: client) { coordinator, origin, _, _ in
            coordinator.showBalanceWithdrawal(from: origin)
            XCTAssertFalse(coordinator.isPreparingBalanceWithdrawal)
            XCTAssertNil(origin.presentedViewController)
            XCTAssertEqual(prepared, 0)
        }
    }

    func testAPendingOperationThatArrivesWhilePreparingKeepsTheReviewClosed() async throws {
        let quote = Self.quote(amount: "1.47", receiveAmount: "1.27", expiresAt: 4_000_000_000_000)
        var response: CheckedContinuation<ApiPerpsBalanceWithdrawalQuote, Error>?
        var submitted: CheckedContinuation<ApiPerpsOperation, Error>?
        var client = try client()
        client.prepareBalanceWithdrawal = { _ in try await withCheckedThrowingContinuation { response = $0 } }
        client.executeBalanceWithdrawal = { _, _, _, _ in try await withCheckedThrowingContinuation { submitted = $0 } }
        try await withCoordinator(client: client) { coordinator, origin, window, store in
            coordinator.showBalanceWithdrawal(from: origin)
            try await waitUntil(window) { response != nil }
            let submission = Task { try? await store.executeBalanceWithdrawal(quote: quote, enclaveToken: "test") }
            try await waitUntil(window) { submitted != nil }
            XCTAssertTrue(coordinator.isPreparingBalanceWithdrawal)
            response?.resume(returning: quote)
            try await waitUntil(window) { !coordinator.isPreparingBalanceWithdrawal }
            XCTAssertNil(origin.presentedViewController)
            submitted?.resume(throwing: PerpsError.invalidResponse)
            _ = await submission.value
        }
    }

    func testAnAccountWithoutArbitrumIsToldItNeedsAMultichainWallet() async throws {
        try await withCoordinator(client: try client(), chains: [.ton: AccountChain(address: "EQ1234")]) { coordinator, _, _, _ in
            let data = coordinator.homeDisplayData()
            XCTAssertEqual(data.accountNotice, lang("PerpsRequiresMultichainWallet"))
            XCTAssertFalse(data.showsOnboarding)
        }
    }

    func testAViewAccountSeesItsBalanceAndCannotWithdrawIt() async throws {
        var client = try client(canSign: false)
        client.prepareBalanceWithdrawal = { _ in
            Self.quote(amount: "1.47", receiveAmount: "1.27", expiresAt: 4_000_000_000_000)
        }
        try await withCoordinator(client: client, type: .view) { coordinator, origin, _, _ in
            let data = coordinator.homeDisplayData()
            XCTAssertNil(data.accountNotice)
            XCTAssertEqual(data.balanceWithdrawal?.canWithdraw, false)
            coordinator.showBalanceWithdrawal(from: origin)
            // Set synchronously before the request is scheduled, so this needs no waiting
            XCTAssertEqual(coordinator.homeDisplayData().balanceWithdrawal?.isPreparing, false)
        }
    }

    private func withCoordinator(client: PerpsClient, saved: [ApiPerpsOperation] = [], type: AccountType = .mnemonic,
                                 chains: [ApiChain: AccountChain] = [.arbitrum: AccountChain(address: "0x1234567890123456789012345678901234567890")],
                                 _ body: (PerpsCoordinator, UIViewController, UIWindow, PerpsStore) async throws -> Void) async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(id: Self.accountId, title: "Wallet", type: type, byChain: chains)
        try await db.write { try account.insert($0) }
        let accounts = _AccountStore(db: db)
        _ = try await accounts.accountForActivation(accountId: account.id)
        let store = PerpsStore(client: client, load: { saved }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await store.loadCapabilities()
        await store.refresh(accountId: Self.accountId)
        try await withDependencies {
            $0.accountStore = accounts
        } operation: {
            let coordinator = PerpsCoordinator(accountId: Self.accountId, store: store)
            let origin = UIViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = UINavigationController(rootViewController: origin)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await waitUntil(window) { origin.viewIfLoaded?.window != nil }
            try await body(coordinator, origin, window, store)
        }
    }

    private func waitUntil(_ window: UIWindow, _ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    private func client(canSign: Bool = true) throws -> PerpsClient {
        let market = try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[],"assetsFetchedAt":0}
        """.utf8))
        let snapshot = try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"tradingAvailability":{"isAvailable":\(canSign)},"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,
         "unavailableDexs":[],"balanceWithdrawal":{"balance":"1.5","amount":"1.47","bridgeFee":"0.2","receiveAmount":"1.27"}}
        """.utf8))
        var client = PerpsClient()
        client.supported = { true }
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: []) }
        return client
    }

    private nonisolated static func quote(amount: String, receiveAmount: String, expiresAt: Int64) -> ApiPerpsBalanceWithdrawalQuote {
        .init(id: "quote-\(expiresAt)", accountId: accountId, destination: "0x1234567890123456789012345678901234567890",
              balance: "1.5", amount: amount, bridgeFee: "0.2", receiveAmount: receiveAmount, expiresAt: expiresAt)
    }
}

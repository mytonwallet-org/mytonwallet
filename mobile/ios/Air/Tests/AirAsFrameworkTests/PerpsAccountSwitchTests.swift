import Dependencies
import GRDB
import UIKit
import XCTest
import UIComponents
@testable import UIToken
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

@MainActor
final class PerpsAccountSwitchTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    func testSwitchLoadsTheSelectedWalletAndDiscardsThePreviousDraft() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        let accounts = _AccountStore(db: database)
        for id in ["1-mainnet", "2-mainnet"] {
            let account = MAccount(id: id, title: id, type: .mnemonic, byChain: [.arbitrum: .init(address: "0x1234")])
            try await database.write { try account.insert($0) }
            _ = try await accounts.accountForActivation(accountId: id)
        }
        let market = try decode(ApiPerpsMarketSnapshot.self, """
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
          "dex":"","szDecimals":4,"maxLeverage":40,"tradingAvailability":{"isAvailable":true},
          "context":{"markPx":"100","prevDayPx":"100"}}],"assetsFetchedAt":0}
        """)
        let snapshot = try decode(ApiPerpsAccountSnapshot.self, """
        {"tradingAvailability":{"isAvailable":true},"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]}
        """)
        let funding = try decode(ApiPerpsFundingRequirements.self, """
        {"requiredUsdc":"10","requiredGasUsdc":"0","requiredEth":"0","requiredEthUsd":"0",
         "usdcBalance":"100","availableCollateral":"100","ethBalance":"1","needsUsdc":false,"needsEth":false}
        """)
        var snapshotAccounts: [String] = []
        var historyAccounts: [String] = []
        var fundingAccounts: [String] = []
        var previewAccounts: [String] = []
        var oldPreview: CheckedContinuation<ApiPerpsQuote, Error>?
        var client = PerpsClient()
        client.supported = { true }
        client.marketSnapshot = { market }
        client.positions = { accountId in snapshotAccounts.append(accountId); return snapshot }
        client.history = { accountId in historyAccounts.append(accountId); return .init(fills: []) }
        client.fundingRequirements = { accountId, _ in fundingAccounts.append(accountId); return funding }
        client.preview = { accountId, _ in
            previewAccounts.append(accountId)
            if accountId == "1-mainnet" {
                return try await withCheckedThrowingContinuation { oldPreview = $0 }
            }
            throw PerpsError.invalidResponse
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await store.refresh(accountId: "1-mainnet")

        try await withDependencies { $0.accountStore = accounts } operation: {
            let coordinator = PerpsCoordinator(accountId: "1-mainnet", store: store)
            let original = coordinator.makeOrder(asset: try XCTUnwrap(market.assets.first), side: .short)
            original.loadViewIfNeeded()
            let navigation = UINavigationController(rootViewController: original)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await waitUntil { fundingAccounts == ["1-mainnet"] }
            let switcher = try XCTUnwrap(original.navigationItem.leftBarButtonItem?.customView as? AccountSwitcherButton)
            XCTAssertTrue(switcher.isUserInteractionEnabled)
            let field = try XCTUnwrap(descendants(original.view).compactMap { $0 as? TradeTextField }.first)
            field.onChange?(.init(text: "25"))
            try await waitUntil { oldPreview != nil }

            await original.selectAccount("2-mainnet")
            let selected = try XCTUnwrap(navigation.topViewController as? PerpsOrderVC)
            XCTAssertFalse(selected === original)
            XCTAssertEqual(accounts.accountId, "2-mainnet")
            try await waitUntil { fundingAccounts.contains("2-mainnet") }
            XCTAssertTrue(snapshotAccounts.contains("2-mainnet"))
            XCTAssertEqual(historyAccounts, ["1-mainnet"])
            let selectedField = try XCTUnwrap(descendants(selected.view).compactMap { $0 as? TradeTextField }.first)
            XCTAssertTrue(selectedField.text?.isEmpty != false)

            oldPreview?.resume(throwing: PerpsError.invalidResponse)
            oldPreview = nil
            selectedField.onChange?(.init(text: "30"))
            try await waitUntil { previewAccounts.contains("2-mainnet") }
            XCTAssertEqual(previewAccounts, ["1-mainnet", "2-mainnet"])
            XCTAssertTrue(navigation.topViewController === selected)
            XCTAssertEqual(navigation.viewControllers.count, 1)
            XCTAssertEqual(selectedField.text, "30")
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

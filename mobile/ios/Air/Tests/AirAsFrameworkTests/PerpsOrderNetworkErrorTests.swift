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
final class PerpsOrderNetworkErrorTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    func testFundingConnectionFailureShowsNetworkMessageAndRetryRecovers() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        let account = MAccount(id: "1-mainnet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: .init(address: "0x1234")])
        try await database.write { try account.insert($0) }
        let accounts = _AccountStore(db: database)
        _ = try await accounts.accountForActivation(accountId: account.id)
        let market = try decode(ApiPerpsMarketSnapshot.self, """
        {"assets":[{"id":"hyperliquid:hl:SOL","name":"SOL","symbol":"SOL","dex":"","szDecimals":2,
          "maxLeverage":20,"tradingAvailability":{"isAvailable":true},"context":{"markPx":"200"}}],"assetsFetchedAt":0}
        """)
        let snapshot = try decode(ApiPerpsAccountSnapshot.self, """
        {"tradingAvailability":{"isAvailable":true},"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[]}
        """)
        let funding = try decode(ApiPerpsFundingRequirements.self, """
        {"requiredUsdc":"10","requiredGasUsdc":"0","requiredEth":"0","requiredEthUsd":"0",
         "usdcBalance":"0","availableCollateral":"0","ethBalance":"1","needsUsdc":true,"needsEth":false}
        """)
        var fundingRequests = 0
        var client = PerpsClient()
        client.supported = { true }
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.fundingRequirements = { _, _ in
            fundingRequests += 1
            if fundingRequests == 1 {
                throw SdkError.javaScriptException(.init(methodName: "perpsGetFundingRequirements",
                    exceptionMessage: #"{"message":"Load failed","name":"TypeError"}"#))
            }
            return funding
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        await store.refresh(accountId: account.id, includesHistory: false)

        try await withDependencies { $0.accountStore = accounts } operation: {
            let coordinator = PerpsCoordinator(accountId: account.id, store: store)
            let controller = coordinator.makeOrder(asset: try XCTUnwrap(market.assets.first), side: .long)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = UINavigationController(rootViewController: controller)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.loadViewIfNeeded()
            let notice = try XCTUnwrap(findDescendants(controller.view).first {
                $0.accessibilityIdentifier == "perps.order.unavailable"
            } as? NativeTradeNoticeView)
            try await waitUntil { notice.configuration?.actionTitle == lang("Retry") }
            XCTAssertEqual(fundingRequests, 1)
            XCTAssertEqual(notice.configuration?.message, lang("Please make sure your internet connection is working and try again."))
            let retry = try XCTUnwrap(findDescendants(notice).first {
                $0.accessibilityLabel == lang("Retry")
            } as? UIButton)
            retry.sendActions(for: .touchUpInside)
            let expected = PerpsSDKAdapter.order(asset: market.assets[0], account: account, side: .long,
                input: .init(amount: "", leverage: 2), fundingRequirements: funding).fundingRequirement
            let expectedTitle = try XCTUnwrap(expected?.title)
            try await waitUntil { notice.configuration?.title == expectedTitle }
            XCTAssertEqual(fundingRequests, 2)
            XCTAssertEqual(notice.configuration?.message, expected?.message)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    private func findDescendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + findDescendants($0) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

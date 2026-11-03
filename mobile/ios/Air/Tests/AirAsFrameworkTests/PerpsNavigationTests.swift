import Dependencies
import UIKit
import UIToken
import WalletCore
import WalletResources
import XCTest
@testable import AirAsFramework

@MainActor
final class PerpsNavigationTests: XCTestCase {
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
    }

    func testMarketSelectionOpensTheExistingPositionForEitherSide() async throws {
        for side in ["long", "short"] {
            let snapshot = try snapshot(side: side)
            let store = makeStore(snapshot: snapshot)
            await store.refresh(accountId: "wallet")
            let coordinator = PerpsCoordinator(accountId: "wallet", store: store)
            let origin = UIViewController()
            let navigation = UINavigationController(rootViewController: origin)

            coordinator.showMarket("hyperliquid:hl:BTC", from: origin)

            XCTAssertTrue(navigation.topViewController is PerpsPositionVC)
            XCTAssertEqual(navigation.viewControllers.count, 2)
        }
    }

    func testMarketSelectionDoesNotUseAnotherWalletsPosition() async throws {
        let snapshot = try snapshot(side: "long")
        var empty = snapshot
        empty.positions = []
        var client = makeClient(snapshot: empty)
        client.snapshot = { $0 == "other-wallet" ? snapshot : empty }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "other-wallet")
        await store.refresh(accountId: "wallet")
        let coordinator = PerpsCoordinator(accountId: "wallet", store: store)
        let origin = UIViewController()
        let navigation = UINavigationController(rootViewController: origin)

        coordinator.showMarket("hyperliquid:hl:BTC", from: origin)

        XCTAssertTrue(navigation.topViewController is PerpsMarketVC)
        XCTAssertEqual(navigation.viewControllers.count, 2)
    }

    private func makeStore(snapshot: ApiPerpsSnapshot) -> PerpsStore {
        PerpsStore(client: makeClient(snapshot: snapshot), load: { [] }, save: { _ in })
    }

    private func makeClient(snapshot: ApiPerpsSnapshot) -> PerpsClient {
        var client = PerpsClient()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        client.candles = { _, _ in [] }
        client.assetDetail = { _, _, _ in throw PerpsError.invalidResponse }
        return client
    }

    private func snapshot(side: String) throws -> ApiPerpsSnapshot {
        try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
          "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}],
         "positions":[{"id":"wallet/btc","assetId":"hyperliquid:hl:BTC","dex":"","side":"\(side)","size":"0.5",
           "collateral":"100","equity":"125","returnOnEquity":"0.25","funding":"0.3",
           "raw":{"coin":"BTC","entryPx":"2000","liquidationPx":"1800","leverage":{"type":"isolated","value":10},
             "marginUsed":"125","positionValue":"1000","returnOnEquity":"0.25","szi":"0.5","unrealizedPnl":"25"}}],
         "totalEquity":"125","totalPnl":"25","timestamp":0,"unavailableDexs":[]}
        """.utf8))
    }
}

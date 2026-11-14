import Dependencies
import GRDB
import UIKit
@testable import UIToken
@testable import WalletCore
import WalletResources
import XCTest
@testable import AirAsFramework

@MainActor
final class PerpsNavigationTests: XCTestCase {
    private var database: DatabaseQueue!

    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = WalletResourcesBundle.bundle.load()
        database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        SettingsStore.liveValue.use(db: database)
    }

    override func tearDown() {
        SettingsStore.liveValue.clean()
        super.tearDown()
    }

    func testMarketAndPositionChartsRememberTheLastTokenOrFuturesPeriod() async throws {
        AppStorageHelper.save(currentTokenPeriod: ApiPriceHistoryPeriod.month.rawValue)
        let session = try await makeSession(positions: false)
        session.coordinator.showMarket("hyperliquid:hl:BTC", from: session.origin)
        let market = try XCTUnwrap(session.navigation.topViewController as? PerpsMarketVC)
        XCTAssertEqual(try readSelectedPeriodTitle(in: market), ApiPriceHistoryPeriod.month.localized)
        market.onSelectPeriod(.year)
        XCTAssertEqual(AppStorageHelper.selectedCurrentTokenPeriod(), ApiPriceHistoryPeriod.year.rawValue)

        session.navigation.popViewController(animated: false)
        SettingsStore.liveValue.use(db: database)
        session.coordinator.showMarket("hyperliquid:hl:BTC", from: session.origin)
        let reopenedMarket = try XCTUnwrap(session.navigation.topViewController as? PerpsMarketVC)
        XCTAssertEqual(try readSelectedPeriodTitle(in: reopenedMarket), ApiPriceHistoryPeriod.year.localized)

        let positionSession = try await makeSession(positions: true)
        positionSession.coordinator.showPosition("wallet/btc", from: positionSession.origin)
        let position = try XCTUnwrap(positionSession.navigation.topViewController as? PerpsPositionVC)
        XCTAssertEqual(position.data.market.period, .year)
        position.onSelectPeriod(.all)
        XCTAssertEqual(AppStorageHelper.selectedCurrentTokenPeriod(), ApiPriceHistoryPeriod.all.rawValue)

        positionSession.navigation.popViewController(animated: false)
        positionSession.coordinator.showPosition("wallet/btc", from: positionSession.origin)
        let reopenedPosition = try XCTUnwrap(positionSession.navigation.topViewController as? PerpsPositionVC)
        XCTAssertEqual(reopenedPosition.data.market.period, .all)
    }

    private func readSelectedPeriodTitle(in controller: UIViewController) throws -> String {
        controller.loadViewIfNeeded()
        func findPeriods(in view: UIView) -> WChartSegmentedControl? {
            if let periods = view as? WChartSegmentedControl { return periods }
            return view.subviews.lazy.compactMap { findPeriods(in: $0) }.first
        }
        let periods = try XCTUnwrap(findPeriods(in: controller.view))
        return try XCTUnwrap(periods.titleForSegment(at: periods.selectedSegmentIndex))
    }

    func testMarketSelectionOpensTheExistingPositionForEitherSide() async throws {
        for side in ["long", "short"] {
            let snapshot = try snapshot(side: side)
            let store = try makeStore(snapshot: snapshot)
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
        var client = try makeClient(snapshot: empty)
        client.positions = { $0 == "other-wallet" ? snapshot : empty }
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

    /// Opening a position from the asset screen turns that screen into the position screen, so Long and Short are gone.
    func testOpeningAPositionTurnsTheMarketScreenIntoThePositionScreenInPlace() async throws {
        let session = try await makeSession(positions: false)
        session.coordinator.showMarket("hyperliquid:hl:BTC", from: session.origin)
        let market = try XCTUnwrap(session.navigation.topViewController as? PerpsMarketVC)
        market.onSelectPeriod(.week)

        await session.read(try snapshot(side: "long"))
        try await waitUntil { session.navigation.topViewController is PerpsPositionVC }

        XCTAssertEqual(session.navigation.viewControllers.count, 2)
        XCTAssertTrue(session.navigation.viewControllers.first === session.origin)
        let position = try XCTUnwrap(session.navigation.topViewController as? PerpsPositionVC)
        XCTAssertEqual(position.data.market.period, .week)
    }

    func testClosingThePositionTurnsThePositionScreenBackIntoTheMarketScreen() async throws {
        let session = try await makeSession(positions: true)
        session.coordinator.showPosition("wallet/btc", from: session.origin)
        let position = try XCTUnwrap(session.navigation.topViewController as? PerpsPositionVC)
        position.onSelectPeriod(.month)

        var closed = try snapshot(side: "long")
        closed.positions = []
        await session.read(closed)
        try await waitUntil { session.navigation.topViewController is PerpsMarketVC }

        XCTAssertEqual(session.navigation.viewControllers.count, 2)
        XCTAssertTrue(session.navigation.viewControllers.first === session.origin)
    }

    /// Without its catalogue the read cannot tell a closed position from one it could not place.
    func testAnIncompleteReadKeepsThePositionScreen() async throws {
        let session = try await makeSession(positions: true)
        session.coordinator.showPosition("wallet/btc", from: session.origin)

        var incomplete = try snapshot(side: "long")
        incomplete.positions = []
        incomplete.unavailableDexs = [""]
        await session.read(incomplete)
        // The switch runs on the next main-queue turn, so this gives it the chance to happen.
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(session.navigation.topViewController is PerpsPositionVC)
    }

    /// The receipt sheet stays up while the screen under it changes.
    func testTheSwitchKeepsASheetPresentedOverTheScreen() async throws {
        let session = try await makeSession(positions: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = session.navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        session.coordinator.showMarket("hyperliquid:hl:BTC", from: session.origin)
        let market = try XCTUnwrap(session.navigation.topViewController as? PerpsMarketVC)
        try await waitUntil { session.navigation.transitionCoordinator == nil && market.viewIfLoaded?.window != nil }
        let sheet = UINavigationController(rootViewController: UIViewController())
        market.present(sheet, animated: false)
        try await waitUntil { market.presentedViewController === sheet }

        await session.read(try snapshot(side: "long"))
        try await waitUntil { session.navigation.topViewController is PerpsPositionVC }
        try await waitUntil { session.navigation.viewControllers.count == 2 }

        XCTAssertTrue(session.navigation.presentedViewController === sheet)
        XCTAssertNotNil(sheet.presentingViewController)
        session.navigation.dismiss(animated: false)
    }

    func testTheAnimatedSwitchReplacesTheScreenInPlace() async throws {
        try await withAssetStack { navigation, root, current in
            let next = UIViewController()

            try await switchAssetScreen(current, to: next, in: navigation, whileAnimating: {})

            XCTAssertEqual(navigation.viewControllers, [root, next])
        }
    }

    func testBackJustBeforeTheSwitchLeavesTheAsset() async throws {
        try await withAssetStack { navigation, root, current in
            _ = navigation.popViewController(animated: true)

            await navigation.switchAssetScreen(current, to: UIViewController())
            try await waitUntil { navigation.transitionCoordinator == nil }

            XCTAssertEqual(navigation.viewControllers, [root])
        }
    }

    func testBackDuringTheSwitchAnimationLeavesTheAsset() async throws {
        try await withAssetStack { navigation, root, current in
            try await switchAssetScreen(current, to: UIViewController(), in: navigation, whileAnimating: {
                _ = navigation.popViewController(animated: true)
            })
            try await waitUntil { navigation.transitionCoordinator == nil }

            XCTAssertEqual(navigation.viewControllers, [root])
        }
    }

    func testAScreenPushedDuringTheSwitchAnimationStaysOnTop() async throws {
        try await withAssetStack { navigation, root, current in
            let next = UIViewController()
            let destination = UIViewController()

            try await switchAssetScreen(current, to: next, in: navigation, whileAnimating: {
                navigation.pushViewController(destination, animated: true)
            })
            try await waitUntil { navigation.transitionCoordinator == nil }

            XCTAssertEqual(navigation.viewControllers, [root, next, destination])
        }
    }

    func testAScreenAlreadyAboveTheOldStateStaysOnTop() async throws {
        try await withAssetStack { navigation, root, current in
            let next = UIViewController()
            let destination = UIViewController()
            navigation.pushViewController(destination, animated: false)

            await navigation.switchAssetScreen(current, to: next)

            XCTAssertEqual(navigation.viewControllers, [root, next, destination])
        }
    }

    /// Has the asset screen on top of a stack in a window, so that a switch animates
    private func withAssetStack(_ body: (UINavigationController, UIViewController, UIViewController) async throws -> Void) async throws {
        let root = UIViewController()
        let current = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(current, animated: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await waitUntil { navigation.transitionCoordinator == nil && current.viewIfLoaded?.window != nil }
        try await body(navigation, root, current)
    }

    private func switchAssetScreen(_ current: UIViewController, to next: UIViewController, in navigation: UINavigationController,
                                   whileAnimating navigate: () -> Void) async throws {
        let switching = Task { await navigation.switchAssetScreen(current, to: next) }
        try await waitUntil { navigation.viewControllers.contains(next) }
        // Both states are in the stack only while the animation runs
        XCTAssertTrue(navigation.viewControllers.contains(current))
        navigate()
        await switching.value
    }

    /// One account behind a store whose next read a test can change.
    @MainActor private final class Session {
        let coordinator: PerpsCoordinator
        let origin = UIViewController()
        let navigation: UINavigationController
        private let store: PerpsStore
        private let answer: Answer

        final class Answer { var snapshot: ApiPerpsAccountSnapshot; init(_ snapshot: ApiPerpsAccountSnapshot) { self.snapshot = snapshot } }

        init(answer: Answer, client: PerpsClient) {
            self.answer = answer
            navigation = UINavigationController(rootViewController: origin)
            store = PerpsStore(client: client, load: { [] }, save: { _ in })
            coordinator = PerpsCoordinator(accountId: "wallet", store: store)
        }

        func read(_ snapshot: ApiPerpsAccountSnapshot) async {
            answer.snapshot = snapshot
            await store.refresh(accountId: "wallet", force: true)
        }
    }

    private func makeSession(positions: Bool) async throws -> Session {
        var initial = try snapshot(side: "long")
        if !positions { initial.positions = [] }
        let answer = Session.Answer(initial)
        var client = try makeClient(snapshot: initial)
        client.positions = { _ in answer.snapshot }
        let session = Session(answer: answer, client: client)
        await session.read(initial)
        return session
    }

    private func waitUntil(line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), line: line)
    }

    private func makeStore(snapshot: ApiPerpsAccountSnapshot) throws -> PerpsStore {
        PerpsStore(client: try makeClient(snapshot: snapshot), load: { [] }, save: { _ in })
    }

    private func makeClient(snapshot: ApiPerpsAccountSnapshot) throws -> PerpsClient {
        let market = try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[{"id":"hyperliquid:hl:BTC","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
          "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}],"assetsFetchedAt":0}
        """.utf8))
        var client = PerpsClient()
        client.marketSnapshot = { market }
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: []) }
        client.candles = { _, _ in [] }
        client.assetDetail = { _, _, _ in throw PerpsError.invalidResponse }
        return client
    }

    private func snapshot(side: String) throws -> ApiPerpsAccountSnapshot {
        try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"positions":[{"id":"wallet/btc","assetId":"hyperliquid:hl:BTC","dex":"","side":"\(side)","size":"0.5",
           "collateral":"100","equity":"125","returnOnEquity":"0.25","funding":"0.3",
           "raw":{"coin":"BTC","entryPx":"2000","liquidationPx":"1800","leverage":{"type":"isolated","value":10},
             "marginUsed":"125","positionValue":"1000","returnOnEquity":"0.25","szi":"0.5","unrealizedPnl":"25"}}],
         "totalEquity":"125","totalPnl":"25","timestamp":0,"unavailableDexs":[]}
        """.utf8))
    }
}

import Dependencies
import CoreSpotlight
import UIKit
import XCTest
import UIComponents
import UIAssets
import UIUniversalSearch
import WalletContext
import WalletResources
@testable import AirAsFramework

@MainActor
final class SystemSearchNavigationTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
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

    func testSpotlightContinuationPreservesTheQuery() throws {
        let activity = NSUserActivity(activityType: CSQueryContinuationActionType)
        activity.userInfo = [CSSearchQueryString: "  eth usdt  "]
        let action = try XCTUnwrap(AirSystemAction(searchContinuation: activity))
        guard case let .search(query) = action else { return XCTFail("Expected an in-app search") }
        XCTAssertEqual(query, "  eth usdt  ")
    }

    func testSpotlightContinuationRejectsUnrelatedAndMalformedActivities() {
        let unrelated = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        unrelated.userInfo = [CSSearchQueryString: "solana"]
        XCTAssertNil(AirSystemAction(searchContinuation: unrelated))
        let continuation = NSUserActivity(activityType: CSQueryContinuationActionType)
        XCTAssertNil(AirSystemAction(searchContinuation: continuation))
        continuation.userInfo = [CSSearchQueryString: 42]
        XCTAssertNil(AirSystemAction(searchContinuation: continuation))
    }

    @available(iOS 17.0, *)
    func testSystemSearchPreservesQueryAndReusesCoveredSearch() async throws {
        for sizeClass: UIUserInterfaceSizeClass in [.compact, .regular] {
            let (root, window) = host(sizeClass)
            defer { window.isHidden = true }
            try await settle(window)
            let toolbar = root.searchController
            toolbar.showSearch(query: "solana")
            try await settle(window)
            let search = try XCTUnwrap(toolbar.universalSearchViewController)
            XCTAssertEqual(search.fieldConfiguration.text, "solana")
            XCTAssertEqual(toolbar.searchToolbar.configuration.text, "solana")
            toolbar.showSearch(query: "SOL")
            try await settle(window)
            XCTAssertTrue(toolbar.universalSearchViewController === search)
            XCTAssertEqual(search.fieldConfiguration.text, "SOL")

            XCTAssertTrue(toolbar.pushFromSearch(UIViewController()))
            try await settle(window)
            toolbar.showSearch(query: "eth usdt")
            try await settle(window)
            XCTAssertTrue(try navigation(root).topViewController === search)
            XCTAssertEqual(search.fieldConfiguration.text, "eth usdt")
            XCTAssertNil(search.returnDeadline)

            root.coveredController = UIViewController()
            toolbar.showSearch(query: "bitcoin")
            try await settle(window)
            XCTAssertTrue(root.didDismissCover)
            XCTAssertNil(root.presentedViewController)
            XCTAssertEqual(toolbar.searchToolbar.configuration.text, "bitcoin")
        }
    }

    @available(iOS 17.0, *)
    func testSearchWithoutKeyboardKeepsTheHomeToolbarInsets() async throws {
        let (root, window) = host(.compact, size: CGSize(width: 402, height: 874))
        defer { window.isHidden = true }
        try await settle(window)
        let toolbar = root.searchController.searchToolbar
        func getToolbarFrame() -> CGRect { toolbar.convert(toolbar.bounds, to: root.view) }
        XCTAssertEqual(toolbar.presentation, .homeToolbar)
        let homeFrame = getToolbarFrame()
        XCTAssertEqual(homeFrame.minX - root.view.safeAreaInsets.left, 28, accuracy: 0.5)

        root.searchController.showSearch(query: "solana")
        try await settle(window)
        XCTAssertEqual(toolbar.presentation, .search)
        XCTAssertFalse(toolbar.isEditing)
        let searchFrame = getToolbarFrame()
        XCTAssertEqual(searchFrame.minX, homeFrame.minX, accuracy: 0.5)
        XCTAssertEqual(searchFrame.maxX, homeFrame.maxX, accuracy: 0.5)
        XCTAssertEqual(searchFrame.maxY, homeFrame.maxY, accuracy: 0.5)
    }

    @available(iOS 17.0, *)
    private func host(
        _ sizeClass: UIUserInterfaceSizeClass,
        size: CGSize = CGSize(width: 1024, height: 900)
    ) -> (SearchTestHost, UIWindow) {
        let root = SearchTestHost()
        root.traitOverrides.horizontalSizeClass = sizeClass
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = root
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        root.searchController.attach(to: root)
        return (root, window)
    }

    private func navigation(_ root: SearchTestHost) throws -> WNavigationController { root }

    private func settle(_ window: UIWindow) async throws {
        // A custom navigation animator can outlive UIView's disabled animations.
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if let root = window.rootViewController as? SearchTestHost,
               root.transitionCoordinator == nil { return }
        }
        XCTFail("Navigation did not settle")
    }
}

@MainActor
private final class SearchTestHost: WNavigationController, RootSearchToolbarHost {
    let searchController = RootSearchToolbarController()
    var searchNavigationController: WNavigationController? { self }
    var searchRootContentControllers: [UIViewController] { Array(viewControllers.prefix(1)) }
    var searchEditingNavigator: NftsEditingNavigator? { nil }
    var showsRootSearchToolbar: Bool { true }

    // Hostless package tests cannot complete UIKit's modal presentation lifecycle.
    // Model the cover here to verify the controller's dismissal/navigation handoff.
    var coveredController: UIViewController?
    var didDismissCover = false
    override var presentedViewController: UIViewController? { coveredController ?? super.presentedViewController }
    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        guard coveredController != nil else { return super.dismiss(animated: animated, completion: completion) }
        coveredController = nil
        didDismissCover = true
        completion?()
    }

    init() { super.init(rootViewController: UIViewController()) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setSearchVisible(_ isVisible: Bool, coordinator: (any UIViewControllerTransitionCoordinator)?) {}
}

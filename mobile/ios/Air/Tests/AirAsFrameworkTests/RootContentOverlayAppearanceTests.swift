import ContextMenuKit
import Dependencies
import GRDB
import UIKit
import XCTest
import UIAssets
import UIComponents
import WalletContext
import WalletResources
@testable import WalletCore
@testable import AirAsFramework

@MainActor
final class RootContentOverlayAppearanceTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    override func setUpWithError() throws {
        _ = WalletResourcesBundle.bundle.load()
        try MainActor.assumeIsolated {
            let db = try DatabaseQueue()
            try makeMigrator().migrate(db)
            SettingsStore.liveValue.use(db: db)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { SettingsStore.liveValue.clean() }
        super.tearDown()
    }

    func testOrdinaryDuoScreensKeepStandardAppearance() async throws {
        let (host, window, toolbar) = try makeHost()
        defer { window.isHidden = true }
        host.navigation.pushViewController(WViewController(), animated: true)
        try await settle(window)
        let previousAnimations = animations(in: toolbar.searchToolbar.layer)
        toolbar.updatePresentation()
        let currentAnimations = animations(in: toolbar.searchToolbar.layer)
        XCTAssertEqual(toolbar.searchToolbar.presentation, .sideToolbar)
        XCTAssertEqual(toolbar.searchToolbar.searchOverlayAppearance, .standard)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, .standard)
        XCTAssertEqual(currentAnimations, previousAnimations)

        toolbar.openSearch()
        try await settle(window)
        toolbar.updatePresentation()
        XCTAssertEqual(toolbar.searchToolbar.searchOverlayAppearance, .standard)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, .standard)
        XCTAssertEqual(toolbar.searchToolbar.trailingButtonView.overrideUserInterfaceStyle, .unspecified)
    }

    func testNftAppearanceDoesNotOverrideBottomToolbar() async throws {
        let (host, window, toolbar) = try makeHost(verticalEdge: nil)
        defer { window.isHidden = true }
        let nft = ContentController()
        host.navigation.pushViewController(nft, animated: true)
        try await settle(window)
        XCTAssertEqual(toolbar.searchToolbar.searchOverlayAppearance, .standard)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, .standard)
        XCTAssertNil(nft.onContentOverlayAppearanceChange)
    }

    func testDuoAppearanceUpdatesAndResetsForSearchAndNavigation() async throws {
        let (host, window, toolbar) = try makeHost()
        defer { window.isHidden = true }
        let nft = ContentController()
        host.navigation.pushViewController(nft, animated: true)
        try await settle(window)
        XCTAssertEqual(toolbar.searchToolbar.presentation, .sideToolbar)
        XCTAssertEqual(toolbar.searchToolbar.searchOverlayAppearance, nft.appearance)
        XCTAssertEqual(toolbar.searchToolbar.trailingButtonView.traitCollection.userInterfaceStyle, .dark)

        nft.appearance = .init(usesClearGlass: true, foregroundColor: .black, userInterfaceStyle: .light)
        nft.onContentOverlayAppearanceChange?(true)
        XCTAssertTrue(hasAnimations(in: toolbar.searchToolbar.layer), "Content contrast changes should animate")
        try await settle(window)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, nft.appearance)
        XCTAssertEqual(toolbar.searchToolbar.trailingButtonView.traitCollection.userInterfaceStyle, .light)
        nft.appearance = ContentController.darkAppearance
        nft.onContentOverlayAppearanceChange?(true)
        try await settle(window)

        toolbar.openSearch()
        try await settle(window)
        XCTAssertTrue(toolbar.isSearchVisible)
        XCTAssertEqual(toolbar.searchToolbar.searchOverlayAppearance, .standard)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, .standard)
        XCTAssertEqual(toolbar.searchToolbar.trailingButtonView.traitCollection.userInterfaceStyle, .light)
        XCTAssertNil(nft.onContentOverlayAppearanceChange)

        toolbar.closeSearch()
        try await settle(window)
        XCTAssertTrue(host.navigation.topViewController === nft)
        XCTAssertEqual(toolbar.searchToolbar.searchOverlayAppearance, nft.appearance)
        XCTAssertNotNil(nft.onContentOverlayAppearanceChange)

        _ = host.navigation.popViewController(animated: true)
        try await settle(window)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, .standard)
        XCTAssertNil(nft.onContentOverlayAppearanceChange)
    }

    func testCancelledNavigationRestoresAppearanceAndSubscription() async throws {
        let (host, window, toolbar) = try makeHost()
        defer { window.isHidden = true }
        let nft = ContentController()
        host.navigation.pushViewController(nft, animated: false)
        try await settle(window)
        let transition = try XCTUnwrap(host.navigation.beginInteractivePush(WViewController()))
        transition.update(0.4)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, .standard)
        transition.cancel()
        try await settle(window)
        XCTAssertTrue(host.navigation.topViewController === nft)
        XCTAssertEqual(toolbar.searchToolbar.actionsOverlayAppearance, nft.appearance)
        XCTAssertNotNil(nft.onContentOverlayAppearanceChange)
    }

    func testActionMenuInheritsDarkSource() async throws {
        guard #available(iOS 26, *) else { return }
        let (host, window, toolbar) = try makeHost()
        defer { window.isHidden = true }
        host.navigation.pushViewController(ContentController(), animated: false)
        try await settle(window)
        let interaction = ContextMenuInteraction(triggers: [.tap], presentationMode: .zoomSheetOrPopover) { _ in
            ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: [.action(.init(title: "Action", handler: {}))]),
                backdrop: .none,
                sheetNavigationControllerProvider: { ActionMenuNavigationController(rootViewController: $0) }
            )
        }
        interaction.attach(to: toolbar.searchToolbar.trailingButtonView)
        UIView.performWithoutAnimation { interaction.present() }
        try await settle(window)
        let menu = try XCTUnwrap(host.navigation.presentedViewController as? ActionMenuNavigationController)
        XCTAssertEqual(menu.overrideUserInterfaceStyle, .dark)
        menu.dismiss(animated: false)
    }

    func testActionMenuResetsWhenReplacingContent() async throws {
        guard #available(iOS 26, *) else { return }
        let menu = ActionMenuNavigationController(rootViewController: MenuController())
        menu.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = menu
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await settle(window)
        let destination = WViewController()
        menu.present(WNavigationController(rootViewController: destination), animated: true)
        try await settle(window)
        XCTAssertTrue(menu.topViewController === destination)
        XCTAssertEqual(menu.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(destination.traitCollection.userInterfaceStyle, .light)
    }

    func testStatusBarForwardingReachesVisibleContent() {
        let nft = ContentController()
        let navigation = WNavigationController(rootViewController: nft)
        let container = RootContainerVC(contentViewController: navigation)
        let host = RootHostVC()
        host.setContentViewController(container, rootState: .active, animationDuration: nil)
        var owner: UIViewController = host
        while let child = owner.childForStatusBarStyle { owner = child }
        XCTAssertTrue(owner === nft)
        XCTAssertEqual(owner.preferredStatusBarStyle, .lightContent)
        let ordinary = WViewController()
        navigation.pushViewController(ordinary, animated: false)
        XCTAssertTrue(navigation.childForStatusBarStyle === ordinary)
    }

    private func makeHost(verticalEdge: UIRectEdge? = .right) throws -> (Host, UIWindow, RootSearchToolbarController) {
        let host = Host(verticalEdge: verticalEdge)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host.navigation
        if #available(iOS 17, *) { host.navigation.traitOverrides.horizontalSizeClass = .compact }
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        let toolbar = RootSearchToolbarController()
        toolbar.attach(to: host)
        window.layoutIfNeeded()
        return (host, window, toolbar)
    }

    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
        }
    }

    private func hasAnimations(in layer: CALayer) -> Bool {
        !animations(in: layer).isEmpty
    }

    private func animations(in layer: CALayer) -> [ObjectIdentifier: [String]] {
        var result: [ObjectIdentifier: [String]] = [:]
        if let keys = layer.animationKeys(), !keys.isEmpty { result[ObjectIdentifier(layer)] = keys }
        for child in layer.sublayers ?? [] {
            result.merge(animations(in: child)) { _, new in new }
        }
        return result
    }

    private final class Host: RootSearchToolbarHost {
        let navigation = WNavigationController(rootViewController: WViewController())
        var searchNavigationController: WNavigationController? { navigation }
        var searchRootContentControllers: [UIViewController] { [navigation.viewControllers[0]] }
        var searchEditingNavigator: NftsEditingNavigator? { nil }
        var showsRootSearchToolbar: Bool { true }
        // Logic-test windows have no scene and cannot receive Duo's hardware traits.
        let searchToolbarVerticalEdge: UIRectEdge?

        init(verticalEdge: UIRectEdge?) {
            searchToolbarVerticalEdge = verticalEdge
        }
    }

    private final class ContentController: WViewController, ContentOverlayAppearanceProviding {
        static let darkAppearance = ContentOverlayAppearance(usesClearGlass: true, foregroundColor: .white, userInterfaceStyle: .dark)
        var appearance = darkAppearance
        var onContentOverlayAppearanceChange: ((Bool) -> Void)?
        func contentOverlayAppearance(in rectInWindow: CGRect) -> ContentOverlayAppearance { appearance }
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
        }
    }

    @available(iOS 26, *)
    private final class MenuController: WViewController, ContextMenuSheetContent {
        func prepareForContentReplacement() {}
        func animateContentReplacement() {}
    }
}

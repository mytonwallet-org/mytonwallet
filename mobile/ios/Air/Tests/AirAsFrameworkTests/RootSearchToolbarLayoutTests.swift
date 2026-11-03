import Dependencies
import GRDB
import UIKit
import XCTest
import UIAssets
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

@MainActor
final class RootSearchToolbarLayoutTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
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

    func testBottomSpacingTracksMinimizeExpandAndClose() async throws {
        // Keep the host quiet: unrelated screen updates can mask a missed toolbar layout.
        let host = Host()
        var configuration = MinimizableSheetConfiguration.default
        configuration.minimizedVisibleHeight = 44
        let container = MinimizableSheetContainerViewController(
            mainViewController: host.navigation,
            sheetViewController: UIViewController(),
            configuration: configuration
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        // Exercise the inset transition on home-button devices as well.
        container.additionalSafeAreaInsets.bottom = max(0, 34 - container.view.safeAreaInsets.bottom)
        window.layoutIfNeeded()
        let controller = RootSearchToolbarController()
        controller.attach(to: host)
        try await settle(window)

        let hostView = host.navigation.view!
        let toolbar = controller.searchToolbar
        func bottomGap() -> CGFloat {
            hostView.bounds.maxY - toolbar.convert(toolbar.bounds, to: hostView).maxY
        }
        let originalSafeAreaBottom = hostView.safeAreaInsets.bottom
        let originalGap = bottomGap()
        XCTAssertGreaterThan(originalSafeAreaBottom, 0)
        XCTAssertGreaterThan(originalGap, 16)

        for animated in [false, true] {
            for state: MinimizableSheetState in [.expanded, .minimized, .expanded, .minimized, .hidden] {
                container.sheetController.setState(state, animated: animated)
                try await settle(window)
                let context = "state=\(state), animated=\(animated)"
                XCTAssertEqual(
                    hostView.safeAreaInsets.bottom,
                    state == .minimized ? 0 : originalSafeAreaBottom,
                    accuracy: 0.5,
                    context
                )
                XCTAssertEqual(bottomGap(), state == .minimized ? 16 : originalGap, accuracy: 0.5, context)
            }
        }
    }

    private final class Host: RootSearchToolbarHost {
        let navigation = WNavigationController(rootViewController: WViewController())
        var searchNavigationController: WNavigationController? { navigation }
        var searchRootContentControllers: [UIViewController] { navigation.viewControllers }
        var searchEditingNavigator: NftsEditingNavigator? { nil }
        var showsRootSearchToolbar: Bool { true }
    }

    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
        }
    }
}

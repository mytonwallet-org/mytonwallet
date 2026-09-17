import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct NavigationCrossfadeTests {
    private final class SearchScreen: WViewController {
        private let hidesBar: Bool

        override var hideNavigationBar: Bool { hidesBar }

        init(hidesBar: Bool) {
            self.hidesBar = hidesBar
            super.init(nibName: nil, bundle: nil)
            navigationItem.hidesBackButton = true
            configureNavigationItemWithTransparentBackground()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    @Test(arguments: [true, false])
    func `crossfade uses its own duration and leaves result navigation native`(hidesBar: Bool) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let source = WViewController()
        source.navigationItem.title = "Source"
        let navigation = WNavigationController(rootViewController: source)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))

        let search = SearchScreen(hidesBar: hidesBar)
        navigation.withCrossfade(duration: 0.12) {
            navigation.pushViewController(search, animated: true)
        }
        let coordinator = try #require(navigation.transitionCoordinator)
        #expect(abs(coordinator.transitionDuration - 0.12) < 0.001)
        try await Task.sleep(for: .milliseconds(350))
        #expect(navigation.isNavigationBarHidden == hidesBar)
        #expect(navigation.delegate === navigation)
        #expect(navigation.topViewController === search)
        if hidesBar {
            #expect(search.view.safeAreaInsets.top == window.safeAreaInsets.top)
        } else {
            #expect(navigation.navigationBar.topItem === search.navigationItem)
            #expect(navigation.navigationBar.topItem?.hidesBackButton == true)
            #expect(navigation.navigationBar.topItem?.title == nil)
        }

        let result = WViewController()
        result.navigationItem.title = "Result"
        navigation.pushViewController(result, animated: true)
        #expect(navigation.delegate === navigation)
        try await Task.sleep(for: .seconds(1))
        #expect(!navigation.isNavigationBarHidden)
        #expect(navigation.topViewController === result)

        _ = navigation.popViewController(animated: true)
        try await Task.sleep(for: .seconds(1))
        #expect(navigation.topViewController === search)
        #expect(navigation.isNavigationBarHidden == hidesBar)

        navigation.withCrossfade(duration: 0.18) {
            _ = navigation.popViewController(animated: true)
        }
        #expect(abs(try #require(navigation.transitionCoordinator).transitionDuration - 0.18) < 0.001)
        try await Task.sleep(for: .milliseconds(400))
        #expect(navigation.topViewController === source)
        #expect(!navigation.isNavigationBarHidden)
        #expect(navigation.navigationBar.topItem === source.navigationItem)
        #expect(navigation.delegate === navigation)
    }

    @Test
    func `a crossfade without a stack change releases its delegate and snapshot`() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let navigation = WNavigationController(rootViewController: WViewController())
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        let originalSubviews = navigation.view.subviews
        navigation.withCrossfade(duration: 0.12) {}
        #expect(navigation.delegate === navigation)
        #expect(navigation.view.subviews == originalSubviews)
    }
}

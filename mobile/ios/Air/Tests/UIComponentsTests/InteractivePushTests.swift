import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct InteractivePushTests {
    @Test(arguments: [false, true])
    func `native push supports completion and cancellation`(complete: Bool) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let root = UIViewController()
        let navigation = WNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.view.layoutIfNeeded()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))

        let destination = UIViewController()
        let transition = try #require(navigation.beginInteractivePush(destination))
        let coordinator = try #require(navigation.transitionCoordinator)
        #expect(coordinator.isInteractive)
        #expect(navigation.beginInteractivePush(UIViewController()) == nil)
        try await Task.sleep(for: .milliseconds(100))
        transition.update(0.4)
        try await Task.sleep(for: .milliseconds(100))
        if complete { transition.finish() } else { transition.cancel() }
        #expect(navigation.delegate === navigation)
        try await Task.sleep(for: .seconds(1))
        #expect(navigation.topViewController === (complete ? destination : root))
        #expect(navigation.transitionCoordinator == nil)
        #expect(navigation.delegate === navigation)

        if complete {
            _ = navigation.popViewController(animated: false)
            try await Task.sleep(for: .milliseconds(100))
        }
        let next = try #require(navigation.beginInteractivePush(UIViewController()))
        try await Task.sleep(for: .milliseconds(100))
        next.cancel()
        try await Task.sleep(for: .seconds(1))
        #expect(navigation.topViewController === root)
        #expect(navigation.delegate === navigation)
    }

    @Test
    func `native pop can preempt a finishing push`() async throws {
        guard #available(iOS 26.0, *) else { return }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let root = UIViewController()
        let navigation = WNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.view.layoutIfNeeded()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))

        let destination = UIViewController()
        let transition = try #require(navigation.beginInteractivePush(destination))
        try await Task.sleep(for: .milliseconds(100))
        transition.update(0.4)
        transition.finish()
        #expect(navigation.delegate === navigation)
        #expect(navigation.transitionCoordinator != nil)
        #expect(navigation.popViewController(animated: true) === destination)
        try await Task.sleep(for: .seconds(1))
        #expect(navigation.topViewController === root)
        #expect(navigation.viewControllers.count == 1)
        #expect(navigation.transitionCoordinator == nil)
        #expect(navigation.delegate === navigation)
    }

    @Test
    func `push requires a visible navigation controller`() {
        let navigation = WNavigationController(rootViewController: UIViewController())
        #expect(navigation.beginInteractivePush(UIViewController()) == nil)
        #expect(navigation.viewControllers.count == 1)
    }
}

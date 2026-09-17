import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct ContentReplaceAnimationTests {
    @Test(arguments: [true, false], [true, false])
    func `replacement waits for an active transition and revalidates before changing layout or navigation`(remainsValid: Bool, completesOpening: Bool) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let root = UIViewController()
        let navigation = WNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.view.layoutIfNeeded()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))

        let menu = UIViewController()
        let openingTransition = try #require(navigation.beginInteractivePush(menu))
        try await Task.sleep(for: .milliseconds(50))
        _ = try #require(navigation.transitionCoordinator)

        let destination = UIViewController()
        destination.navigationItem.hidesBackButton = true
        let shouldReplace = remainsValid && completesOpening
        let expectedTop = completesOpening ? (remainsValid ? destination : menu) : root
        var prepared = false
        var completed = 0
        var isValid = true
        let replacement = ContentReplaceAnimationCoordinator()
        replacement.replaceNavigationTop(with: destination, in: navigation, prepareLayout: {
            #expect(navigation.transitionCoordinator == nil)
            prepared = true
        }, isValid: { isValid }, animateAlongside: {}) {
            completed += 1
            #expect(navigation.viewControllers.count == (completesOpening && !remainsValid ? 2 : 1))
            #expect(navigation.topViewController === expectedTop)
        }
        #expect(!prepared)
        #expect(navigation.topViewController === menu)
        isValid = remainsValid
        if completesOpening {
            openingTransition.finish()
        } else {
            openingTransition.cancel()
        }

        try await Task.sleep(for: .seconds(2))
        #expect(prepared == shouldReplace)
        #expect(completed == 1)
        #expect(navigation.delegate === navigation)
        #expect(navigation.transitionCoordinator == nil)
        #expect(navigation.topViewController === expectedTop)
        #expect(destination.navigationItem.hidesBackButton)
    }
}

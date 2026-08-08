import Testing
import UIKit
@testable import UIComponents

@Suite("Content Replacement")
@MainActor
struct ContentReplaceAnimationTests {
    @Test
    func `replacement without animation resets the navigation stack`() async {
        let origin = UIViewController()
        let authorization = UIViewController()
        let completion = UIViewController()
        let navigationController = UINavigationController()
        navigationController.setViewControllers([origin, authorization], animated: false)
        let originalDelegate = NavigationDelegate()
        navigationController.delegate = originalDelegate
        var animateAlongsideCount = 0

        let didReplace = await ContentReplaceAnimationCoordinator().replaceNavigationStack(
            with: completion,
            in: navigationController,
            targetViewControllers: [completion],
            animateAlongside: { animateAlongsideCount += 1 }
        )

        #expect(didReplace)
        #expect(navigationController.viewControllers.count == 1)
        #expect(navigationController.viewControllers[0] === completion)
        #expect(navigationController.delegate === originalDelegate)
        #expect(animateAlongsideCount == 1)
    }
}

private final class NavigationDelegate: NSObject, UINavigationControllerDelegate {}

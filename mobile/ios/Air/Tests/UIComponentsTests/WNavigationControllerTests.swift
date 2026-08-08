import Testing
import UIKit
@testable import UIComponents

@Suite("Navigation Back Swipe")
@MainActor
struct NavigationBackSwipeTests {
    @Test
    func `compatibility navigation reports and restores full width gesture state`() {
        guard !IOS_26_MODE_ENABLED else { return }
        let navigationController = WNavigationController(rootViewController: UIViewController())
        navigationController.loadViewIfNeeded()

        #expect(navigationController.interactivePopGestureRecognizer?.isEnabled == false)
        #expect(navigationController.isBackSwipeToDismissAllowed)

        navigationController.allowBackSwipeToDismiss(false)
        #expect(!navigationController.isBackSwipeToDismissAllowed)

        navigationController.allowBackSwipeToDismiss(true)
        #expect(navigationController.isBackSwipeToDismissAllowed)
    }
}

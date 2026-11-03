import Testing
import UIKit
@testable import UIComponents

@MainActor @Suite(.serialized)
struct NavigationDismissalTests {
    @Test func callbackFiresOnceForDismissalAndNotForCovering() {
        let navigation = DismissalNavigationController(rootViewController: UIViewController())
        var dismissals = 0
        navigation.onPresentationDismissed = { dismissals += 1 }
        navigation.viewWillAppear(false)
        navigation.viewDidAppear(false)
        navigation.viewWillDisappear(false)
        navigation.viewDidDisappear(false)
        #expect(dismissals == 0)
        #expect(navigation.onPresentationDismissed != nil)
        navigation.viewWillAppear(false)
        navigation.viewDidAppear(false)
        #expect(dismissals == 0)
        navigation.simulatesDismissal = true
        navigation.viewWillDisappear(false)
        navigation.viewDidDisappear(false)
        #expect(dismissals == 1)
        #expect(navigation.onPresentationDismissed == nil)
        navigation.viewDidDisappear(false)
        #expect(dismissals == 1)
    }

    @Test func returningDuringACancelledDismissalDoesNotConsumeTheCallback() {
        let navigation = DismissalNavigationController(rootViewController: UIViewController())
        var dismissals = 0
        navigation.onPresentationDismissed = { dismissals += 1 }
        navigation.simulatesDismissal = true
        navigation.viewWillDisappear(true)
        navigation.simulatesDismissal = false
        navigation.viewWillAppear(true)
        navigation.viewDidAppear(true)
        #expect(dismissals == 0)
        #expect(navigation.onPresentationDismissed != nil)

        navigation.simulatesDismissal = true
        navigation.viewWillDisappear(true)
        navigation.viewDidDisappear(true)
        #expect(dismissals == 1)
        #expect(navigation.onPresentationDismissed == nil)
    }

    private final class DismissalNavigationController: WNavigationController {
        var simulatesDismissal = false
        override var isBeingDismissed: Bool { simulatesDismissal }
    }
}

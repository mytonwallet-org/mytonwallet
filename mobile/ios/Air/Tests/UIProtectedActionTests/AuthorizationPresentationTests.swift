import Testing
import UIKit
@testable import UIProtectedAction

@Suite("Authorization Presentation", .serialized)
@MainActor
struct AuthorizationPresentationTests {
    @Test
    func `sheet presentation is rejected when presenter is detached`() {
        let presenter = UIViewController()
        presenter.loadViewIfNeeded()

        #expect(
            !AuthorizationSupport.presentSheet(
                UIViewController(),
                on: presenter,
                animated: false
            )
        )
    }

    @Test
    func `sheet presentation reports UIKit acceptance`() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.loadViewIfNeeded()
        defer { window.isHidden = true }

        let presented = UIViewController()
        #expect(AuthorizationSupport.presentSheet(presented, on: presenter, animated: false))
        #expect(presented.presentingViewController === presenter)
        presenter.dismiss(animated: false)
    }
}

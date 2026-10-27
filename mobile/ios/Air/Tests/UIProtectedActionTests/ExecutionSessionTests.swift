import ProtectedAction
import Testing
import UIKit
@testable import UIProtectedAction

@Suite("Execution session")
@MainActor
struct ExecutionSessionTests {
    @Test
    func `child of a stacked container can present authorization`() throws {
        let container = UIViewController()
        let child = UIViewController()
        container.addChild(child)
        container.view.addSubview(child.view)
        child.didMove(toParent: container)
        let navigationController = UINavigationController(rootViewController: container)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.isHidden = false
        defer { window.isHidden = true }

        let session = try #require(ExecutionSessionRegistry.shared.acquire(in: ExecutionContext(child)))
        defer { session.finish() }

        #expect(session.configurationError == nil)
        #expect(session.canPresentAuthorization)
    }
}

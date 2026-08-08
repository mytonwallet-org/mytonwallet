import ProtectedAction
import Testing
import UIKit
@testable import UIProtectedAction

@Suite("Protected Action Execution Session", .serialized)
@MainActor
struct ExecutionSessionTests {
    @Test
    func `only one execution can own a presentation surface`() {
        let registry = ExecutionSessionRegistry()
        let origin = UIViewController()
        let presenter = UIViewController()
        let navigationController = UINavigationController()
        navigationController.setViewControllers([origin, presenter], animated: false)
        let context = ExecutionContext(
            authorizationPresenter: presenter,
            flowOrigin: origin
        )

        let first = registry.acquire(in: context)
        let duplicate = registry.acquire(in: context)

        #expect(first != nil)
        #expect(duplicate == nil)
        first?.finish()
        #expect(registry.acquire(in: context) != nil)
    }

    @Test
    func `different presentation surfaces have independent executions`() {
        let registry = ExecutionSessionRegistry()
        let firstPresenter = UIViewController()
        let secondPresenter = UIViewController()

        let first = registry.acquire(in: ExecutionContext(firstPresenter))
        let second = registry.acquire(in: ExecutionContext(secondPresenter))

        #expect(first != nil)
        #expect(second != nil)
    }

    @Test
    func `visible authorization presenter may differ from flow origin`() {
        withVisibleNavigationController { navigationController in
            let origin = UIViewController()
            let presenter = UIViewController()
            navigationController.setViewControllers([origin, presenter], animated: false)
            let session = ExecutionSessionRegistry().acquire(
                in: ExecutionContext(
                    authorizationPresenter: presenter,
                    flowOrigin: origin
                )
            )

            #expect(session != nil)
            #expect(session?.configurationError == nil)
            #expect(session?.canPresentAuthorization == true)
        }
    }

    @Test
    func `flow origin must share the authorization navigation controller`() {
        let presenter = UIViewController()
        let origin = UIViewController()
        let presenterNavigationController = UINavigationController(rootViewController: presenter)
        let originNavigationController = UINavigationController(rootViewController: origin)

        let session = ExecutionSessionRegistry().acquire(
            in: ExecutionContext(
                authorizationPresenter: presenter,
                flowOrigin: origin
            )
        )

        guard let error = session?.configurationError else {
            Issue.record("Expected an invalid execution context")
            return
        }
        guard case .invalidConfiguration = error else {
            Issue.record("Expected navigation-controller mismatch")
            return
        }
        withExtendedLifetime((presenterNavigationController, originNavigationController)) {}
    }

    @Test
    func `completion replaces the captured flow without touching an unrelated modal`() async {
        await withVisibleNavigationController { navigationController in
            let predecessor = UIViewController()
            let origin = UIViewController()
            let presenter = UIViewController()
            navigationController.setViewControllers(
                [predecessor, origin, presenter],
                animated: false
            )
            let session = ExecutionSessionRegistry().acquire(
                in: ExecutionContext(
                    authorizationPresenter: presenter,
                    flowOrigin: origin
                )
            )
            let unrelatedController = UIViewController()
            let unrelatedNavigationController = UINavigationController(
                rootViewController: unrelatedController
            )
            navigationController.present(unrelatedNavigationController, animated: false)
            let completion = UIViewController()

            #expect(session?.isPresentationContextAlive == true)
            #expect(!navigationController.isBeingDismissed)

            let didReplace = await session?.replaceCompletion(
                with: Replacement(viewController: completion)
            )

            #expect(didReplace == true)
            #expect(navigationController.viewControllers.count == 2)
            #expect(navigationController.viewControllers[0] === predecessor)
            #expect(navigationController.viewControllers[1] === completion)
            #expect(unrelatedNavigationController.viewControllers == [unrelatedController])
        }
    }

    private func withVisibleNavigationController(
        perform work: (UINavigationController) -> Void
    ) {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let navigationController = UINavigationController()
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        navigationController.loadViewIfNeeded()
        work(navigationController)
        window.isHidden = true
    }

    private func withVisibleNavigationController(
        perform work: (UINavigationController) async -> Void
    ) async {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let navigationController = UINavigationController()
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        navigationController.loadViewIfNeeded()
        await work(navigationController)
        window.isHidden = true
    }
}

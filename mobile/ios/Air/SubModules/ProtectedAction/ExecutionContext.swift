import UIKit

@MainActor
public struct ExecutionContext {
    public let authorizationPresenter: UIViewController
    public let flowOrigin: UIViewController

    public init(
        authorizationPresenter: UIViewController,
        flowOrigin: UIViewController
    ) {
        self.authorizationPresenter = authorizationPresenter
        self.flowOrigin = flowOrigin
    }

    public init(_ viewController: UIViewController) {
        self.init(
            authorizationPresenter: viewController,
            flowOrigin: viewController
        )
    }
}

import UIKit

@MainActor
public struct ExecutionContext {
    public let authorizationPresenter: UIViewController
    public let flowOrigin: UIViewController

    public init(
        authorizationPresenter: UIViewController,
        flowOrigin: UIViewController
    ) {
        self.authorizationPresenter = authorizationPresenter.navigationStackEntry
        self.flowOrigin = flowOrigin.navigationStackEntry
    }

    public init(_ viewController: UIViewController) {
        self.init(
            authorizationPresenter: viewController,
            flowOrigin: viewController
        )
    }
}

private extension UIViewController {
    // A screen embedded in a container is not a navigation stack member itself; its container is.
    var navigationStackEntry: UIViewController {
        guard let navigationController else { return self }
        var entry = self
        while let parent = entry.parent, parent !== navigationController {
            entry = parent
        }
        return entry
    }
}

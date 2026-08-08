import UIKit

@MainActor
public struct Replacement {
    public let viewController: UIViewController
    public let animateAlongside: () -> Void

    public init(
        viewController: UIViewController,
        animateAlongside: @escaping () -> Void = {}
    ) {
        self.viewController = viewController
        self.animateAlongside = animateAlongside
    }
}

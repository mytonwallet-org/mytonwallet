import UIKit

/// A WNavigationController whose root view controller is created lazily on first appearance
/// or when explicitly requested. Used by both compact (tab bar) and large (split) layouts
/// so that optional-tab VCs are not instantiated until needed.
open class AppTabLazyNavigationController: WNavigationController {
    private let makeRootViewController: () -> UIViewController
    private var didInstallRootViewController = false

    public init(makeRootViewController: @escaping () -> UIViewController) {
        self.makeRootViewController = makeRootViewController
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ensureRootViewControllerInstalled()
    }

    public func ensureRootViewControllerInstalled() {
        guard !didInstallRootViewController else { return }
        didInstallRootViewController = true
        viewControllers = [makeRootViewController()]
    }

    public func resetRootViewController() {
        didInstallRootViewController = true
        viewControllers = [makeRootViewController()]
    }

    public func setPreservedViewControllers(_ viewControllers: [UIViewController]) {
        guard !viewControllers.isEmpty else { return }
        didInstallRootViewController = true
        self.viewControllers = viewControllers
    }
}

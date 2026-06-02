import UIKit
import WalletContext

@MainActor
protocol RootContainerLayoutResolving {
    func buildActiveRootViewController() -> UIViewController
}

@MainActor
struct RootContainerLayoutResolver: RootContainerLayoutResolving {
    func buildActiveRootViewController() -> UIViewController {
        StartupTrace.mark("rootContainer.activeRoot.build", details: "layout=adaptive")
        return RootContainerVC(contentViewController: AdaptiveRootViewController())
    }
}

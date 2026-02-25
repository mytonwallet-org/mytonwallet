import UIKit
import UIHome
import WalletContext

@MainActor
protocol RootContainerLayoutResolving {
    func buildActiveRootViewController() -> UIViewController
}

@MainActor
struct RootContainerLayoutResolver: RootContainerLayoutResolving {
    func buildActiveRootViewController() -> UIViewController {
        if shouldUseSplitLayout {
            return RootContainerVC(contentViewController: SplitRootViewController())
        }
        return RootContainerVC(contentViewController: HomeTabBarController())
    }
    
    private var shouldUseSplitLayout: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return false
        }
        let width = UIApplication.shared.sceneKeyWindow?.bounds.width
            ?? UIApplication.shared.anySceneKeyWindow?.bounds.width
            ?? UIScreen.main.bounds.width
        return width >= 700
    }
}

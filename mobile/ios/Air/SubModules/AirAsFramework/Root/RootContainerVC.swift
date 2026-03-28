import UIKit
import UIComponents
import UIInAppBrowser
import WalletContext

@MainActor
final class RootContainerVC: UIViewController, VisibleContentProviding {
    let contentViewController: UIViewController
    var visibleContentProviderViewController: UIViewController { contentViewController }

    private let minimizableSheetContentViewController = MinimizableSheetContentViewController()
    private lazy var sheetContainerViewController: MinimizableSheetContainerViewController = {
        var configuration = MinimizableSheetConfiguration.default
        configuration.minimizedVisibleHeight = 44
        configuration.minimizedCornerRadius = IOS_26_MODE_ENABLED ? 20 : 12
        configuration.expandedCornerRadius = IOS_26_MODE_ENABLED ? 26 : 16
        return MinimizableSheetContainerViewController(
            mainViewController: contentViewController,
            sheetViewController: minimizableSheetContentViewController,
            configuration: configuration
        )
    }()

    init(contentViewController: UIViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        addChild(sheetContainerViewController)
        sheetContainerViewController.view.frame = view.bounds
        sheetContainerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(sheetContainerViewController.view)
        sheetContainerViewController.didMove(toParent: self)
    }
}

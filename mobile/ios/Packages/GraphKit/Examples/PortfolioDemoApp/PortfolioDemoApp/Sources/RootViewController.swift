import UIKit

final class RootViewController: UIViewController {
    private let demoViewController = PortfolioCompositionDemoViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        addChild(demoViewController)
        view.addSubview(demoViewController.view)
        demoViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        demoViewController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        demoViewController.view.frame = view.bounds
    }
}

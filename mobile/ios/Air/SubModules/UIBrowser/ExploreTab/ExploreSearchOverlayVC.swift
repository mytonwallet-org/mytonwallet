import UIKit
import UIComponents
import WalletContext

@MainActor
public final class ExploreSearchOverlayVC: UIViewController {
    private lazy var searchViewController = ExploreTabVC(
        showsSearchBar: true,
        showsLargeTitle: false,
        focusesSearchOnAppearance: true,
        onSearchCancel: { [weak self] in
            self?.dismissOverlay()
        }
    )

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .air.background
        addChild(searchViewController)
        searchViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchViewController.view)
        NSLayoutConstraint.activate([
            searchViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            searchViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        searchViewController.didMove(toParent: self)
    }

    private func dismissOverlay() {
        view.endEditing(true)
        dismiss(animated: true)
    }
}

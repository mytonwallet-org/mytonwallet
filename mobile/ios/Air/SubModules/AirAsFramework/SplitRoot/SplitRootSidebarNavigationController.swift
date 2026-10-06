import UIKit
import UIComponents
import WalletContext

/// Hosting the cover inside the primary column lets UIKit handle floating,
/// hidden and right-to-left sidebars without duplicating their geometry.
@MainActor
final class SplitRootSidebarNavigationController: WNavigationController {
    var onDismissSearch: (() -> Void)?
    private(set) var isSearchVisible = false
    private let searchCover = UIButton(type: .custom)
    private var visibilityTransitionID: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        searchCover.translatesAutoresizingMaskIntoConstraints = false
        searchCover.isHidden = true
        searchCover.accessibilityLabel = lang("Close")
        searchCover.accessibilityIdentifier = "SearchSidebarDismissOverlay"
        searchCover.addAction(UIAction { [weak self] _ in
            self?.onDismissSearch?()
        }, for: .touchUpInside)
        view.addSubview(searchCover)
        NSLayoutConstraint.activate([
            searchCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchCover.topAnchor.constraint(equalTo: view.topAnchor),
            searchCover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(searchCover)
    }

    func setSearchVisible(_ isVisible: Bool, coordinator: (any UIViewControllerTransitionCoordinator)?) {
        loadViewIfNeeded()
        guard isVisible != isSearchVisible || coordinator == nil else { return }
        let sourceIsVisible = isSearchVisible
        isSearchVisible = isVisible
        let transitionID = UUID()
        visibilityTransitionID = transitionID

        // Animate the color, not the control's alpha: even a transparent cover
        // must block touches during the first and last frames of a transition.
        setSidebarCovered(sourceIsVisible || isVisible)
        let animations = { [weak self] in
            self?.searchCover.backgroundColor = .air.background.withAlphaComponent(isVisible ? 0.6 : 0)
        }
        let finish = { [weak self] (isCancelled: Bool) in
            guard let self, visibilityTransitionID == transitionID else { return }
            visibilityTransitionID = nil
            isSearchVisible = isCancelled ? sourceIsVisible : isVisible
            searchCover.backgroundColor = .air.background.withAlphaComponent(isSearchVisible ? 0.6 : 0)
            setSidebarCovered(isSearchVisible)
        }
        if let coordinator, coordinator.animateAlongsideTransition(in: view, animation: { _ in
            animations()
        }, completion: { context in
            finish(context.isCancelled)
        }) {
            return
        }
        UIView.performWithoutAnimation {
            animations()
            finish(false)
        }
    }

    private func setSidebarCovered(_ isCovered: Bool) {
        searchCover.isHidden = !isCovered
        topViewController?.view.accessibilityElementsHidden = isCovered
        navigationBar.accessibilityElementsHidden = isCovered
        view.bringSubviewToFront(searchCover)
    }
}

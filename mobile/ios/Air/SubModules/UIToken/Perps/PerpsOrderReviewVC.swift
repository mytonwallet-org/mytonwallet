import SwiftUI
import UIKit
import UIComponents
import WalletContext

@MainActor
public final class PerpsOrderReviewVC: WViewController {
    private let state: PerpsOrderReviewState

    public init(data: PerpsOrderReviewDisplayData, onConfirm: @escaping (PerpsOrderReviewRequest) -> Void) {
        state = PerpsOrderReviewState(data: data, onConfirm: onConfirm)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Updates can refresh or invalidate the quote. While confirmation is pending, echo its request.
    /// The adapter remains responsible for quote expiry, authentication, execution, and navigation.
    @discardableResult
    public func update(data: PerpsOrderReviewDisplayData, for request: PerpsOrderReviewRequest? = nil) -> Bool {
        state.update(data: data, for: request)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = state.data.mode.title
        view.backgroundColor = .air.headerBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.closeReview()
        })
        let content = addHostingController(PerpsOrderReviewView(state: state))
        let footer = addHostingController(PerpsOrderReviewFooter(state: state))
        AssetDetailsView.prepare(content)
        AssetDetailsView.prepare(footer)
        AssetDetailsView(sections: [content.view], footer: footer.view, background: .air.headerBackground).install(in: view)
        addCustomNavigationBarBackground(color: .air.headerBackground)
    }

    func closeReview() {
        if let navigationController {
            navigationController.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

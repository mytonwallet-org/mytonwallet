import SwiftUI
import UIKit
import UIComponents
import WalletContext

@MainActor
public final class PerpsOrderReviewVC: WViewController {
    private let state: PerpsOrderReviewState

    public init(data: PerpsOrderReviewDisplayData, onSelectPayment: ((PerpsOrderReviewRequest) -> Void)? = nil,
                onConfirm: @escaping (PerpsOrderReviewRequest) -> Void) {
        state = PerpsOrderReviewState(data: data, onSelectPayment: onSelectPayment, onConfirm: onConfirm)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Updates can refresh/invalidate the quote. While confirmation is pending, echo its request.
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
        PerpsSheetContentView.prepare(content)
        PerpsSheetContentView.prepare(footer)
        let layout = PerpsSheetContentView(content: content.view, footer: footer.view, footerBackground: .air.headerBackground)
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
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

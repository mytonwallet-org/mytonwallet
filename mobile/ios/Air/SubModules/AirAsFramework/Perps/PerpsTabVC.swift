import SwiftNavigation
import UIKit
import UIAssets
import UIComponents
import WalletContext
import WalletCore

/// The root follows the selected wallet; pushed flows retain their original account context.
@MainActor
final class PerpsTabVC: WViewController {
    private let context: AccountContext
    private var observation: ObserveToken?
    private var coordinator: PerpsCoordinator?
    private var content: UIViewController?
    private var pagingBackgroundColor: UIColor?
    private(set) var accountId: String?

    init(accountContext: AccountContext = AccountContext(source: .current)) {
        context = accountContext
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Futures")
        view.backgroundColor = pagingBackgroundColor ?? .air.groupedBackground
        observation = observe { [weak self] in
            guard let self else { return }
            showAccount(context.account.id)
        }
    }

    func showPosition(_ id: String) {
        loadViewIfNeeded()
        if let content { coordinator?.showPosition(id, from: content) }
    }

    func showAllPositions() {
        loadViewIfNeeded()
        coordinator?.showAllPositions()
    }

    override func scrollToTop(animated: Bool) {
        (content as? WViewController)?.scrollToTop(animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateContentInsets()
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateContentInsets()
    }

    private func updateContentInsets() {
        (content as? PerpsHomeVC)?.updateScrollInsets(view.safeAreaInsets, layoutMargins: view.layoutMargins)
    }

    private func showAccount(_ id: String) {
        guard accountId != id else { return }
        accountId = id
        if let content {
            content.willMove(toParent: nil)
            content.view.removeFromSuperview()
            content.removeFromParent()
        }
        let coordinator = PerpsCoordinator(accountId: id)
        self.coordinator = coordinator
        let content = coordinator.makeHome()
        self.content = content
        addChild(content)
        // Replacement children can lose their inherited safe area in a retained
        // pager page. Keep the full viewport and supply the stable root's insets.
        view.addStretchedToBounds(subview: content.view)
        content.didMove(toParent: self)
        setPagingBackgroundColor(pagingBackgroundColor)
        updateContentInsets()
    }
}

extension PerpsTabVC: WPagingBackgroundTinting {
    func setPagingBackgroundColor(_ color: UIColor?) {
        pagingBackgroundColor = color
        viewIfLoaded?.backgroundColor = color ?? .air.groupedBackground
        content?.viewIfLoaded?.backgroundColor = color ?? .air.groupedBackground
    }
}

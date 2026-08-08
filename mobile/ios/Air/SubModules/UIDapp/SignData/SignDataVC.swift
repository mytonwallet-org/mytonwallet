
import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import WalletCore
import WalletContext

class SignDataVC: WViewController, UISheetPresentationControllerDelegate {
    
    var update: ApiUpdate.DappSignData?
    var onCancel: (() -> ())?
    
    var placeholderAccountId: String?
    
    var hostingController: UIHostingController<SignDataViewOrPlaceholder>?
    
    @AccountContext var account: MAccount
    
    init(
        update: ApiUpdate.DappSignData,
        onCancel: @escaping () -> ()
    ) {
        self._account = AccountContext(accountId: update.accountId)
        self.update = update
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    
    init(placeholderAccountId: String?) {
        self._account = AccountContext(accountId: placeholderAccountId)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func replacePlaceholder(
        update: ApiUpdate.DappSignData,
        onCancel: @escaping () -> ()
    ) {
        self.update = update
        self.onCancel = onCancel
        withAnimation {
            self.$account.accountId = update.accountId
            self.hostingController?.rootView = makeView()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        navigationItem.title = lang("Confirm Actions", arg1: 1)
        addCloseNavigationItemIfNeeded()
        // Route the close "X" through cancellation so the dapp is notified (otherwise it waits forever).
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?._onCancel()
            })
        }

        hostingController = addHostingController(makeView(), constraints: .fill)

        updateTheme()

        // The sheet (and its swipe-to-dismiss) belongs to the enclosing nav controller, not this VC.
        (navigationController?.sheetPresentationController ?? sheetPresentationController)?.delegate = self
    }
    
    private func makeView() -> SignDataViewOrPlaceholder {
        SignDataViewOrPlaceholder(
            update: update,
            accountContext: _account,
            onConfirm: { [weak self] in self?._onConfirm() },
            onCancel: { [weak self] in self?._onCancel() },
        )
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }

    func _onConfirm() {
        guard let update else { return }
        let protectedAction = ProtectedAction.signData(
            account: account,
            accountContext: _account,
            update: update,
            onCommitted: { [weak self] in
                self?.onCancel = nil
                self?.dismiss(animated: true)
            }
        )
        Task {
            _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
        }
    }

    func _onCancel() {
        // `onCancel` rejects the dapp request; it's nil for the wake placeholder (no request yet),
        // in which case we still dismiss so the Cancel button / swipe / X always close the modal.
        onCancel?()
        onCancel = nil
        navigationController?.presentingViewController?.dismiss(animated: true)
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        _onCancel()
    }
}


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
            self.updateNavigationHeader()
            self.hostingController?.rootView = makeView()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        updateNavigationHeader()

        hostingController = addHostingController(makeView(), constraints: .fill)

        updateTheme()

        // The sheet (and its swipe-to-dismiss) belongs to the enclosing nav controller, not this VC.
        (navigationController?.sheetPresentationController ?? sheetPresentationController)?.delegate = self
    }
    
    private func updateNavigationHeader() {
        navigationItem.titleView = DappNavigationHeader(accountContext: _account, dapp: update?.dapp)
        navigationItem.backButtonDisplayMode = .minimal
    }

    private func makeView() -> SignDataViewOrPlaceholder {
        SignDataViewOrPlaceholder(
            update: update,
            accountContext: _account,
            onConfirm: { [weak self] in await self?._onConfirm() },
            onCancel: { [weak self] in self?._onCancel() },
        )
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }

    func _onConfirm() async {
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
        _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
    }

    func _onCancel() {
        // `onCancel` rejects the dapp request; it's nil for the wake placeholder (no request yet),
        // in which case we still dismiss so Cancel and swipe always close the modal.
        onCancel?()
        onCancel = nil
        navigationController?.presentingViewController?.dismiss(animated: true)
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        _onCancel()
    }
}

#if DEBUG
extension SignDataVC {
    static func presentationFixture(update: ApiUpdate.DappSignData?, account: MAccount, onCancel: @escaping () -> Void = {}) -> SignDataVC {
        let viewController = update.map { SignDataVC(update: $0, onCancel: onCancel) }
            ?? SignDataVC(placeholderAccountId: account.id)
        viewController._account = AccountContext(source: .constant(account))
        return viewController
    }
}
#endif

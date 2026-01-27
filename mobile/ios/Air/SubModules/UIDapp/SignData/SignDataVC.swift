
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

class SignDataVC: WViewController, UISheetPresentationControllerDelegate {
    
    var update: ApiUpdate.DappSignData?
    var onConfirm: ((String?) -> ())?
    var onCancel: (() -> ())?
    
    var placeholderAccountId: String?
    
    var hostingController: UIHostingController<SignDataViewOrPlaceholder>?
    
    @AccountContext var account: MAccount
    
    init(
        update: ApiUpdate.DappSignData,
        onConfirm: @escaping (String?) -> (),
        onCancel: @escaping () -> ()
    ) {
        self._account = AccountContext(accountId: update.accountId)
        self.update = update
        self.onConfirm = onConfirm
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
        onConfirm: @escaping (String?) -> (),
        onCancel: @escaping () -> ()
    ) {
        self.update = update
        self.onConfirm = onConfirm
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

        hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
        
        sheetPresentationController?.delegate = self
    }
    
    private func makeView() -> SignDataViewOrPlaceholder {
        if let update {
            return SignDataViewOrPlaceholder(content: .signData(SignDataView(
                update: update,
                accountContext: _account,
                onConfirm: { [weak self] in self?._onConfirm() },
                onCancel: { [weak self] in self?._onCancel() },
            )))
        } else {
            return SignDataViewOrPlaceholder(content: .placeholder(TonConnectPlaceholder(
                account: account,
                connectionType: .signData,
            )))
        }
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }

    func _onConfirm() {
        if let update, let onConfirm {
            UnlockVC.presentAuth(
                on: self,
                title: lang("Sign Data"),
                subtitle: update.dapp.name,
                onDone: { passcode in
                    onConfirm(passcode)
                    self.onConfirm = nil
                    self.onCancel = nil
                    self.dismiss(animated: true)
                },
                cancellable: true
            )
        }
    }

    func _onCancel() {
        if let onCancel {
            navigationController?.presentingViewController?.dismiss(animated: true)
            onCancel()
            self.onConfirm = nil
            self.onCancel = nil
        }
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        _onCancel()
    }
}


import SwiftUI
import UIKit
import Ledger
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

public class SendDappVC: WViewController, UISheetPresentationControllerDelegate {
    
    var request: ApiUpdate.DappSendTransactions?
    var onConfirm: ((String?) -> ())?
    var onCancel: (() -> ())?
    
    var placeholderAccountId: String?
    
    var hostingController: UIHostingController<SendDappViewOrPlaceholder>?
    private var sendButtonObserver: ObserveToken?
    
    @AccountContext(source: .current) var account: MAccount
    
    public init(
        request: ApiUpdate.DappSendTransactions,
        onConfirm: @escaping (String?) -> (),
        onCancel: @escaping () -> (),
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    
    init(placeholderAccountId: String?) {
        self.placeholderAccountId = placeholderAccountId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func replacePlaceholder(
        request: ApiUpdate.DappSendTransactions,
        onConfirm: @escaping (String?) -> (),
        onCancel: @escaping () -> (),
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        navigationItem.title = makeNavigationTitle()
        withAnimation {
            self.hostingController?.rootView = makeView()
        }
        updateSendButtonState(animated: true)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupObservers()
    }
    
    private lazy var cancelButton = {
        let btn = WButton(style: .secondary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(lang("Cancel"), for: .normal)
        btn.addTarget(self, action: #selector(_onCancel), for: .touchUpInside)
        return btn
    }()
    
    private lazy var sendButton = {
        let btn = WButton(style: .primary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(lang("Send"), for: .normal)
        btn.addTarget(self, action: #selector(onSend), for: .touchUpInside)
        return btn
    }()

    private lazy var errorLabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14, weight: .regular)
        lbl.textAlignment = .center
        lbl.textColor = .air.error
        lbl.numberOfLines = 2
        lbl.isHidden = true
        return lbl
    }()
    
    private lazy var contentView = {
        var constraints = [NSLayoutConstraint]()
        
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        
        v.addSubview(errorLabel)
        v.addSubview(cancelButton)
        v.addSubview(sendButton)
        constraints.append(contentsOf: [
            sendButton.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -16),
            sendButton.topAnchor.constraint(greaterThanOrEqualTo: errorLabel.bottomAnchor, constant: 12),
            sendButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),
            sendButton.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
            cancelButton.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: sendButton.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: sendButton.bottomAnchor),
            cancelButton.widthAnchor.constraint(equalTo: sendButton.widthAnchor),
            errorLabel.topAnchor.constraint(greaterThanOrEqualTo: v.topAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
        ])
        
        NSLayoutConstraint.activate(constraints)
        
        return v
    }()
    
    private func setupViews() {
        navigationItem.title = makeNavigationTitle()
        addCloseNavigationItemIfNeeded()

        hostingController = addHostingController(makeView(), constraints: .fill)
        
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 136),
            contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).withPriority(.init(500)),
            contentView.leftAnchor.constraint(equalTo: view.leftAnchor),
            contentView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        updateTheme()
        
        updateSendButtonState()
        
        sheetPresentationController?.delegate = self
    }

    private func setupObservers() {
        sendButtonObserver = observe { [weak self] in
            guard let self else { return }
            _ = account.id
            _ = $account.balances
            updateSendButtonState()
        }
    }

    private func updateSendButtonState(animated: Bool = false) {
        let insufficientTokens: String? = if let request {
            request.insufficientTokens(accountContext: $account)
        } else {
            nil
        }
        errorLabel.text = insufficientTokens.map { lang("Not Enough %symbol%", arg1: $0) }
        errorLabel.isHidden = insufficientTokens == nil

        let isEnabled = if let request {
            !request.combinedInfo.isScam && insufficientTokens == nil
        } else {
            false
        }
        guard sendButton.isEnabled != isEnabled else { return }
        if animated {
            UIView.animate(withDuration: 0.3) {
                self.sendButton.isEnabled = isEnabled
            }
        } else {
            sendButton.isEnabled = isEnabled
        }
    }
    
    private func makeView() -> SendDappViewOrPlaceholder {
        if let request {
            return SendDappViewOrPlaceholder(content: .sendDapp(SendDappContentView(
                accountContext: _account,
                request: request,
                operationChain: request.operationChain,
                onShowDetail: showDetail(_:),
            )))
        } else {
            return SendDappViewOrPlaceholder(content: .placeholder(TonConnectPlaceholder(
                account: account,
                connectionType: .sendTransaction,
            )))
        }
    }
    
    private func showDetail(_ tx: ApiDappTransfer) {
        guard let request else { return }
        navigationController?.pushViewController(
            DappSendTransactionDetailVC(
                accountContext: _account,
                message: tx,
                chain: request.operationChain
            ),
            animated: true
        )
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }

    private func makeNavigationTitle() -> String {
        guard let request else {
            return lang("Confirm Action")
        }

        if request.transactions.count == 1, request.transactions.first?.isNftTransferPayload == true {
            return lang("Send NFT")
        }

        if request.transactions.count > 1 {
            return lang("$classic_confirm_actions")
        }

        return lang("Confirm Action")
    }
    
    @objc func onSend() {
        if account.isHardware {
            Task {
                await confirmLedger()
            }
        } else {
            confirmMnemonic()
        }
    }
    
    private func confirmMnemonic() {
        guard let request else { return }
        UnlockVC.presentAuth(
            on: self,
            title: lang("Confirm Sending"),
            subtitle: request.dapp.url,
            onDone: { [weak self] passcode in
                self?._onConfirm(passcode)
                self?.dismiss(animated: true)
            },
            cancellable: true
        )
    }
    
    private func confirmLedger() async {
        guard let request else { return }
        
        let signModel = await LedgerSignModel(
            accountId: account.id,
            fromAddress: account.firstAddress,
            signData: .signDappTransfers(update: request)
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: EmptyView()
        )
        vc.onDone = { vc in
            self._onConfirm("ledger")
            self.dismiss(animated: true, completion: {
                self.presentingViewController?.dismiss(animated: true)
            })
        }
        vc.onCancel = { vc in
            self._onCancel()
            self.dismiss(animated: true, completion: {
                self.presentingViewController?.dismiss(animated: true)
            })
        }
        present(WNavigationController(rootViewController: vc), animated: true)
    }
    
    func _onConfirm(_ password: String?) {
        onConfirm?(password)
        onConfirm = nil
        onCancel = nil
    }
    
    @objc func _onCancel() {
        if let onCancel {
            onCancel()
            onConfirm = nil
            self.onCancel = nil
            self.dismiss(animated: true)
        }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        _onCancel()
    }
}


#if DEBUG
//@available(iOS 18, *)
//#Preview {
//    let activity1 = ApiActivity.transaction(ApiTransactionActivity(id: "d", kind: "transaction", timestamp: 0, amount: -123456789, fromAddress: "foo", toAddress: "bar", comment: nil, encryptedComment: nil, fee: 12345, slug: TON_USDT_SLUG, isIncoming: false, normalizedAddress: nil, externalMsgHashNorm: nil, shouldHide: nil, type: nil, metadata: nil, nft: nil, isPending: nil))
//    let activity2 = ApiActivity.transaction(ApiTransactionActivity(id: "d2", kind: "transaction", timestamp: 0, amount: -456789, fromAddress: "foo", toAddress: "bar", comment: nil, encryptedComment: nil, fee: 12345, slug: TON_USDT_SLUG, isIncoming: false, normalizedAddress: nil, externalMsgHashNorm: nil, shouldHide: nil, type: .callContract, metadata: nil, nft: nil, isPending: nil))
//
//    let request = ApiUpdate.DappSendTransactions(
//        promiseId: "",
//        accountId: "",
//        dapp: ApiDapp(url: "https://dedust.io", name: "Dedust", iconUrl: "https://files.readme.io/681e2e6-dedust_1.png", manifestUrl: "", connectedAt: nil, isUrlEnsured: nil, sse: nil),
//        transactions: [
//            ApiDappTransfer(
//                toAddress: "tkffadjklfadsjfalkdjfd;alljfdasfo",
//                amount: 123456789,
//                rawPayload: "adfsljhfdajlhfdasjkfhkjlhfdjkashfjadhkjdashfkjhafjfadshljkfahdsfadsjk",
//                isScam: false,
//                isDangerous: true,
//                normalizedAddress: "bar",
//                displayedToAddress: "fkkfkf",
//                networkFee: 132456
//            ),
//            ApiDappTransfer(
//                toAddress: "tkffadjklfadsjfalkdjfd;alljfdasfo",
//                amount: 123456789,
//                rawPayload: "adfsljhfdajlhfdasjkfhkjlhfdjkashfjadhkjdashfkjhafjfadshljkfahdsfadsjk",
//                isScam: true,
//                isDangerous: true,
//                normalizedAddress: "bar",
//                displayedToAddress: "fkkfkf",
//                networkFee: 132456
//            ),
//        ],
//        emulation: Emulation(
//            activities: [activity1, activity2],
//            realFee: 123456
//        )
//    )
//    
//    let vc = SendDappVC(request: request, onConfirm: { _ in })
//    let nc = WNavigationController(rootViewController: vc)
//    nc
//}
#endif

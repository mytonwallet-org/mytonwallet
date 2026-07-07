
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

private let NOT_RESPONDING_DELAY: TimeInterval = 7

public class SendDappVC: WViewController, UISheetPresentationControllerDelegate {

    var request: ApiUpdate.DappSendTransactions?
    var onCancel: (() -> ())?

    var placeholderAccountId: String?
    private var isWaitingForRequest = false
    private var returnUrl: String?
    private var notRespondingWorkItem: DispatchWorkItem?

    var hostingController: UIHostingController<SendDappViewOrPlaceholder>?
    private var sendButtonObserver: ObserveToken?
    
    @AccountContext(source: .current) var account: MAccount
    
    public init(
        request: ApiUpdate.DappSendTransactions,
        onCancel: @escaping () -> (),
    ) {
        self.request = request
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    
    init(placeholderAccountId: String?, isWaitingForRequest: Bool = false, returnUrl: String? = nil) {
        self.placeholderAccountId = placeholderAccountId
        self.isWaitingForRequest = isWaitingForRequest
        self.returnUrl = returnUrl
        super.init(nibName: nil, bundle: nil)
    }

    isolated deinit {
        notRespondingWorkItem?.cancel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func replacePlaceholder(
        request: ApiUpdate.DappSendTransactions,
        onCancel: @escaping () -> (),
    ) {
        cancelNotResponding()
        self.request = request
        self.onCancel = onCancel
        navigationItem.title = makeNavigationTitle()
        withAnimation {
            self.hostingController?.rootView = makeView()
            self.bottomPanel.isHidden = false
        }
        updateSendButtonState(animated: true)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupObservers()
        scheduleNotRespondingIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelNotResponding()
    }

    // A placeholder opened by a wake deeplink: warn if the request event never arrives.
    private func scheduleNotRespondingIfNeeded() {
        guard isWaitingForRequest else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.showNotResponding()
        }
        notRespondingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NOT_RESPONDING_DELAY, execute: workItem)
    }

    private func cancelNotResponding() {
        notRespondingWorkItem?.cancel()
        notRespondingWorkItem = nil
    }

    private func showNotResponding() {
        let url = returnUrl
        showAlert(
            title: lang("Dapp Not Responding"),
            text: lang("You may need to reconnect your wallet from the dapp if this keeps happening."),
            button: lang("OK"),
            buttonPressed: { [weak self] in
                if let url {
                    self?.dismiss(animated: true)
                    TonConnect.shared.openReturnUrl(url)
                }
            },
            secondaryButton: url != nil ? lang("Cancel") : nil
        )
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
    
    private lazy var bottomPanel = {
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
        // Route the close "X" through cancellation so the dapp is notified (otherwise it waits forever).
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?._onCancel()
            })
        }

        hostingController = addHostingController(makeView(), constraints: .fill)

        view.addSubview(bottomPanel)
        NSLayoutConstraint.activate([
            bottomPanel.heightAnchor.constraint(equalToConstant: 136),
            bottomPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).withPriority(.init(500)),
            bottomPanel.leftAnchor.constraint(equalTo: view.leftAnchor),
            bottomPanel.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        bottomPanel.isHidden = request == nil

        updateTheme()        
        updateSendButtonState()

        // This VC is the root of a presented navigation controller, so the sheet (and its swipe-to-dismiss)
        // belongs to the nav controller — observe that one, otherwise interactive dismissal isn't caught.
        (navigationController?.sheetPresentationController ?? sheetPresentationController)?.delegate = self
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
            canSend(request: request, insufficientTokens: insufficientTokens)
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

    private func canSend(request: ApiUpdate.DappSendTransactions, insufficientTokens: String?) -> Bool {
        !request.combinedInfo.isScam && insufficientTokens == nil
    }
    
    private func makeView() -> SendDappViewOrPlaceholder {
        SendDappViewOrPlaceholder(
            accountContext: _account,
            request: request,
            onShowDetail: showDetail(_:),
        )
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
        guard let request else { return }
        guard canSend(request: request, insufficientTokens: request.insufficientTokens(accountContext: $account)) else { return }
        submit(request: request)
    }

    private func submit(request: ApiUpdate.DappSendTransactions) {
        Task {
            do {
                _ = try await AppActions.authorizeProtectedAction(
                    on: self,
                    account: account,
                    title: lang("Confirm Sending"),
                    headerView: DappHeaderView(dapp: request.dapp, accountContext: _account),
                    passwordAction: { password in
                        try await TonConnect.shared.submitSendTransactions(
                            request: request,
                            password: password
                        )
                    },
                    ledgerSignData: {
                        .signDappTransfers(update: request)
                    },
                    ledgerFromAddress: account.getAddress(chain: request.operationChain),
                    mfaTitle: lang("Confirm Sending")
                )
                finishConfirm()
            } catch is CancellationError {
            } catch {
                showAlert(error: error)
            }
        }
    }
    
    private func finishConfirm() {
        onCancel = nil
        dismiss(animated: true)
    }
    
    @objc func _onCancel() {
        // `onCancel` rejects the dapp request; it's nil for the wake placeholder (no request yet),
        // in which case we still dismiss so the Cancel button / swipe / X always close the modal.
        onCancel?()
        onCancel = nil
        dismiss(animated: true)
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        _onCancel()
    }
}


#if DEBUG

@available(iOS 18, *)
private enum SendDappPreview {

    static let dapp = ApiDapp(
        url: "https://dedust.io",
        name: "Dedust",
        iconUrl: "https://files.readme.io/681e2e6-dedust_1.png",
        manifestUrl: "",
        connectedAt: nil,
        urlTrustStatus: nil,
        sse: nil
    )

    static let transfer1 = ApiDappTransfer(
        toAddress: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs",
        amount: 123456789,
        rawPayload: "adfsljhfdajlhfdasjkfhkjlhfdjkashfjadhkjdashfkjhafjfadshljkfahdsfadsjk",
        isScam: false,
        isDangerous: true,
        normalizedAddress: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs",
        displayedToAddress: "EQCxE6...sDs",
        networkFee: 132456
    )

    static let transfer2 = ApiDappTransfer(
        toAddress: "EQDtFpEwcFAEcRe5mLVh2N6C0x-_hJEM7W61_JLnSF74p4q2",
        amount: 456789000,
        rawPayload: "bbbsljhfdajlhfdasjkfhkjlhfdjkashfjadhkjdashfkjhafjfadshljkfahdsfadsjk",
        isScam: true,
        isDangerous: true,
        normalizedAddress: "EQDtFpEwcFAEcRe5mLVh2N6C0x-_hJEM7W61_JLnSF74p4q2",
        displayedToAddress: "EQDtFp...q2",
        networkFee: 98765
    )

    static let activity1 = ApiActivity.transaction(ApiTransactionActivity(
        id: "d",
        kind: "transaction",
        externalMsgHashNorm: nil,
        timestamp: 0,
        amount: -123456789,
        fromAddress: "foo",
        toAddress: "bar",
        comment: nil,
        encryptedComment: nil,
        fee: 12345,
        slug: TON_USDT_SLUG,
        isIncoming: false,
        normalizedAddress: nil,
        type: nil,
        metadata: nil,
        nft: nil,
        status: .confirmed
    ))

    static let activity2 = ApiActivity.transaction(ApiTransactionActivity(
        id: "d2",
        kind: "transaction",
        externalMsgHashNorm: nil,
        timestamp: 0,
        amount: -456789,
        fromAddress: "foo",
        toAddress: "bar",
        comment: nil,
        encryptedComment: nil,
        fee: 12345,
        slug: TON_USDT_SLUG,
        isIncoming: false,
        normalizedAddress: nil,
        type: .callContract,
        metadata: nil,
        nft: nil,
        status: .confirmed
    ))

    static func makeRequest(transfers: [ApiDappTransfer], activities: [ApiActivity]) -> ApiUpdate.DappSendTransactions {
        ApiUpdate.DappSendTransactions(
            promiseId: "",
            accountId: "",
            dapp: dapp,
            operationChain: .ton,
            transactions: transfers,
            emulation: Emulation(activities: activities, realFee: 123456),
            shouldHideTransfers: nil
        )
    }
}

@available(iOS 18, *)
private class SheetPreviewContainer: UIViewController {
    private let content: UIViewController

    init(_ vc: UIViewController) {
        content = WNavigationController(rootViewController: vc)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard presentedViewController == nil else { return }
        if let sheet = content.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(content, animated: false)
    }
}

// MARK: - Preview:

// Preview has quirks: it keeps the previous preview content after switching
// So here is a dirty solution: Uncomment the variant you need, keep the others commented out.

//@available(iOS 18, *)
//#Preview("Placeholder") {
//    SheetPreviewContainer(
//        SendDappVC(placeholderAccountId: nil, isWaitingForRequest: false)
//    )
//}

@available(iOS 18, *)
#Preview("Send — Single Transaction") {
    let request = SendDappPreview.makeRequest(
        transfers: [SendDappPreview.transfer1],
        activities: [SendDappPreview.activity1]
    )
    return SheetPreviewContainer(SendDappVC(request: request, onCancel: {}))
}

//@available(iOS 18, *)
//#Preview("Send — Multiple Transactions") {
//    let request = SendDappPreview.makeRequest(
//        transfers: [SendDappPreview.transfer1, SendDappPreview.transfer2],
//        activities: [SendDappPreview.activity1, SendDappPreview.activity2]
//    )
//    return SheetPreviewContainer(SendDappVC(request: request, onCancel: {}))
//}

#endif

import Perception
import SwiftNavigation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

final class WalletConnectPaySignTransactionVC: WViewController, UISheetPresentationControllerDelegate {
    private let request: ApiUpdate.WalletConnectPaySignTransaction
    private let dappRequest: ApiUpdate.DappSendTransactions
    private let onSubmit: (ApiUpdate.WalletConnectPaySignTransaction, String?) async throws -> ApiSignDappTransfersResult
    private var onCancel: (() -> Void)?
    private var isWaitingForNextStep = false
    private var sendButtonObserver: ObserveToken?

    private var hostingController: UIHostingController<WalletConnectPaySignTransactionView>?

    @AccountContext var account: MAccount

    init(
        request: ApiUpdate.WalletConnectPaySignTransaction,
        onSubmit: @escaping (ApiUpdate.WalletConnectPaySignTransaction, String?) async throws -> ApiSignDappTransfersResult,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.dappRequest = request.dappRequest
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self._account = AccountContext(accountId: request.accountId)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupObservers()
    }

    private lazy var cancelButton = {
        let btn = WButton(style: .secondary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(lang("Cancel"), for: .normal)
        btn.addTarget(self, action: #selector(onCancelPressed), for: .touchUpInside)
        return btn
    }()

    private lazy var sendButton = {
        let btn = WButton(style: .primary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(request.isSignOnly ? lang("Sign") : lang("Send"), for: .normal)
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
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(errorLabel)
        v.addSubview(cancelButton)
        v.addSubview(sendButton)
        NSLayoutConstraint.activate([
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
        return v
    }()

    private func setupViews() {
        navigationItem.title = request.merchant.name
        addCloseNavigationItemIfNeeded()
        if navigationItem.rightBarButtonItem != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.onCancelPressed()
            })
        }

        hostingController = addHostingController(makeView(), constraints: .fill)

        view.addSubview(contentView)

        view.backgroundColor = .air.sheetBackground

        addCustomNavigationBarBackground(color: .air.sheetBackground)
        
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 136),
            contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).withPriority(.init(500)),
            contentView.leftAnchor.constraint(equalTo: view.leftAnchor),
            contentView.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])
        updateSendButtonState()
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

    private func makeView() -> WalletConnectPaySignTransactionView {
        WalletConnectPaySignTransactionView(
            accountContext: _account,
            request: request,
            onShowTransferInfo: { [weak self] in self?.showTransferInfo() }
        )
    }

    private func updateSendButtonState() {
        guard !isWaitingForNextStep else {
            sendButton.isEnabled = false
            cancelButton.isEnabled = false
            return
        }
        let insufficientTokens = dappRequest.insufficientTokens(accountContext: $account)
        errorLabel.text = insufficientTokens.map { lang("Not Enough %symbol%", arg1: $0) }
        errorLabel.isHidden = insufficientTokens == nil
        sendButton.isEnabled = canSend(insufficientTokens: insufficientTokens)
    }

    private func canSend(insufficientTokens: String?) -> Bool {
        insufficientTokens == nil
    }

    @objc private func onSend() {
        guard !isWaitingForNextStep else { return }
        guard canSend(insufficientTokens: dappRequest.insufficientTokens(accountContext: $account)) else { return }
        submit()
    }

    private func submit() {
        Task {
            do {
                _ = try await AppActions.authorizeProtectedAction(
                    on: self,
                    account: account,
                    title: lang("Confirm Sending"),
                    headerView: WalletConnectPayAuthHeaderView(
                        merchant: request.merchant,
                        paymentContext: WalletConnectPayPaymentContext(
                            paymentInfo: request.paymentInfo,
                            paymentOption: request.paymentOption
                        ),
                        accountContext: _account
                    ),
                    passwordAction: { password in
                        try await self.onSubmit(self.request, password)
                    },
                    completionBehavior: .keepAuthForReplacement,
                    prefersNavigationTitleWithCustomHeader: true,
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
        isWaitingForNextStep = true
        sendButton.showLoading = true
        updateSendButtonState()
        navigationItem.rightBarButtonItem?.isEnabled = false
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
    }

    @objc private func onCancelPressed() {
        onCancel?()
        onCancel = nil
    }

    private func showTransferInfo() {
        let transfers = request.visibleTransfers
        guard !transfers.isEmpty else { return }
        navigationController?.pushViewController(
            WalletConnectPayTransferInfoVC(transfers: transfers, chain: request.operationChain),
            animated: true
        )
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onCancelPressed()
    }
}

private extension ApiUpdate.WalletConnectPaySignTransaction {
    var visibleTransfers: [ApiDappTransfer] {
        guard shouldHideTransfers != true else {
            return []
        }

        return transactions.filter { !$0.isPlaceholderWalletConnectPayTransfer }
    }
}

private extension ApiDappTransfer {
    var isPlaceholderWalletConnectPayTransfer: Bool {
        toAddress.isEmpty
            && normalizedAddress.isEmpty
            && displayedToAddress.isEmpty
            && amount == 0
            && networkFee == 0
            && payload == nil
            && rawPayload?.isEmpty == false
    }
}

private struct WalletConnectPaySignTransactionView: View {
    var accountContext: AccountContext
    var request: ApiUpdate.WalletConnectPaySignTransaction
    var onShowTransferInfo: () -> Void

    var body: some View {
        InsetList(topPadding: 24) {
            WalletConnectPayPaymentHeaderView(
                merchant: request.merchant,
                paymentInfo: request.paymentInfo
            )
            .padding(.horizontal, 16)

            WalletConnectPayConfirmationSummarySections(
                accountContext: accountContext,
                paymentOption: request.paymentOption
            )

            if !request.visibleTransfers.isEmpty {
                WalletConnectPayTransferInfoRow(action: onShowTransferInfo)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 80)
        }
    }
}

private final class WalletConnectPayTransferInfoVC: WViewController {
    private let transfers: [ApiDappTransfer]
    private let chain: ApiChain
    private var hostingController: UIHostingController<WalletConnectPayTransferInfoView>?

    init(transfers: [ApiDappTransfer], chain: ApiChain) {
        self.transfers = transfers
        self.chain = chain
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = lang("Transfer Info")
        hostingController = addHostingController(makeView(), constraints: .fill)
        addCustomNavigationBarBackground(color: .air.sheetBackground)
        view.backgroundColor = .air.sheetBackground
    }

    private func makeView() -> WalletConnectPayTransferInfoView {
        WalletConnectPayTransferInfoView(transfers: transfers, chain: chain)
    }
}

private struct WalletConnectPayTransferInfoView: View {
    var transfers: [ApiDappTransfer]
    var chain: ApiChain

    var body: some View {
        InsetList(topPadding: 16) {
            InsetSection {
                ForEach(transfers, id: \.self) { transfer in
                    WalletConnectPayTransferRow(
                        transfer: transfer,
                        chain: chain
                    )
                }
            } header: {
                Text(lang("$many_transactions", arg1: transfers.count))
            }
        }
    }
}

private struct WalletConnectPayTransferRow: View {
    var transfer: ApiDappTransfer
    var chain: ApiChain

    var body: some View {
        InsetCell {
            HStack(spacing: 8) {
                if transfer.isScam == true {
                    Image.airBundle("ScamBadge")
                }
                Text(rowText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.air.primaryLabel)
                    .opacity(transfer.isScam == true ? 0.7 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
        }
    }

    private var rowText: String {
        let amountText = displayedAmountText
        let address = formatStartEndAddress(transfer.displayedToAddress)
        let toText = lang("$transaction_to", arg1: address)

        guard !amountText.isEmpty else {
            return toText
        }

        return "\(amountText) \(toText)"
    }

    private var displayedAmountText: String {
        var amounts: [String] = []

        if transfer.isNftTransferPayload {
            amounts.append("1 NFT")
        }

        amounts.append(contentsOf: transfer.displayedAmounts(chain: chain, includeNativeFee: true).map {
            $0.formatted(.defaultAdaptive, maxDecimals: 4)
        })

        return amounts.joined(separator: " + ")
    }
}

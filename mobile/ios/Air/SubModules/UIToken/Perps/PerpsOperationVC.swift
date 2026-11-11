import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public final class PerpsOperationVC: WViewController {
    private let store: PerpsStore
    private let accountId: String
    private let operationId: String
    private let onWithdraw: () -> Void
    private let onReceipt: () -> Void
    private let statusView = PerpsOperationStatusView()
    private var detailsController: UIHostingController<PerpsOperationDetailsView>?
    private var isVisible = false
    private var isRefreshing = false
    private var isAcknowledging = false
    private lazy var refreshButton = makeButton(title: lang("Refresh"), style: .secondary) { [weak self] in
        Task { await self?.refresh() }
    }
    private lazy var actionButton = makeButton(title: lang("Close"), style: .primary) { [weak self] in self?.performAction() }

    public init(store: PerpsStore, accountId: String, operationId: String,
                onWithdraw: @escaping () -> Void, onReceipt: @escaping () -> Void) {
        self.store = store
        self.accountId = accountId
        self.operationId = operationId
        self.onWithdraw = onWithdraw
        self.onReceipt = onReceipt
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang(operation?.isBalanceWithdrawal == true ? "PerpsWithdrawalStatus" : "PerpsOperationStatus")
        view.backgroundColor = .air.groupedBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
        let details = addHostingController(PerpsOperationDetailsView(operation: operation, symbol: symbol))
        details.sizingOptions = .intrinsicContentSize
        detailsController = details
        let layout = AssetDetailsView(sections: [statusView, details.view], buttons: [refreshButton, actionButton])
        layout.scrollView.accessibilityIdentifier = "perps.operation.content"
        layout.install(in: view)
        addCustomNavigationBarBackground(color: .air.groupedBackground)
        observe { [weak self] in self?.updateContent() }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        updateContent()
        store.watch(accountId: accountId, every: .seconds(5), by: self)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        store.unwatch(by: self)
    }

    private var operation: ApiPerpsOperation? {
        guard let operation = store.operations[operationId], operation.accountId == accountId else { return nil }
        return operation
    }

    private var symbol: String {
        operation.flatMap { store.asset(id: $0.assetId) }?.symbol
            ?? operation?.assetId.components(separatedBy: ":").last ?? ""
    }

    private var hasReceipt: Bool {
        guard let operation, let orderId = operation.orderId else { return false }
        let coin = store.asset(id: operation.assetId)?.name ?? operation.assetId
        return store.fills[accountId]?.contains { $0.oid == orderId && $0.coin == coin } == true
    }

    private func updateContent() {
        let operation = operation
        let hasReceipt = hasReceipt
        statusView.configure(operation: operation, hasReceipt: hasReceipt)
        detailsController?.rootView = PerpsOperationDetailsView(operation: operation, symbol: symbol)
        let canAcknowledge = operation?.state == "unknown" && operation?.acknowledgedAt == nil
        let actionTitle: String
        if operation?.state == "partial" { actionTitle = "PerpsWithdrawReleased" }
        else if canAcknowledge { actionTitle = "PerpsAllowNewOrders" }
        else if hasReceipt { actionTitle = "Details" }
        else { actionTitle = operation?.blocksTrading == true ? "Hide" : "Close" }
        actionButton.setTitle(lang(actionTitle), for: .normal)
        actionButton.isEnabled = !isAcknowledging
        actionButton.showLoading = isAcknowledging
        refreshButton.isEnabled = !isRefreshing && !store.loading.contains(accountId)
    }

    private func refresh() async {
        guard isVisible, !isRefreshing else { return }
        isRefreshing = true
        refreshButton.isEnabled = false
        await store.reconcile(accountId: accountId)
        isRefreshing = false
        if isVisible { updateContent() }
    }

    private func performAction() {
        if operation?.state == "partial" { onWithdraw() }
        else if operation?.state == "unknown", operation?.acknowledgedAt == nil {
            let message = lang(operation?.isBalanceWithdrawal == true ? "PerpsAcknowledgeWithdrawalUnknown" : "PerpsAcknowledgeUnknown")
            let alert = WAlertController(title: lang("PerpsAllowNewOrders"), message: message, actions: acknowledgementActions())
            present(alert, animated: true)
        }
        else if hasReceipt { onReceipt() }
        else { close() }
    }

    func acknowledgementActions() -> [WAlertAction] {
        [
            WAlertAction(title: lang("Cancel")),
            WAlertAction(title: lang("PerpsAllowNewOrders"), style: .primary) { [weak self] in
                Task { await self?.acknowledgeUnknownOperation() }
            },
        ]
    }

    private func acknowledgeUnknownOperation() async {
        guard !isAcknowledging else { return }
        isAcknowledging = true
        updateContent()
        defer { isAcknowledging = false; updateContent() }
        do {
            try await store.acknowledgeUnknownOperation(id: operationId, accountId: accountId)
            close()
        } catch {
            showAlert(title: lang("Error"), text: PerpsFormatting.error(error), button: lang("OK"))
        }
    }

    private func close() {
        store.dismissOperationStatus(id: operationId, accountId: accountId)
        if let navigationController, navigationController.presentingViewController != nil {
            navigationController.dismiss(animated: true)
        } else if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func makeButton(title: String, style: WButtonStyle, action: @escaping () -> Void) -> WButton {
        let button = WButton(style: style)
        button.customTitleFont = WButton.capsuleFont
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = "perps.operation." + (style == .primary ? "action" : "refresh")
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

private final class PerpsOperationStatusView: UIView {
    private let icon = IconView(size: 60)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        for label in [titleLabel, messageLabel] {
            label.numberOfLines = 0
            label.textAlignment = .center
        }
        let labels = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        labels.axis = .vertical
        labels.spacing = 8
        let stack = UIStackView(arrangedSubviews: [icon, labels, spinner])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            labels.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        icon.isAccessibilityElement = false
        titleLabel.accessibilityTraits = .header
        titleLabel.accessibilityIdentifier = "perps.operation.status"
        messageLabel.textColor = .air.secondaryLabel
        messageLabel.accessibilityIdentifier = "perps.operation.message"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(operation: ApiPerpsOperation?, hasReceipt: Bool) {
        titleLabel.applyTextStyle(.statusTitle)
        messageLabel.applyTextStyle(.callout, scaling: .dynamic)
        let state = operation?.state
        let needsAttention = operation?.error == "PerpsPartialFill" || operation?.isWithdrawalRejected == true
        let isWithdrawal = operation?.isBalanceWithdrawal == true
        let statusMessage = operation.map(PerpsFormatting.operationMessage) ?? ""
        titleLabel.text = state == "completed" && !needsAttention
            ? lang(isWithdrawal ? "PerpsWithdrawalCompleted" : "PerpsCompleted")
            : lang(isWithdrawal ? "PerpsWithdrawalStatus" : "PerpsOperationStatus")
        titleLabel.textColor = state == "completed" && !needsAttention ? .air.positiveAmount : .label
        let glyph: String
        let colors: [UIColor]
        let message: String
        switch state {
        case "completed":
            glyph = needsAttention ? "exclamationmark" : "checkmark"
            colors = needsAttention ? [UIColor(light: "#DE8C00", dark: "#FFAB2F"), UIColor(light: "#DE8C00", dark: "#FFAB2F")] : UIColor.air.greenGradient
            message = !needsAttention && hasReceipt ? "" : statusMessage
        case "failed":
            glyph = "exclamationmark"
            colors = UIColor.air.redGradient
            message = statusMessage
        case "partial", "unknown":
            glyph = "exclamationmark"
            colors = [UIColor(light: "#DE8C00", dark: "#FFAB2F"), UIColor(light: "#DE8C00", dark: "#FFAB2F")]
            message = statusMessage
        case "running":
            glyph = "clock"
            colors = UIColor.air.blueGradient
            message = statusMessage
        default:
            glyph = "questionmark"
            colors = UIColor.air.blueGradient
            message = lang("Unavailable")
        }
        icon.config(activityImage: UIImage(systemName: glyph, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold))!, gradientColors: colors)
        messageLabel.text = message
        messageLabel.isHidden = message.isEmpty
        spinner.isHidden = state != "running"
        if state == "running" { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

private struct PerpsOperationDetailsView: View {
    let operation: ApiPerpsOperation?
    let symbol: String

    var body: some View {
        VStack(spacing: 16) {
            if let operation, let withdrawal = operation.balanceWithdrawal {
                InsetSection(horizontalPadding: 0) {
                    if operation.state != "failed" {
                        AssetInfoMetricRow(title: lang("You Receive"), value: PerpsFormatting.quantity(withdrawal.receiveAmount, symbol: "USDC"))
                    }
                    AssetInfoMetricRow(title: lang("PerpsWithdrawalFromHyperliquid"), value: PerpsFormatting.quantity(withdrawal.amount, symbol: "USDC"))
                    let withdrawalData = PerpsSDKAdapter.balanceWithdrawalReview(withdrawal)
                    PerpsFeeSummaryRow(fee: withdrawalData.fee, rows: withdrawalData.feeRows)
                    AssetInfoMetricRow(title: lang("PerpsWithdrawalToWallet"), value: formatStartEndAddress(withdrawal.destination))
                    AssetInfoMetricRow(title: lang("Date"), value: operation.createdAt.dateTimeString)
                }
            } else if let operation {
                InsetSection(horizontalPadding: 0) {
                    AssetInfoMetricRow(title: lang("Order"), value: PerpsFormatting.operationTitle(operation, symbol: symbol))
                    AssetInfoMetricRow(title: lang("Date"), value: operation.createdAt.dateTimeString)
                    if let orderId = operation.orderId {
                        AssetInfoMetricRow(title: lang("Order ID"), value: String(orderId))
                    }
                }
            }
            if let operation, let size = operation.filledSize {
                InsetSection(horizontalPadding: 0) {
                    AssetInfoMetricRow(title: lang("Position Size"), value: size + (symbol.isEmpty ? "" : " " + symbol))
                    if let price = operation.averagePrice {
                        AssetInfoMetricRow(title: lang("Price"), value: PerpsFormatting.money(price))
                    }
                }
            }
            if let hash = operation?.depositTxHash {
                PerpsTransferIDSection(hash: hash)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

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
    private let onCompleted: ((ApiPerpsOperation) -> Void)?
    private let statusView = PerpsOperationStatusView()
    private var detailsController: UIHostingController<PerpsOperationDetailsView>?
    private var pollTask: Task<Void, Never>?
    private var isVisible = false
    private var isRefreshing = false
    private var isAcknowledging = false
    private var didComplete = false
    private lazy var refreshButton = makeButton(title: lang("Refresh"), style: .secondary) { [weak self] in
        Task { await self?.refresh() }
    }
    private lazy var actionButton = makeButton(title: lang("Close"), style: .primary) { [weak self] in self?.performAction() }

    public init(store: PerpsStore, accountId: String, operationId: String,
                onWithdraw: @escaping () -> Void, onReceipt: @escaping () -> Void,
                onCompleted: ((ApiPerpsOperation) -> Void)? = nil) {
        self.store = store
        self.accountId = accountId
        self.operationId = operationId
        self.onWithdraw = onWithdraw
        self.onReceipt = onReceipt
        self.onCompleted = onCompleted
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    deinit { pollTask?.cancel() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("PerpsOperationStatus")
        view.backgroundColor = .air.groupedBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
        let details = addHostingController(PerpsOperationDetailsView(operation: operation, symbol: symbol))
        details.sizingOptions = .intrinsicContentSize
        detailsController = details
        let layout = AssetDetailsView(sections: [statusView, details.view], buttons: [refreshButton, actionButton])
        layout.scrollView.accessibilityIdentifier = "perps.operation.content"
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        addCustomNavigationBarBackground(color: .air.groupedBackground)
        observe { [weak self] in self?.updateContent() }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        updateContent()
        guard !didComplete else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.isVisible == true else { break }
                if UIApplication.shared.applicationState == .active { await self?.refresh() }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        pollTask?.cancel()
        pollTask = nil
    }

    private var operation: ApiPerpsOperation? {
        guard let operation = store.operations[operationId], operation.accountId == accountId else { return nil }
        return operation
    }

    private var symbol: String {
        store.snapshots[accountId]?.assets.first { $0.id == operation?.assetId }?.symbol
            ?? operation?.assetId.components(separatedBy: ":").last ?? ""
    }

    private var hasReceipt: Bool {
        guard let operation, let orderId = operation.orderId else { return false }
        let coin = store.snapshots[accountId]?.assets.first { $0.id == operation.assetId }?.name ?? operation.assetId
        return store.fills[accountId]?.contains { $0.oid == orderId && $0.coin == coin && $0.eventKind != nil } == true
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
        guard isVisible, !didComplete, let operation, operation.state == "completed", operation.error != "PerpsPartialFill", hasReceipt,
              let onCompleted else { return }
        didComplete = true
        pollTask?.cancel()
        pollTask = nil
        onCompleted(operation)
    }

    private func refresh() async {
        guard isVisible, !isRefreshing, !didComplete else { return }
        isRefreshing = true
        refreshButton.isEnabled = false
        await store.reconcile(accountId: accountId)
        isRefreshing = false
        if isVisible { updateContent() }
    }

    private func performAction() {
        if operation?.state == "partial" { onWithdraw() }
        else if operation?.state == "unknown", operation?.acknowledgedAt == nil {
            let alert = WAlertController(title: lang("PerpsAllowNewOrders"), message: lang("PerpsAcknowledgeUnknown"), actions: acknowledgementActions())
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
        let isPartialFill = operation?.error == "PerpsPartialFill"
        titleLabel.text = lang(state == "completed" && !isPartialFill ? "PerpsCompleted" : "PerpsOperationStatus")
        titleLabel.textColor = state == "completed" && !isPartialFill ? .air.positiveAmount : .label
        let glyph: String
        let colors: [UIColor]
        let message: String
        switch state {
        case "completed":
            glyph = isPartialFill ? "exclamationmark" : "checkmark"
            colors = isPartialFill ? [UIColor(light: "#DE8C00", dark: "#FFAB2F"), UIColor(light: "#DE8C00", dark: "#FFAB2F")] : UIColor.air.greenGradient
            message = isPartialFill ? lang("PerpsPartialFill") : hasReceipt ? "" : lang("PerpsReconciled")
        case "failed":
            glyph = "exclamationmark"
            colors = UIColor.air.redGradient
            message = PerpsFormatting.errorMessage(operation?.error)
        case "partial", "unknown":
            glyph = "exclamationmark"
            colors = [UIColor(light: "#DE8C00", dark: "#FFAB2F"), UIColor(light: "#DE8C00", dark: "#FFAB2F")]
            message = lang(state == "partial" ? "PerpsWithdrawalPending" : "PerpsExecutionUnknown")
        case "running":
            glyph = "clock"
            colors = UIColor.air.blueGradient
            message = lang("PerpsProcessing")
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
            if let operation {
                InsetSection(horizontalPadding: 0) {
                    AssetInfoMetricRow(title: lang("Order"), value: PerpsFormatting.operationTitle(operation, symbol: symbol))
                    AssetInfoMetricRow(title: lang("Date"), value: PerpsFormatting.date(operation.createdAt))
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
                InsetSection(horizontalPadding: 0) {
                    Button { AppActions.copyString(hash, toastMessage: lang("Copied")) } label: {
                        AssetInfoMetricRow(title: lang("Transfer ID"), value: hash)
                    }
                    .buttonStyle(InsetRowButtonStyle())
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

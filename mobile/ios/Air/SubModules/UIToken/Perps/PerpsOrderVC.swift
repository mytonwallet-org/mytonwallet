import ContextMenuKit
import Combine
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor
public final class PerpsOrderVC: WViewController {
    private let state: PerpsOrderState
    private let accountButton = AccountSwitcherButton()
    private var menuInteraction: ContextMenuInteraction?
    private let orderTitle = PerpsOrderTitleView()
    private var didRefreshInitialFunding = false
    private var isVisible = false
    private var estimateRefreshSuspended = false
    private var estimateRefreshFailures = 0
    private var applicationSubscription: AnyCancellable?
    private let loadEstimate: (@MainActor (PerpsOrderInput) async throws -> PerpsOrderDisplayData)?
    private let loadLeverageEstimates: ((PerpsOrderInput) async throws -> [PerpsOrderDisplayData.LeverageOption])?
    private lazy var estimateRefresh = DraftEngine<PerpsOrderState.EstimateRefreshRequest, Bool>(
        debounce: { _, _ in .seconds(10) }, refreshInterval: .seconds(10), load: { [weak self] request, _ in
            guard let self, let loadEstimate = self.loadEstimate else { return false }
            let data = try await loadEstimate(request.input)
            return self.state.applyEstimateRefresh(data, for: request)
        })

    public init(data: PerpsOrderDisplayData,
                loadLeverageEstimates: ((PerpsOrderInput) async throws -> [PerpsOrderDisplayData.LeverageOption])? = nil,
                loadEstimate: (@MainActor (PerpsOrderInput) async throws -> PerpsOrderDisplayData)? = nil,
                onRequest: @escaping (PerpsOrderRequest) -> Void) {
        self.loadLeverageEstimates = loadLeverageEstimates
        self.loadEstimate = loadEstimate
        state = PerpsOrderState(data: data, onRequest: onRequest)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        if !didRefreshInitialFunding {
            didRefreshInitialFunding = true
            refreshFunding()
        }
        updateEstimateRefreshActivity()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        updateEstimateRefreshActivity()
    }

    public func setEstimateRefreshSuspended(_ suspended: Bool) {
        estimateRefreshSuspended = suspended
        updateEstimateRefreshActivity()
    }

    private func updateEstimateRefreshActivity() {
        guard loadEstimate != nil else { return }
        let active = isVisible && !estimateRefreshSuspended && CardBackgroundAnimationEnvironment.shared.applicationActive
        state.setEstimateRefreshActive(active)
        if active { estimateRefresh.resume() } else { estimateRefresh.pause() }
    }

    public func refreshFunding() {
        state.request(.refreshFunding)
    }

    public func refreshBlockedFunding() {
        let isIdleOpening = state.data.status == .idle && state.data.editingPosition == nil && !state.data.input.hasAmount
        guard state.data.fundingRequirement != nil || state.canRetryFunding || isIdleOpening else { return }
        refreshFunding()
    }

    /// Echo the request that produced this snapshot. Before any input, omit it for an initial load.
    /// Returns false for superseded responses, including initial loads that arrive after the user edits.
    @discardableResult
    public func update(data: PerpsOrderDisplayData, for request: PerpsOrderRequest? = nil) -> Bool {
        state.update(data: data, for: request)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.headerBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        accountButton.accessibilityIdentifier = "perps.order.account"
        accountButton.addAction(UIAction { [weak self] _ in self?.state.request(.selectAccount) }, for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: accountButton)
        if #available(iOS 27.1, *) { navigationItem.leftBarButtonItem?.axisBehavior = .verticalPreferred }
        navigationItem.titleView = orderTitle
        configureInfoButton()
        if loadEstimate != nil {
            estimateRefresh.onLoad = { [weak self] _ in
                self?.estimateRefreshFailures = 0
                self?.estimateRefresh.refreshInterval = .seconds(10)
            }
            estimateRefresh.onFailure = { [weak self] _, _ in
                guard let self else { return }
                estimateRefreshFailures = min(estimateRefreshFailures + 1, 3)
                estimateRefresh.refreshInterval = .seconds(min(60, 10 * (1 << estimateRefreshFailures)))
            }
            estimateRefresh.start { [weak self] in self?.state.estimateRefreshRequest }
            applicationSubscription = CardBackgroundAnimationEnvironment.shared.$applicationActive
                .removeDuplicates().sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updateEstimateRefreshActivity() }
                }
        }
        PerpsOrderView(state: state, selectLeverage: { [weak self] in
            self?.showLeverage()
        }).install(in: view)
        observe { [weak self] in
            guard let self else { return }
            let data = state.data
            let title: String
            let compactTitle: String
            if data.editingPosition != nil {
                title = data.direction == .long
                    ? L10n.perpsEditLong(asset: data.token.symbol)
                    : L10n.perpsEditShort(asset: data.token.symbol)
                compactTitle = title
            } else {
                title = data.direction == .long
                    ? L10n.perpsOrderLong(asset: data.token.name)
                    : L10n.perpsOrderShort(asset: data.token.name)
                compactTitle = data.direction == .long
                    ? L10n.perpsOrderLong(asset: data.token.symbol)
                    : L10n.perpsOrderShort(asset: data.token.symbol)
            }
            orderTitle.configure(title: title, compactTitle: compactTitle, price: lang("Price") + " " + data.price)
            accountButton.configure(account: data.account, showsChevron: data.canSelectAccount)
            accountButton.isEnabled = data.canSelectAccount
            accountButton.isHidden = data.account == nil
        }
    }

    private func configureInfoButton() {
        let button = UIButton(type: .system)
        if #available(iOS 26, *), IOS_26_MODE_ENABLED {
            var configuration = UIButton.Configuration.glass()
            configuration.cornerStyle = .capsule
            configuration.contentInsets = .zero
            configuration.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .medium)
            button.configuration = configuration
        }
        button.setImage(UIImage(systemName: "info"), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = lang("Info")
        button.accessibilityIdentifier = "perps.order.info"
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.frame = container.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(button)
        let item = UIBarButtonItem(customView: container)
        if #available(iOS 26, *) { item.hidesSharedBackground = true }
        if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
        navigationItem.rightBarButtonItems = (navigationItem.rightBarButtonItems ?? []) + [item]
        let interaction = ContextMenuInteraction(triggers: [.tap, .longPress], presentationMode: .zoomPopover) { [weak self] _ in
            guard let self else { return nil }
            let isEditing = state.data.editingPosition != nil
            var items: [ContextMenuItem] = []
            if state.data.swapFee != nil {
                items.append(TradeInfoMenu.row(title: lang("PerpsBridgeFee"), value: { [state] in state.data.swapFee ?? "—" }, help: lang("PerpsFeeEstimateHint")))
            }
            items += [
                TradeInfoMenu.row(title: lang("Network Fee"), value: { [state] in state.data.networkFee ?? "—" }, help: lang("$perps_network_fee_hint")),
                TradeInfoMenu.row(title: lang("Trading Fee"), value: { [state] in state.data.tradingFee ?? "—" }, help: lang("$perps_trading_fee_hint")),
                TradeInfoMenu.row(title: lang("Funding Payments"), value: { [state] in state.data.fundingPayments ?? "—" }, help: lang("$perps_funding_payments_hint")),
            ]
            items += [
                .separator,
                .custom(.swiftUI(preferredWidth: 242, sizing: .automatic(minHeight: 48), interaction: .contentHandlesTouches) { _ in
                    VStack(alignment: .leading, spacing: 20) {
                        if isEditing { Text(lang("$perps_edit_liquidation_hint")) }
                        Text(lang("$perps_position_size_hint"))
                    }
                    .textStyle(.footnote)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }),
            ]
            return ContextMenuConfiguration(rootPage: .init(items: items), backdrop: .none,
                style: .init(minWidth: 242, maxWidth: 300, glassTint: .strong, listVerticalPadding: 10, separatorHeight: 20))
        }
        interaction.attach(to: button)
        button.addAction(UIAction { [weak interaction] _ in interaction?.present() }, for: .primaryActionTriggered)
        menuInteraction = interaction
    }

    private func showLeverage() {
        guard state.canSelectLeverage else { return }
        let controller = PerpsLeverageVC(data: state.data) { [weak self] in self?.state.selectLeverage($0) }
        setEstimateRefreshSuspended(true)
        controller.onDismiss = { [weak self] in self?.setEstimateRefreshSuspended(false) }
        if let loadLeverageEstimates {
            let input = state.data.input
            controller.loadEstimate = { leverage in
                var input = input
                input.leverage = leverage
                return try await loadLeverageEstimates(input)
            }
        }
        present(WNavigationController(rootViewController: controller), animated: true)
    }
}

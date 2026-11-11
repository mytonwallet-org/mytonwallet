import ContextMenuKit
import Combine
import Perception
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor
public final class PerpsOrderVC: WViewController {
    private let state: PerpsOrderState
    private let onSelectAccount: (@MainActor (String) async throws -> Void)?
    private var isChangingAccount = false
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .perps)) { [weak self] accountId in
        Task { await self?.selectAccount(accountId) }
    }
    private var infoButton: TradeInfoBarButton?
    private var didRefreshInitialFunding = false
    private var isVisible = false
    private var estimateRefreshSuspended = false
    private var estimateRefreshFailures = 0
    private var applicationSubscription: AnyCancellable?
    private let loadEstimate: (@MainActor (PerpsOrderInput) async throws -> PerpsOrderDisplayData)?
    private let loadLeverageEstimate: ((PerpsOrderInput) async throws -> PerpsOrderDisplayData.LeverageEstimate)?
    private lazy var estimateRefresh = DraftEngine<PerpsOrderState.EstimateRefreshRequest, Bool>(
        debounce: { _, _ in .seconds(10) }, refreshInterval: .seconds(10), load: { [weak self] request, _ in
            guard let self, let loadEstimate = self.loadEstimate else { return false }
            let data = try await loadEstimate(request.input)
            return self.state.applyEstimateRefresh(data, for: request)
        })

    public init(data: PerpsOrderDisplayData,
                loadLeverageEstimate: ((PerpsOrderInput) async throws -> PerpsOrderDisplayData.LeverageEstimate)? = nil,
                loadEstimate: (@MainActor (PerpsOrderInput) async throws -> PerpsOrderDisplayData)? = nil,
                onSelectAccount: (@MainActor (String) async throws -> Void)? = nil,
                onRequest: @escaping (PerpsOrderRequest) -> Void) {
        self.loadLeverageEstimate = loadLeverageEstimate
        self.loadEstimate = loadEstimate
        self.onSelectAccount = onSelectAccount
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
        infoButton?.interaction.dismiss()
        updateEstimateRefreshActivity()
    }

    public func setEstimateRefreshSuspended(_ suspended: Bool) {
        estimateRefreshSuspended = suspended
        updateEstimateRefreshActivity()
    }

    private func updateEstimateRefreshActivity() {
        guard loadEstimate != nil else { return }
        let active = isVisible && !estimateRefreshSuspended && !isChangingAccount && CardBackgroundAnimationEnvironment.shared.applicationActive
        state.setEstimateRefreshActive(active)
        if active { estimateRefresh.resume() } else { estimateRefresh.pause() }
    }

    public func refreshFunding() {
        state.request(.refreshFunding)
    }

    public func refreshBlockedFunding() {
        guard !isChangingAccount else { return }
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
        accountSwitcher.button.accessibilityIdentifier = "perps.order.account"
        if #available(iOS 27.1, *) { accountSwitcher.barButtonItem.axisBehavior = .verticalPreferred }
        observe { [weak self] in self?.updateAccountSwitcher() }
        let state = state
        navigationItem.titleView = HostingView {
            WithPerceptionTracking {
                NavigationHeader {
                    ViewThatFits(in: .horizontal) {
                        Text(verbatim: state.data.title(compact: false))
                        Text(verbatim: state.data.title(compact: true))
                    }
                } subtitle: {
                    Text(verbatim: lang("Price") + " " + state.data.price)
                }
                .accessibilityElement(children: .combine)
                // VoiceOver reads the full title even when the compact one is shown.
                .accessibilityLabel(Text(verbatim: state.data.title(compact: false) + ", " + lang("Price") + " " + state.data.price))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("perps.order.title")
            }
        }
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
    }

    private func updateAccountSwitcher() {
        guard state.data.editingPosition == nil, onSelectAccount != nil, let account = state.data.account else {
            navigationItem.leftBarButtonItem = nil
            return
        }
        accountSwitcher.update(selectedAccountId: account.id, isEnabled: !isChangingAccount)
        navigationItem.leftBarButtonItem = accountSwitcher.hasAlternativeAccounts(selectedAccountId: account.id)
            ? accountSwitcher.barButtonItem : nil
    }

    func selectAccount(_ accountId: String) async {
        guard !isChangingAccount, state.data.editingPosition == nil,
              accountId != state.data.account?.id, let onSelectAccount else { return }
        isChangingAccount = true
        view.isUserInteractionEnabled = false
        updateAccountSwitcher()
        updateEstimateRefreshActivity()
        defer {
            isChangingAccount = false
            view.isUserInteractionEnabled = true
            updateAccountSwitcher()
            updateEstimateRefreshActivity()
        }
        do {
            try await onSelectAccount(accountId)
        } catch {
            AppActions.showError(error: error)
            refreshFunding()
        }
    }

    private func configureInfoButton() {
        let info = TradeInfoMenu.barButton(accessibilityIdentifier: "perps.order.info") { [weak self] in
            guard let self, isVisible else { return nil }
            let state = state
            var items: [ContextMenuItem] = []
            if state.data.bridgeFee != nil {
                items.append(TradeInfoMenu.row(title: lang("PerpsBridgeFee"), value: { state.data.bridgeFee ?? "—" }, help: lang("PerpsFeeEstimateHint")))
            }
            if state.data.networkFee != nil {
                items.append(TradeInfoMenu.row(title: lang("Network Fee"), value: { state.data.networkFee ?? "—" }, help: lang("$perps_network_fee_hint")))
            }
            items += [
                TradeInfoMenu.row(title: lang("Trading Fee"), value: { state.data.tradingFee ?? "—" }, help: lang("$perps_trading_fee_hint")),
                TradeInfoMenu.row(title: lang("Funding Rate"), value: { state.data.fundingRate ?? "—" }, help: lang("$perps_funding_rate_hint")),
                .separator,
                .custom(.swiftUI(preferredWidth: 242, sizing: .automatic(minHeight: 48), interaction: .contentHandlesTouches) { _ in
                    VStack(alignment: .leading, spacing: 20) {
                        if state.data.editingPosition != nil { Text(lang("$perps_edit_liquidation_hint")) }
                        Text(lang("$perps_position_size_hint"))
                    }
                    .textStyle(.footnote)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }),
            ]
            return TradeInfoMenu.configuration(items: items)
        }
        info.button.setImage(UIImage(systemName: "info"), for: .normal)
        info.button.accessibilityLabel = lang("Info")
        navigationItem.rightBarButtonItems = (navigationItem.rightBarButtonItems ?? []) + [info.item]
        infoButton = info
    }

    private func showLeverage() {
        guard state.canSelectLeverage else { return }
        let controller = PerpsLeverageVC(data: state.data) { [weak self] in self?.state.selectLeverage($0) }
        setEstimateRefreshSuspended(true)
        controller.onDismiss = { [weak self] in self?.setEstimateRefreshSuspended(false) }
        if let loadLeverageEstimate {
            let input = state.data.input
            controller.loadEstimate = { leverage in
                var input = input
                input.leverage = leverage
                return try await loadLeverageEstimate(input)
            }
        }
        present(WNavigationController(rootViewController: controller), animated: true)
    }
}

private extension PerpsOrderDisplayData {
    func title(compact: Bool) -> String {
        if editingPosition != nil {
            return direction == .long ? L10n.perpsEditLong(asset: token.symbol) : L10n.perpsEditShort(asset: token.symbol)
        }
        let asset = compact ? token.symbol : token.name
        return direction == .long ? L10n.perpsOrderLong(asset: asset) : L10n.perpsOrderShort(asset: asset)
    }
}

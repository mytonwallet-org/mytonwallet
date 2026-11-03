import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public final class PerpsPositionVC: WViewController, UIScrollViewDelegate {
    public var onLoadMoreActivity: (() -> Void)?
    public var onVisibilityChanged: ((Bool) -> Void)?
    public var isPreparingClose = false {
        didSet { if isViewLoaded { updateActionButtons() } }
    }
    private var data: PerpsPositionDisplayData
    private let onSelectPeriod: (ApiPriceHistoryPeriod) -> Void
    private let onAction: (PerpsPositionAction) -> Void
    private var positionController: UIHostingController<PerpsPositionView>?
    private var infoView: PerpsMarketInfoView?
    private var detailsView: AssetDetailsView?
    private lazy var activitySection = PerpsPositionActivitySectionView { [weak self] id in
        guard let self, data.activities.contains(where: { $0.id == id && $0.canSelect }) else { return }
        onAction(.activity(id))
    }
    private lazy var chartView = TokenExpandableChartView(usesStoredPresentation: false) { [weak self] in
        self?.view.layoutIfNeeded()
    }
    private lazy var editButton = makeButton(title: lang("PerpsEditPositionAction"), style: .secondary, action: .edit)
    private lazy var closeButton = makeButton(title: lang("PerpsClosePositionAction"), style: .primary, action: .close)
    private lazy var closeButtonPresenter = DraftButtonPresenter(button: closeButton)

    public init(data: PerpsPositionDisplayData, onSelectPeriod: @escaping (ApiPriceHistoryPeriod) -> Void,
                onAction: @escaping (PerpsPositionAction) -> Void) {
        self.data = data
        self.onSelectPeriod = onSelectPeriod
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItemWithTransparentBackground()
        view.backgroundColor = .air.groupedBackground
        let position = addHostingController(PerpsPositionView(data: data))
        let info = PerpsMarketInfoView(data: data.market, collapsesMetrics: true)
        position.sizingOptions = .intrinsicContentSize
        positionController = position
        infoView = info
        let layout = AssetDetailsView(sections: [position.view, chartView, info, activitySection], buttons: [editButton, closeButton])
        detailsView = layout
        layout.content.setCustomSpacing(24, after: position.view)
        layout.scrollView.delegate = self
        layout.scrollView.accessibilityIdentifier = "Perps.Position.Content"
        info.onHeightChange = { [weak layout] in layout?.layoutKeepingScrollPosition() }
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        addCustomNavigationBarBackground(color: .air.groupedBackground)
        applyData()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 300 {
            onLoadMoreActivity?()
        }
    }

    /// Adapters should discard stale requests before supplying a new snapshot of this position.
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onVisibilityChanged?(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onVisibilityChanged?(false)
    }

    public func update(data: PerpsPositionDisplayData) {
        guard data.id == self.data.id else { return }
        self.data = data
        if isViewLoaded { applyData() }
    }

    private func applyData() {
        title = data.market.token.symbol
        let token = data.market.token.symbol
        let direction = data.direction
        let leverage = L10n.perpsLeverageDirection(
            leverage: data.leverage.formatted(.number.locale(.forNumberFormatters)),
            direction: lang(direction == .long ? "Long" : "Short"))
        navigationItem.titleView = HostingView {
            NavigationHeader {
                HStack(spacing: 4) {
                    Text(verbatim: token).foregroundStyle(Color.air.primaryLabel)
                    Text(verbatim: leverage).foregroundStyle(direction == .long ? Color.air.positiveAmount : Color.air.negativeAmount)
                }
                .accessibilityElement(children: .combine)
            }
        }
        positionController?.rootView = PerpsPositionView(data: data)
        infoView?.configure(data: data.market)
        activitySection.configure(activities: data.activities, title: data.activityTitle, isStale: data.isActivityStale)
        activitySection.isHidden = data.activities.isEmpty
        chartView.configure(token: data.market.token, price: data.market.price, percentChange24h: data.market.percentChange24h,
                            baseCurrency: data.market.baseCurrency, period: data.market.period, showsTokenIcon: false,
                            priceTitle: L10n.perpsAssetPrice(asset: data.market.token.name), historyData: data.market.history,
                            isHistoryRestored: data.market.isHistoryRestored, isHistoryStale: data.market.isHistoryRestored,
                            isValueStale: data.market.isStale,
                            onPeriodChange: { [weak self] in self?.onSelectPeriod($0) })
        updateActionButtons()
    }

    private func updateActionButtons() {
        detailsView?.setActionNotice(data.market.tradingUnavailableReason)
        editButton.isEnabled = data.canEdit && !isPreparingClose
        closeButtonPresenter.apply(.init(title: .text(lang("PerpsClosePositionAction")),
                                         isEnabled: data.canClose && !isPreparingClose,
                                         showLoading: isPreparingClose))
    }

    private func makeButton(title: String, style: WButtonStyle, action: PerpsPositionAction) -> WButton {
        let button = WButton(style: style)
        button.customTitleFont = WButton.capsuleFont
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = "perps.position." + (style == .primary ? "close" : "edit")
        if style == .secondary { button.customTintColor = .label }
        button.addAction(UIAction { [weak self] _ in
            guard let self, !isPreparingClose else { return }
            switch action {
            case .edit: guard data.canEdit else { return }
            case .close: guard data.canClose else { return }
            case .activity: return
            }
            onAction(action)
        }, for: .touchUpInside)
        return button
    }
}

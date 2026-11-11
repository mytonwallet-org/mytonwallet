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
    private(set) var data: PerpsPositionDisplayData
    let onSelectPeriod: (ApiPriceHistoryPeriod) -> Void
    private let onAction: (PerpsPositionAction) -> Void
    private var positionController: UIHostingController<PerpsPositionView>?
    private lazy var infoModel = TokenInfoModel(state: .summary(data.market.infoSummary), hasBalance: true)
    private let infoCard = TokenInfoCardView(sizesItself: true)
    private var detailsView: AssetDetailsView?
    private var titleKey: String?
    private lazy var activitySection = PerpsPositionActivitySectionView { [weak self] id in
        self?.onAction(.activity(id))
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
        position.sizingOptions = .intrinsicContentSize
        positionController = position
        let layout = AssetDetailsView(sections: [position.view, chartView, infoCard, activitySection], buttons: [editButton, closeButton])
        detailsView = layout
        layout.content.setCustomSpacing(24, after: position.view)
        layout.scrollView.delegate = self
        layout.scrollView.accessibilityIdentifier = "Perps.Position.Content"
        infoCard.configure(model: infoModel, onHeightChange: { [weak layout] in layout?.layoutKeepingScrollPosition() })
        layout.install(in: view)
        addCustomNavigationBarBackground(color: .air.groupedBackground)
        applyData()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 300 {
            onLoadMoreActivity?()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onVisibilityChanged?(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onVisibilityChanged?(false)
    }

    /// Ignores snapshots of another position.
    public func update(data: PerpsPositionDisplayData) {
        guard data.id == self.data.id else { return }
        self.data = data
        if isViewLoaded { applyData() }
    }

    private func applyData() {
        updateTitle()
        positionController?.rootView = PerpsPositionView(data: data)
        infoModel.configure(state: .summary(data.market.infoSummary))
        infoCard.modelStateDidChange()
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

    private func updateTitle() {
        let token = data.market.token.symbol
        let direction = data.direction
        let leverage = L10n.perpsLeverageDirection(
            leverage: data.leverage.formatted(.number.locale(.forNumberFormatters)),
            direction: lang(direction == .long ? "Long" : "Short"))
        let key = token + " " + leverage
        guard key != titleKey else { return }
        titleKey = key
        title = token
        navigationItem.titleView = HostingView {
            NavigationHeader {
                HStack(spacing: 4) {
                    Text(verbatim: token).foregroundStyle(Color.air.primaryLabel)
                    Text(verbatim: leverage).foregroundStyle(direction == .long ? Color.air.positiveAmount : Color.air.negativeAmount)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func updateActionButtons() {
        detailsView?.setActionNotice(data.market.tradingUnavailableReason, isInformational: data.market.isUnavailableReasonInformational)
        editButton.isEnabled = data.market.canTrade && !isPreparingClose
        closeButtonPresenter.apply(.init(title: .text(lang("PerpsClosePositionAction")),
                                         isEnabled: data.market.canTrade && !isPreparingClose,
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
            onAction(action)
        }, for: .touchUpInside)
        return button
    }
}

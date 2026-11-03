import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public final class PerpsMarketVC: WViewController {
    public var onVisibilityChanged: ((Bool) -> Void)?
    private var data: PerpsMarketDisplayData
    private let onSelectPeriod: (ApiPriceHistoryPeriod) -> Void
    private let onSelectDirection: (PerpsTradeDirection) -> Void
    private lazy var chartView = TokenExpandableChartView(usesStoredPresentation: false) { [weak self] in
        self?.view.layoutIfNeeded()
    }
    private var infoView: PerpsMarketInfoView?
    private var detailsView: AssetDetailsView?
    private lazy var longButton = makeTradeButton(.long)
    private lazy var shortButton = makeTradeButton(.short)

    public init(
        data: PerpsMarketDisplayData,
        onSelectPeriod: @escaping (ApiPriceHistoryPeriod) -> Void,
        onSelectDirection: @escaping (PerpsTradeDirection) -> Void
    ) {
        self.data = data
        self.onSelectPeriod = onSelectPeriod
        self.onSelectDirection = onSelectDirection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItemWithTransparentBackground()
        view.backgroundColor = .air.groupedBackground
        let info = PerpsMarketInfoView(data: data)
        infoView = info
        let layout = AssetDetailsView(sections: [chartView, info], buttons: [longButton, shortButton])
        detailsView = layout
        layout.scrollView.accessibilityIdentifier = "Perps.Market.Content"
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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onVisibilityChanged?(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onVisibilityChanged?(false)
    }

    public func update(data: PerpsMarketDisplayData) {
        self.data = data
        if isViewLoaded {
            applyData()
        }
    }

    private func applyData() {
        title = data.title
        infoView?.configure(data: data)
        chartView.configure(
            token: data.token, price: data.price, percentChange24h: data.percentChange24h,
            baseCurrency: data.baseCurrency, period: data.period, historyData: data.history,
            isHistoryRestored: data.isHistoryRestored, isHistoryStale: data.isHistoryRestored, isValueStale: data.isStale,
            onPeriodChange: { [weak self] period in self?.onSelectPeriod(period) }
        )
        longButton.isEnabled = data.canTrade
        shortButton.isEnabled = data.canTrade
        detailsView?.setActionNotice(data.tradingUnavailableReason)
    }

    private func makeTradeButton(_ direction: PerpsTradeDirection) -> WButton {
        let isLong = direction == .long
        let button = WButton(style: .primary)
        button.customTintColor = isLong ? .air.positiveAmount : .air.negativeAmount
        button.customTitleFont = WButton.capsuleFont
        button.setTitle(lang(isLong ? "Long" : "Short"), for: .normal)
        button.setImage(.airBundle(isLong ? "PerpsLong" : "PerpsShort").withRenderingMode(.alwaysTemplate), for: .normal)
        if var configuration = button.configuration {
            configuration.imagePadding = 4
            button.configuration = configuration
        }
        button.accessibilityIdentifier = isLong ? "Perps.Long" : "Perps.Short"
        button.addAction(UIAction { [weak self] _ in
            guard let self, data.canTrade else { return }
            onSelectDirection(direction)
        }, for: .touchUpInside)
        return button
    }
}

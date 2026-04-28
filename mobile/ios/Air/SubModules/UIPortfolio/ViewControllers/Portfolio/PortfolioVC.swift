import Perception
import SwiftUI
import UIComponents
import UIKit
import WalletCore
import WalletContext

private let portfolioSectionTopSpacing = CGFloat(20)

private final class PortfolioCollectionView: UICollectionView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

private enum PortfolioSectionID: Hashable {
    case localSummary
    case localInsights
    case totalValueChart
    case portfolioShareChart
}

private enum PortfolioItemID: Hashable {
    case localSummary
    case localInsight(PortfolioInsightCardID)
    case totalValueChartTile
    case portfolioShareChartTile
}

@MainActor
private struct PortfolioSectionDescriptor: Equatable {
    let id: PortfolioSectionID
    let items: [PortfolioItemID]
    let layout: PortfolioSectionLayout
    let contentInsets: NSDirectionalEdgeInsets
    let interGroupSpacing: CGFloat

    func makeLayoutSection() -> NSCollectionLayoutSection {
        let section = layout.makeLayoutSection()
        section.contentInsets = contentInsets
        section.interGroupSpacing = interGroupSpacing
        return section
    }
}

@MainActor
private enum PortfolioSectionLayout: Equatable {
    case fullWidthTile(estimatedHeight: CGFloat)
    case horizontalTiles(itemWidth: CGFloat, estimatedHeight: CGFloat, orthogonalScrolling: UICollectionLayoutSectionOrthogonalScrollingBehavior)

    func makeLayoutSection() -> NSCollectionLayoutSection {
        switch self {
        case .fullWidthTile(let estimatedHeight):
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(estimatedHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
            return NSCollectionLayoutSection(group: group)
        case .horizontalTiles(let itemWidth, let estimatedHeight, let orthogonalScrolling):
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(estimatedHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .estimated(estimatedHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = orthogonalScrolling
            return section
        }
    }
}

public final class PortfolioVC: WViewController, UICollectionViewDelegate, WBackSwipeControlling {
    private struct ChartViewState {
        let errorText: String?
        let isLoading: Bool
        let isRefreshing: Bool
    }

    private typealias CollectionViewDataSource = UICollectionViewDiffableDataSource<PortfolioSectionID, PortfolioItemID>
    private let backSwipeSafeInset = CGFloat(30.0)
    private let chartAdapterConfiguration = PortfolioGraphKitAdapter.Configuration(
        maxSeriesCount: nil,
        includeOtherSeries: false
    )
    private var registeredChartInteractionBlockers = Set<ObjectIdentifier>()
    private var insightLegendDisplayModes: [PortfolioInsightCardID: PortfolioInsightLegendDisplayMode] = [:]
    private var isChartLayoutInvalidationScheduled = false

    private let viewModel: PortfolioVM
    private var sectionDescriptors: [PortfolioSectionDescriptor] = []
    private var localInsightCards: [PortfolioInsightCardModel] = []
    private var chartViewState = ChartViewState(errorText: nil, isLoading: false, isRefreshing: false)
    private var preparedCharts = PortfolioGraphKitAdapter.PreparedCharts.empty
    private var preparedChartDataToken = -1
    private var preparingChartDataToken: Int?
    private var chartPreparationTask: Task<Void, Never>?
    private var languageObserver: NSObjectProtocol?
    private lazy var collectionView = makeCollectionView()
    private lazy var dataSource = makeDataSource()

    public init(accountContext: AccountContext) {
        self.viewModel = PortfolioVM(accountContext: accountContext)
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        chartPreparationTask?.cancel()
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = lang("Portfolio")
        view.backgroundColor = .air.background
        addCloseNavigationItemIfNeeded()

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        localInsightCards = viewModel.localInsightCards
        applySnapshot(animated: false)
        observeLanguageChanges()
        bindViewModel()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.loadIfNeeded()
        registerVisibleChartGestureDependencies()
    }

    private func makeSectionDescriptors() -> [PortfolioSectionDescriptor] {
        var sections: [PortfolioSectionDescriptor] = [
            PortfolioSectionDescriptor(
                id: .localSummary,
                items: [.localSummary],
                layout: .fullWidthTile(estimatedHeight: 108),
                contentInsets: .init(top: portfolioSectionTopSpacing, leading: 20, bottom: 0, trailing: 20),
                interGroupSpacing: 0
            ),
        ]

        if !localInsightCards.isEmpty {
            sections.append(
                    PortfolioSectionDescriptor(
                        id: .localInsights,
                        items: localInsightCards.map { .localInsight($0.id) },
                        layout: .horizontalTiles(
                            itemWidth: 238,
                            estimatedHeight: 230,
                            orthogonalScrolling: .continuousGroupLeadingBoundary
                        ),
                        contentInsets: .init(top: portfolioSectionTopSpacing, leading: 20, bottom: 0, trailing: 20),
                        interGroupSpacing: 12
                )
            )
        }

        sections.append(contentsOf: [
            PortfolioSectionDescriptor(
                id: .totalValueChart,
                items: [.totalValueChartTile],
                layout: .fullWidthTile(estimatedHeight: 580),
                contentInsets: .init(top: portfolioSectionTopSpacing, leading: 0, bottom: 0, trailing: 0),
                interGroupSpacing: 0
            ),
            PortfolioSectionDescriptor(
                id: .portfolioShareChart,
                items: [.portfolioShareChartTile],
                layout: .fullWidthTile(estimatedHeight: 560),
                contentInsets: .init(top: portfolioSectionTopSpacing, leading: 0, bottom: 28, trailing: 0),
                interGroupSpacing: 0
            ),
        ])

        return sections
    }

    private func makeCollectionView() -> UICollectionView {
        let collectionView = PortfolioCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delaysContentTouches = false
        collectionView.allowsSelection = false
        collectionView.delegate = self
        return collectionView
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let self,
                  self.sectionDescriptors.indices.contains(sectionIndex)
            else {
                return nil
            }

            return self.sectionDescriptors[sectionIndex].makeLayoutSection()
        }
    }

    private func makeDataSource() -> CollectionViewDataSource {
        let summaryRegistration = UICollectionView.CellRegistration<UICollectionViewCell, PortfolioItemID> { [weak self] cell, _, _ in
            guard let self else { return }
            self.configureSummaryCell(cell)
        }

        let localInsightRegistration = UICollectionView.CellRegistration<UICollectionViewCell, PortfolioItemID> { [weak self] cell, _, itemID in
            guard let self,
                  case .localInsight(let cardID) = itemID
            else {
                return
            }

            self.configureLocalInsightCell(cell, cardID: cardID)
        }

        let chartRegistration = UICollectionView.CellRegistration<PortfolioChartTileCell, PortfolioItemID> { [weak self] cell, _, itemID in
            guard let self else { return }
            self.configureChartCell(cell, itemID: itemID)
        }

        return CollectionViewDataSource(collectionView: collectionView) { collectionView, indexPath, itemID in
            switch itemID {
            case .localSummary:
                collectionView.dequeueConfiguredReusableCell(using: summaryRegistration, for: indexPath, item: itemID)
            case .localInsight:
                collectionView.dequeueConfiguredReusableCell(using: localInsightRegistration, for: indexPath, item: itemID)
            case .totalValueChartTile, .portfolioShareChartTile:
                collectionView.dequeueConfiguredReusableCell(using: chartRegistration, for: indexPath, item: itemID)
            }
        }
    }

    private func applySnapshot(animated: Bool) {
        sectionDescriptors = makeSectionDescriptors()

        var snapshot = NSDiffableDataSourceSnapshot<PortfolioSectionID, PortfolioItemID>()
        snapshot.appendSections(sectionDescriptors.map(\.id))

        for section in sectionDescriptors {
            snapshot.appendItems(section.items, toSection: section.id)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func bindViewModel() {
        observe { [weak self] in
            guard let self else { return }

            let updatedLocalInsightCards = self.viewModel.localInsightCards
            let didLocalInsightsChange = updatedLocalInsightCards != self.localInsightCards
            self.chartViewState = ChartViewState(
                errorText: self.viewModel.errorText,
                isLoading: self.viewModel.isLoading,
                isRefreshing: self.viewModel.isRefreshing
            )

            if didLocalInsightsChange {
                self.localInsightCards = updatedLocalInsightCards
                self.applySnapshot(animated: true)
            }

            self.scheduleChartPreparationIfNeeded(
                token: self.viewModel.chartDataToken,
                response: self.viewModel.response
            )
            self.refreshVisibleCells(
                refreshSummary: false,
                refreshLocalInsights: didLocalInsightsChange,
                refreshCharts: self.preparedChartDataToken == self.viewModel.chartDataToken || self.viewModel.response == nil
            )
        }
    }

    private func scheduleChartPreparationIfNeeded(
        token: Int,
        response: ApiPortfolioHistoryResponse?
    ) {
        guard preparedChartDataToken != token,
              preparingChartDataToken != token
        else {
            return
        }

        chartPreparationTask?.cancel()
        preparingChartDataToken = token

        guard let response else {
            preparedCharts = .empty
            preparedChartDataToken = token
            preparingChartDataToken = nil
            return
        }

        let configuration = chartAdapterConfiguration
        chartPreparationTask = Task.detached(priority: .userInitiated) { [response, configuration] in
            let preparedCharts = PortfolioGraphKitAdapter.makePreparedCharts(
                from: response,
                configuration: configuration
            )
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self,
                      self.preparingChartDataToken == token
                else {
                    return
                }

                self.preparedCharts = preparedCharts
                self.preparedChartDataToken = token
                self.preparingChartDataToken = nil
                self.refreshVisibleCells(refreshSummary: false, refreshLocalInsights: false, refreshCharts: true)
            }
        }
    }

    private func refreshVisibleCells(refreshSummary: Bool, refreshLocalInsights: Bool, refreshCharts: Bool) {
        var didUpdateChartHeight = false

        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let itemID = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath)
            else {
                continue
            }

            switch (itemID, cell) {
            case (.localSummary, _) where refreshSummary:
                configureSummaryCell(cell)
            case (.localInsight(let cardID), _) where refreshLocalInsights:
                configureLocalInsightCell(cell, cardID: cardID)
            case (.totalValueChartTile, let chartCell as PortfolioChartTileCell) where refreshCharts:
                didUpdateChartHeight = configureChartCell(chartCell, itemID: itemID) || didUpdateChartHeight
            case (.portfolioShareChartTile, let chartCell as PortfolioChartTileCell) where refreshCharts:
                didUpdateChartHeight = configureChartCell(chartCell, itemID: itemID) || didUpdateChartHeight
            default:
                break
            }
        }

        if didUpdateChartHeight {
            invalidateChartLayoutImmediately()
        }
    }

    private var visibleChartCells: [PortfolioChartTileCell] {
        collectionView.visibleCells.compactMap { $0 as? PortfolioChartTileCell }
    }

    private func resetVisibleChartInteractions() {
        for cell in visibleChartCells {
            cell.resetInteraction()
        }
    }

    private func registerVisibleChartGestureDependencies() {
        for cell in visibleChartCells {
            registerGestureDependencies(for: cell)
        }
    }

    private func registerGestureDependencies(for cell: PortfolioChartTileCell) {
        let blocker = cell.horizontalInteractionBlockingGestureRecognizer
        let blockerID = ObjectIdentifier(blocker)
        guard !registeredChartInteractionBlockers.contains(blockerID) else {
            return
        }

        registeredChartInteractionBlockers.insert(blockerID)
        collectionView.panGestureRecognizer.require(toFail: blocker)

        if let navigationController {
            navigationController.interactivePopGestureRecognizer?.require(toFail: blocker)
            if #available(iOS 26.0, *) {
                navigationController.interactiveContentPopGestureRecognizer?.require(toFail: blocker)
            }
        }

        (navigationController as? WNavigationController)?.fullWidthBackGestureRecognizerRequireToFail(blocker)
    }

    @discardableResult
    private func configureChartCell(_ cell: PortfolioChartTileCell, itemID: PortfolioItemID) -> Bool {
        let didUpdatePreferredHeight: Bool

        switch itemID {
        case .totalValueChartTile:
            didUpdatePreferredHeight = cell.configure(
                configuration: makeTotalValueChartConfiguration(),
                onRetry: { [weak self] in
                    self?.viewModel.reload(resetHistoryRefreshAttempts: true)
                },
                onPreferredHeightChanged: { [weak self] in
                    self?.scheduleChartLayoutInvalidation()
                }
            )
        case .portfolioShareChartTile:
            didUpdatePreferredHeight = cell.configure(
                configuration: makePortfolioShareChartConfiguration(),
                onRetry: { [weak self] in
                    self?.viewModel.reload(resetHistoryRefreshAttempts: true)
                },
                onPreferredHeightChanged: { [weak self] in
                    self?.scheduleChartLayoutInvalidation()
                }
            )
        case .localSummary, .localInsight:
            didUpdatePreferredHeight = false
        }

        registerGestureDependencies(for: cell)
        return didUpdatePreferredHeight
    }

    private func configureSummaryCell(_ cell: UICollectionViewCell) {
        cell.backgroundColor = .clear
        cell.contentConfiguration = UIHostingConfiguration {
            PortfolioBalanceSummaryView(accountContext: viewModel.accountContext)
        }
        .background {
            Color.clear
        }
        .margins(.all, 0)
    }

    private func configureLocalInsightCell(_ cell: UICollectionViewCell, cardID: PortfolioInsightCardID) {
        guard let card = localInsightCards.first(where: { $0.id == cardID }) else {
            cell.contentConfiguration = nil
            return
        }

        cell.backgroundColor = .clear
        cell.contentConfiguration = UIHostingConfiguration {
            PortfolioInsightCardView(
                card: card,
                legendDisplayMode: insightLegendDisplayModes[cardID, default: .amounts],
                onTap: { [weak self] in
                    self?.toggleInsightLegendDisplayMode(for: cardID)
                },
                onAction: { [weak self] in
                    self?.performAction(for: card)
                }
            )
        }
        .background {
            Color.clear
        }
        .margins(.all, 0)
    }

    private func performAction(for card: PortfolioInsightCardModel) {
        guard let action = card.action else {
            return
        }

        switch action.kind {
        case .fund:
            AppActions.showReceive(accountContext: viewModel.accountContext, chain: nil, title: nil)
        case .swap:
            AppActions.showSwap(
                accountContext: viewModel.accountContext,
                defaultSellingToken: nil,
                defaultBuyingToken: nil,
                defaultSellingAmount: nil,
                push: nil
            )
        case .earn:
            AppActions.showEarn(accountContext: viewModel.accountContext, tokenSlug: nil)
        }
    }

    private func toggleInsightLegendDisplayMode(for cardID: PortfolioInsightCardID) {
        let currentMode = insightLegendDisplayModes[cardID, default: .amounts]
        insightLegendDisplayModes[cardID] = currentMode.next

        guard let indexPath = dataSource.indexPath(for: .localInsight(cardID)),
              let cell = collectionView.cellForItem(at: indexPath)
        else {
            return
        }

        configureLocalInsightCell(cell, cardID: cardID)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        resetVisibleChartInteractions()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else {
            return
        }

        resetVisibleChartInteractions()
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let chartCell = cell as? PortfolioChartTileCell {
            registerGestureDependencies(for: chartCell)
        }
    }

    public func shouldAllowBackSwipe(at point: CGPoint) -> Bool {
        let pointInCollectionView = view.convert(point, to: collectionView)

        for cell in visibleChartCells {
            guard cell.frame.contains(pointInCollectionView) else {
                continue
            }

            let pointInCell = collectionView.convert(pointInCollectionView, to: cell)
            if cell.blocksBackSwipe(at: pointInCell, mainChartLeftSafeInset: backSwipeSafeInset) {
                return false
            }
        }

        return true
    }

    private func makeTotalValueChartConfiguration() -> PortfolioChartTileCellConfiguration {
        PortfolioChartTileCellConfiguration(
            title: lang("Total Value"),
            subtitle: lang("Tracked asset value over time."),
            state: makeChartState(
                chartPresentation: preparedCharts.totalValuePresentation,
                chartKind: .totalValue,
                pieVisible: nil
            ),
            showsUpdatingFooter: false,
            isRefreshing: chartViewState.isRefreshing,
            onLimitedHistoryTap: { [weak self] in
                self?.showLimitedHistoryToast()
            }
        )
    }

    private func makePortfolioShareChartConfiguration() -> PortfolioChartTileCellConfiguration {
        return PortfolioChartTileCellConfiguration(
            title: lang("Portfolio Share"),
            subtitle: lang("Current allocation across tracked assets."),
            state: makeChartState(
                chartPresentation: preparedCharts.portfolioSharePresentation,
                chartKind: .portfolioShare,
                pieVisible: true
            ),
            showsUpdatingFooter: false,
            isRefreshing: false,
            onLimitedHistoryTap: { [weak self] in
                self?.showLimitedHistoryToast()
            }
        )
    }

    private func makeChartState(
        chartPresentation: PortfolioGraphKitAdapter.ChartPresentation?,
        chartKind: PortfolioGraphKind,
        pieVisible: Bool?
    ) -> PortfolioChartTileCellConfiguration.State {
        if let errorText = chartViewState.errorText,
           !preparedCharts.hasChartData {
            return .error(errorText)
        }

        if chartViewState.isLoading && !preparedCharts.hasChartData {
            return .loading
        }

        guard let chartPresentation
        else {
            return .noData
        }

        return .chart(
            presentation: chartPresentation,
            kind: chartKind,
            pieVisible: pieVisible
        )
    }

    private func showLimitedHistoryToast() {
        AppActions.showToast(message: lang("Deep history analysis will be available in upcoming updates."))
    }

    private func observeLanguageChanges() {
        languageObserver = NotificationCenter.default.addObserver(
            forName: .languageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLanguageDidChange()
            }
        }
    }

    private func handleLanguageDidChange() {
        navigationItem.title = lang("Portfolio")
        localInsightCards = viewModel.localInsightCards
        refreshVisibleCells(refreshSummary: true, refreshLocalInsights: true, refreshCharts: true)
    }

    private func invalidateChartLayoutImmediately() {
        isChartLayoutInvalidationScheduled = false
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    private func scheduleChartLayoutInvalidation() {
        guard !isChartLayoutInvalidationScheduled else {
            return
        }

        isChartLayoutInvalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isChartLayoutInvalidationScheduled = false
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    let vc = PortfolioVC(accountContext: AccountContext(source: .current))
    previewNc(vc)
}
#endif

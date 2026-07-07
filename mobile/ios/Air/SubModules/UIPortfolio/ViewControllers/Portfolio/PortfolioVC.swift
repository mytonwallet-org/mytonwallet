import Perception
import SwiftUI
import UIComponents
import UIKit
import WalletCore
import WalletContext

private let portfolioFirstSectionTopSpacing = CGFloat(16)
private let portfolioSectionTopSpacing = CGFloat(24)
private let portfolioHorizontalInset = CGFloat(16)
private let portfolioRangeControlHorizontalInset = CGFloat(21)
private let portfolioRangeControlHeight = CGFloat(44)
private let portfolioRangeControlOverlayHeight = CGFloat(77)

private final class PortfolioCollectionView: UICollectionView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

private final class PortfolioBottomControlBackgroundView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    private func applyTheme() {
        let color = UIColor.air.groupedBackground.resolvedColor(with: traitCollection)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.locations = [0, 1]
        gradientLayer.colors = [
            color.withAlphaComponent(0).cgColor,
            color.withAlphaComponent(0.6).cgColor,
        ]
    }
}

private final class PortfolioRangeSegmentedControl: UISegmentedControl {
    private var backgroundLayer: CALayer?
    private var blurView: UIVisualEffectView?
    private var selectionPillView: UIView?
    private var isPillAnimating = false

    init(titles: [String]) {
        super.init(items: titles)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if #available(iOS 26, *) {
            setupGlassBackgroundIfNeeded()
            blurView?.frame = bounds
            blurView?.layer.cornerRadius = bounds.height / 2
            if !isPillAnimating {
                UIView.performWithoutAnimation { positionSelectionPill() }
            }
        } else {
            let imageViews = subviews.compactMap { $0 as? UIImageView }.prefix(numberOfSegments)
            imageViews.forEach { $0.isHidden = true }

            if let selectorImageView {
                let inset = CGFloat(5)
                selectorImageView.bounds = selectorImageView.bounds.insetBy(dx: inset, dy: inset)
                selectorImageView.image = nil
                selectorImageView.layer.cornerRadius = selectorImageView.bounds.height / 2
                selectorImageView.layer.masksToBounds = true
                selectorImageView.layer.removeAnimation(forKey: "SelectionBounds")
                selectorImageView.isHidden = false
            }

            backgroundLayer?.removeFromSuperlayer()
            let bgLayer = CALayer()
            bgLayer.frame = bounds
            layer.insertSublayer(bgLayer, at: 0)
            backgroundLayer = bgLayer
            
            layer.cornerRadius = bounds.height / 2
            layer.masksToBounds = true
            updateTheme()
        }
    }

    override func sendActions(for controlEvents: UIControl.Event) {
        super.sendActions(for: controlEvents)
        
        guard #available(iOS 26, *), controlEvents.contains(.valueChanged) else { return }
        
        isPillAnimating = true
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5,
            options: [.beginFromCurrentState]
        ) {
            self.positionSelectionPill()
        } completion: { _ in
            self.isPillAnimating = false
            UIView.performWithoutAnimation {
               self.positionSelectionPill()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        apportionsSegmentWidthsByContent = false
        setDividerImage(UIImage(), forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
        setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.label,
        ], for: .normal)
        setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.label,
        ], for: .selected)
    }

    @available(iOS 26, *)
    private func setupGlassBackgroundIfNeeded() {
        guard blurView == nil else { return }

        let empty = UIImage()
        setBackgroundImage(empty, for: .normal, barMetrics: .default)
        setBackgroundImage(empty, for: .highlighted, barMetrics: .default)
        setBackgroundImage(empty, for: .selected, barMetrics: .default)
        setBackgroundImage(empty, for: [.selected, .highlighted], barMetrics: .default)
        backgroundColor = .clear

        let glassEffect = UIGlassEffect()
        let effectView = UIVisualEffectView(effect: glassEffect)
        effectView.backgroundColor = .clear
        effectView.contentView.backgroundColor = .clear
        effectView.layer.cornerCurve = .continuous
        effectView.layer.masksToBounds = true
        effectView.isUserInteractionEnabled = false
        insertSubview(effectView, at: 0)
        blurView = effectView
    }

    @available(iOS 26, *)
    private func positionSelectionPill() {
        guard numberOfSegments > 0, bounds.width > 0, let blurView else { return }

        let segmentWidth = bounds.width / CGFloat(numberOfSegments)
        let inset = CGFloat(4)
        let pillFrame = CGRect(
            x: CGFloat(selectedSegmentIndex) * segmentWidth + inset,
            y: inset,
            width: segmentWidth - inset * 2,
            height: bounds.height - inset * 2
        )
        let cornerRadius = pillFrame.height / 2

        if let pill = selectionPillView {
            pill.frame = pillFrame
            pill.layer.cornerRadius = cornerRadius
        } else {
            let pill = UIView()
            pill.backgroundColor = .label.withAlphaComponent(0.12)
            pill.layer.cornerRadius = cornerRadius
            pill.layer.cornerCurve = .continuous
            pill.isUserInteractionEnabled = false
            pill.frame = pillFrame
            insertSubview(pill, aboveSubview: blurView)
            selectionPillView = pill
        }
    }

    private func updateTheme() {
        if #unavailable(iOS 26) {
            backgroundLayer?.backgroundColor = UIColor.air.headerBackground.resolvedColor(with: traitCollection).cgColor
            selectorImageView?.layer.backgroundColor = UIColor.air.groupedItem.resolvedColor(with: traitCollection).cgColor
        }
    }

    private var selectorImageView: UIImageView? {
        let selectorIndex = numberOfSegments
        guard subviews.indices.contains(selectorIndex),
              let imageView = subviews[selectorIndex] as? UIImageView
        else {
            return nil
        }
        return imageView
    }
}

private enum PortfolioSectionID: Hashable {
    case localSummary
    case localInsights
    case totalValueChart
    case totalPnlChart
    case dailyPnlChart
    case portfolioShareChart
}

private enum PortfolioItemID: Hashable {
    case localSummary
    case localInsight(PortfolioInsightCardID)
    case totalValueChartTile
    case totalPnlChartTile
    case dailyPnlChartTile
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

public final class PortfolioVC: WViewController, UICollectionViewDelegate, WBackSwipeControlling, WSensitiveDataProtocol {
    private struct ChartViewState: Equatable {
        let errorText: String?
        let isLoading: Bool
        let isRefreshing: Bool
        let fadesCurrentData: Bool
    }

    private typealias CollectionViewDataSource = UICollectionViewDiffableDataSource<PortfolioSectionID, PortfolioItemID>
    private let backSwipeSafeInset = CGFloat(30.0)
    private let chartAdapterConfiguration = PortfolioGraphKitAdapter.Configuration(
        maxSeriesCount: nil,
        includeOtherSeries: false
    )
    private var registeredChartInteractionBlockers = Set<ObjectIdentifier>()
    private var isChartLayoutInvalidationScheduled = false
    private var hasEverStartedLoading = false

    private let viewModel: PortfolioVM
    private var sectionDescriptors: [PortfolioSectionDescriptor] = []
    private var overview: PortfolioOverviewModel
    private var localInsightCards: [PortfolioInsightCardModel] = []
    private var chartViewState = ChartViewState(errorText: nil, isLoading: false, isRefreshing: false, fadesCurrentData: false)
    private var preparedCharts = PortfolioGraphKitAdapter.PreparedCharts.empty
    private var preparedChartDataToken = -1
    private var preparingChartDataToken: Int?
    private var chartPreparationTask: Task<Void, Never>?
    private var languageObserver: NSObjectProtocol?
    private lazy var collectionView = makeCollectionView()
    private lazy var bottomControlBackgroundView = PortfolioBottomControlBackgroundView()
    private lazy var rangeSegmentedControl = makeRangeSegmentedControl()
    private lazy var dataSource = makeDataSource()

    public init(accountContext: AccountContext) {
        let viewModel = PortfolioVM(accountContext: accountContext)
        self.viewModel = viewModel
        self.overview = viewModel.overview
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
        view.backgroundColor = .air.groupedBackground
        addCloseNavigationItemIfNeeded()

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        setupRangeSegmentedControl()

        localInsightCards = viewModel.localInsightCards
        overview = viewModel.overview
        applySnapshot(animated: false)
        observeLanguageChanges()
        bindViewModel()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.loadIfNeeded()
        registerVisibleChartGestureDependencies()
    }

    public func updateSensitiveData() {
        refreshVisibleCells(refreshSummary: false, refreshLocalInsights: false, refreshCharts: true)
    }

    private func makeSectionDescriptors() -> [PortfolioSectionDescriptor] {
        var sections: [PortfolioSectionDescriptor] = [
            PortfolioSectionDescriptor(
                id: .localSummary,
                items: [.localSummary],
                layout: .fullWidthTile(estimatedHeight: 105),
                contentInsets: .init(
                    top: portfolioFirstSectionTopSpacing,
                    leading: portfolioHorizontalInset,
                    bottom: 0,
                    trailing: portfolioHorizontalInset
                ),
                interGroupSpacing: 0
            ),
        ]

        if !localInsightCards.isEmpty {
            let localInsightsHeight = PortfolioInsightCardMetrics.totalHeight(for: localInsightCards)
            sections.append(
                    PortfolioSectionDescriptor(
                        id: .localInsights,
                        items: localInsightCards.map { .localInsight($0.id) },
                        layout: .horizontalTiles(
                            itemWidth: 280,
                            estimatedHeight: localInsightsHeight,
                            orthogonalScrolling: .continuousGroupLeadingBoundary
                        ),
                        contentInsets: .init(
                            top: portfolioSectionTopSpacing,
                            leading: portfolioHorizontalInset,
                            bottom: 0,
                            trailing: portfolioHorizontalInset
                        ),
                        interGroupSpacing: 16
                )
            )
        }

        sections.append(contentsOf: [
            PortfolioSectionDescriptor(
                id: .portfolioShareChart,
                items: [.portfolioShareChartTile],
                layout: .fullWidthTile(estimatedHeight: 535),
                contentInsets: .init(
                    top: portfolioSectionTopSpacing,
                    leading: portfolioHorizontalInset,
                    bottom: 0,
                    trailing: portfolioHorizontalInset
                ),
                interGroupSpacing: 0
            ),
            PortfolioSectionDescriptor(
                id: .totalValueChart,
                items: [.totalValueChartTile],
                layout: .fullWidthTile(estimatedHeight: 535),
                contentInsets: .init(
                    top: portfolioSectionTopSpacing,
                    leading: portfolioHorizontalInset,
                    bottom: 0,
                    trailing: portfolioHorizontalInset
                ),
                interGroupSpacing: 0
            ),
            PortfolioSectionDescriptor(
                id: .totalPnlChart,
                items: [.totalPnlChartTile],
                layout: .fullWidthTile(estimatedHeight: 535),
                contentInsets: .init(
                    top: portfolioSectionTopSpacing,
                    leading: portfolioHorizontalInset,
                    bottom: 0,
                    trailing: portfolioHorizontalInset
                ),
                interGroupSpacing: 0
            ),
            PortfolioSectionDescriptor(
                id: .dailyPnlChart,
                items: [.dailyPnlChartTile],
                layout: .fullWidthTile(estimatedHeight: 535),
                contentInsets: .init(
                    top: portfolioSectionTopSpacing,
                    leading: portfolioHorizontalInset,
                    bottom: 32,
                    trailing: portfolioHorizontalInset
                ),
                interGroupSpacing: 0
            ),
        ])

        return sections
    }

    private func makeCollectionView() -> UICollectionView {
        let collectionView = PortfolioCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .air.groupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delaysContentTouches = false
        collectionView.contentInset.bottom = portfolioRangeControlOverlayHeight
        collectionView.verticalScrollIndicatorInsets.bottom = portfolioRangeControlOverlayHeight
        collectionView.allowsSelection = false
        collectionView.delegate = self
        return collectionView
    }

    private func makeRangeSegmentedControl() -> UISegmentedControl {
        let control = PortfolioRangeSegmentedControl(
            titles: PortfolioTimeRange.displayOrder.map(\.title)
        )
        control.selectedSegmentIndex = PortfolioTimeRange.displayOrder.firstIndex(of: viewModel.selectedRange) ?? 0
        control.addTarget(self, action: #selector(rangeSegmentedControlChanged), for: .valueChanged)
        return control
    }

    private func setupRangeSegmentedControl() {
        view.addSubview(bottomControlBackgroundView)
        view.addSubview(rangeSegmentedControl)

        NSLayoutConstraint.activate([
            bottomControlBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomControlBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomControlBackgroundView.topAnchor.constraint(equalTo: rangeSegmentedControl.topAnchor),
            bottomControlBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rangeSegmentedControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: portfolioRangeControlHorizontalInset),
            rangeSegmentedControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -portfolioRangeControlHorizontalInset),
            rangeSegmentedControl.heightAnchor.constraint(equalToConstant: portfolioRangeControlHeight),
            rangeSegmentedControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func updateRangeSegmentedControlSelection(_ range: PortfolioTimeRange) {
        let index = PortfolioTimeRange.displayOrder.firstIndex(of: range) ?? 0
        guard rangeSegmentedControl.selectedSegmentIndex != index else {
            return
        }
        rangeSegmentedControl.selectedSegmentIndex = index
    }

    private func updateRangeSegmentedControlTitles() {
        for (index, range) in PortfolioTimeRange.displayOrder.enumerated() {
            rangeSegmentedControl.setTitle(range.title, forSegmentAt: index)
        }
    }

    @objc
    private func rangeSegmentedControlChanged(_ sender: UISegmentedControl) {
        guard PortfolioTimeRange.displayOrder.indices.contains(sender.selectedSegmentIndex) else {
            return
        }

        resetVisibleChartInteractions()
        resetVisibleChartRanges()
        viewModel.selectRange(PortfolioTimeRange.displayOrder[sender.selectedSegmentIndex])
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
            case .totalValueChartTile, .totalPnlChartTile, .dailyPnlChartTile, .portfolioShareChartTile:
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

        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    private func bindViewModel() {
        observe { [weak self] in
            guard let self else { return }

            let updatedLocalInsightCards = self.viewModel.localInsightCards
            let updatedOverview = self.viewModel.overview
            let didLocalInsightsChange = updatedLocalInsightCards != self.localInsightCards
            let didOverviewChange = updatedOverview != self.overview
            let previousChartViewState = self.chartViewState
            self.updateRangeSegmentedControlSelection(self.viewModel.selectedRange)
            self.chartViewState = ChartViewState(
                errorText: self.viewModel.errorText,
                isLoading: self.viewModel.isLoading,
                isRefreshing: self.viewModel.isRefreshing,
                fadesCurrentData: self.viewModel.isShowingStaleRangeData
            )
            let didChartViewStateChange = self.chartViewState != previousChartViewState
            if !self.hasEverStartedLoading,
               self.chartViewState.isLoading || self.viewModel.responses != nil || self.viewModel.errorText != nil {
                self.hasEverStartedLoading = true
            }
            self.overview = updatedOverview

            if didLocalInsightsChange {
                self.localInsightCards = updatedLocalInsightCards
                self.applySnapshot(animated: true)
            }

            self.scheduleChartPreparationIfNeeded(
                token: self.viewModel.chartDataToken,
                responses: self.viewModel.responses
            )
            self.refreshVisibleCells(
                refreshSummary: didOverviewChange,
                refreshLocalInsights: didLocalInsightsChange,
                refreshCharts: didChartViewStateChange
                    || self.preparedChartDataToken == self.viewModel.chartDataToken
                    || self.viewModel.responses == nil
            )
        }
    }

    private func scheduleChartPreparationIfNeeded(
        token: Int,
        responses: PortfolioHistoryResponses?
    ) {
        guard preparedChartDataToken != token,
              preparingChartDataToken != token
        else {
            return
        }

        chartPreparationTask?.cancel()
        preparingChartDataToken = token

        guard let responses else {
            preparedCharts = .empty
            preparedChartDataToken = token
            preparingChartDataToken = nil
            return
        }

        let configuration = chartAdapterConfiguration
        chartPreparationTask = Task.detached(priority: .userInitiated) { [responses, configuration] in
            let preparedCharts = PortfolioGraphKitAdapter.makePreparedCharts(
                from: responses,
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
            case (.totalPnlChartTile, let chartCell as PortfolioChartTileCell) where refreshCharts:
                didUpdateChartHeight = configureChartCell(chartCell, itemID: itemID) || didUpdateChartHeight
            case (.dailyPnlChartTile, let chartCell as PortfolioChartTileCell) where refreshCharts:
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

    private func resetVisibleChartRanges() {
        for cell in visibleChartCells {
            cell.resetRange()
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
        case .totalPnlChartTile:
            didUpdatePreferredHeight = cell.configure(
                configuration: makeTotalPnlChartConfiguration(),
                onRetry: { [weak self] in
                    self?.viewModel.reload(resetHistoryRefreshAttempts: true)
                },
                onPreferredHeightChanged: { [weak self] in
                    self?.scheduleChartLayoutInvalidation()
                }
            )
        case .dailyPnlChartTile:
            didUpdatePreferredHeight = cell.configure(
                configuration: makeDailyPnlChartConfiguration(),
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
            PortfolioOverviewSectionView(
                accountContext: viewModel.accountContext,
                overview: overview
            )
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
        let localInsightsHeight = PortfolioInsightCardMetrics.totalHeight(for: localInsightCards)
        cell.contentConfiguration = UIHostingConfiguration {
            PortfolioInsightCardView(
                card: card,
                height: localInsightsHeight
            )
        }
        .background {
            Color.clear
        }
        .margins(.all, 0)
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
            state: makeChartState(
                chartPresentation: preparedCharts.totalValuePresentation,
                chartKind: .totalValue,
                pieVisible: nil
            ),
            isRefreshing: chartViewState.isRefreshing,
            fadesCurrentData: chartViewState.fadesCurrentData,
            hidesVerticalAxisLabels: shouldHideVerticalAxisLabels(for: .totalValue),
            onLimitedHistoryTap: { [weak self] in
                self?.showLimitedHistoryToast()
            }
        )
    }

    private func makeTotalPnlChartConfiguration() -> PortfolioChartTileCellConfiguration {
        PortfolioChartTileCellConfiguration(
            title: lang("Total P&L"),
            state: makeChartState(
                chartPresentation: preparedCharts.totalPnlPresentation,
                chartKind: .totalPnl,
                pieVisible: nil
            ),
            isRefreshing: chartViewState.isRefreshing,
            fadesCurrentData: chartViewState.fadesCurrentData,
            hidesVerticalAxisLabels: shouldHideVerticalAxisLabels(for: .totalPnl),
            onLimitedHistoryTap: { [weak self] in
                self?.showLimitedHistoryToast()
            }
        )
    }

    private func makeDailyPnlChartConfiguration() -> PortfolioChartTileCellConfiguration {
        PortfolioChartTileCellConfiguration(
            title: lang("Daily P&L"),
            state: makeChartState(
                chartPresentation: preparedCharts.dailyPnlPresentation,
                chartKind: .dailyPnl,
                pieVisible: nil
            ),
            isRefreshing: chartViewState.isRefreshing,
            fadesCurrentData: chartViewState.fadesCurrentData,
            hidesVerticalAxisLabels: shouldHideVerticalAxisLabels(for: .dailyPnl),
            onLimitedHistoryTap: { [weak self] in
                self?.showLimitedHistoryToast()
            }
        )
    }

    private func makePortfolioShareChartConfiguration() -> PortfolioChartTileCellConfiguration {
        return PortfolioChartTileCellConfiguration(
            title: lang("Portfolio Share"),
            state: makeChartState(
                chartPresentation: preparedCharts.portfolioSharePresentation,
                chartKind: .portfolioShare,
                pieVisible: true
            ),
            isRefreshing: false,
            fadesCurrentData: chartViewState.fadesCurrentData,
            hidesVerticalAxisLabels: shouldHideVerticalAxisLabels(for: .portfolioShare),
            onLimitedHistoryTap: { [weak self] in
                self?.showLimitedHistoryToast()
            }
        )
    }

    private func shouldHideVerticalAxisLabels(for kind: PortfolioGraphKind) -> Bool {
        kind.yAxisRepresentsBaseCurrency && AppStorageHelper.isSensitiveDataHidden
    }

    private func makeChartState(
        chartPresentation: PortfolioGraphKitAdapter.ChartPresentation?,
        chartKind: PortfolioGraphKind,
        pieVisible: Bool?
    ) -> PortfolioChartTileCellConfiguration.State {
        guard hasEverStartedLoading || preparedCharts.hasChartData else {
            return .idle
        }

        if let errorText = chartViewState.errorText,
           !preparedCharts.hasChartData {
            return .error(errorText)
        }

        if (chartViewState.isLoading || preparingChartDataToken != nil) && !preparedCharts.hasChartData {
            return .loading
        }

        if chartViewState.fadesCurrentData {
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
        updateRangeSegmentedControlTitles()
        localInsightCards = viewModel.localInsightCards
        overview = viewModel.overview
        refreshVisibleCells(refreshSummary: true, refreshLocalInsights: true, refreshCharts: true)
    }

    private func invalidateChartLayoutImmediately() {
        isChartLayoutInvalidationScheduled = false
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        }
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

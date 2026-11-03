import Combine
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

/// UIKit screen layout with Market's shared native section renderer.
@MainActor
public final class PerpsHomeVC: WViewController {
    public var onLoadMoreActivity: (() -> Void)?
    public var onVisibilityChanged: ((Bool) -> Void)?
    public var onOpenOnboarding: ((StoriesPresentationSource) -> Void)?
    public var onDismissOnboarding: (() -> Void)?
    private let state: PerpsHomeState
    private let positions = PerpsPositionsSectionDataProvider(id: "positions", showsHeader: false, topSpacing: 0)
    private let collection = PerpsCollectionView()
    private let activity = PerpsActivitySectionDataProvider()
    private var subscriptions = Set<AnyCancellable>()
    private var previousShowsChange: Bool?
    private var previousPositions: PerpsPositionsDisplayData?
    private var previousShowsOnboarding: Bool?
    private var hasCompletedInitialAppearance = false
    private lazy var summaryRegistration = UICollectionView.CellRegistration<PerpsPositionsSummaryCell, PerpsPositionsDisplayData> { cell, _, data in
        cell.configure(data)
    }
    private lazy var onboardingRegistration = UICollectionView.CellRegistration<PerpsOnboardingBannerCell, String> { [weak self] cell, _, _ in
        cell.onOpen = { [weak self, weak cell] in
            guard let self, let cell, state.data.showsOnboarding else { return }
            onOpenOnboarding?(cell.presentationSource())
        }
        cell.onDismiss = { [weak self] in self?.onDismissOnboarding?() }
    }
    private lazy var marketRegistration = UICollectionView.CellRegistration<MarketSectionCell, MarketSectionDisplayData> { [weak self] cell, _, section in
        cell.market.configure(section, onSeeAll: { [weak self] in self?.state.send(.marketSection(section.id)) },
                              onSelect: { [weak self] in self?.state.send(.marketToken(sectionID: section.id, tokenID: $0.id)) })
    }
    private let dividerRegistration = UICollectionView.CellRegistration<PerpsMarketDividerCell, String> { _, _, _ in }
    private lazy var operationRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, PerpsOperationStatusDisplayData> { cell, _, data in
        var content = cell.defaultContentConfiguration()
        content.text = data.title
        content.applyTextStyle(.bodyStrong, scaling: .dynamic)
        content.secondaryText = data.message
        content.secondaryTextProperties.font = WTypography.uiFont(.supporting, scaling: .dynamic)
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.color = .air.secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: "clock.arrow.circlepath")
        cell.contentConfiguration = content
        let dismiss = UIButton(type: .system)
        dismiss.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        dismiss.tintColor = .air.secondaryLabel
        dismiss.accessibilityLabel = lang("Hide")
        dismiss.accessibilityIdentifier = "perps.operation.dismiss"
        dismiss.addAction(UIAction { _ in data.onDismiss() }, for: .touchUpInside)
        dismiss.widthAnchor.constraint(equalToConstant: 44).isActive = true
        dismiss.heightAnchor.constraint(equalToConstant: 44).isActive = true
        cell.accessories = [.customView(configuration: .init(customView: dismiss, placement: .trailing()))]
        cell.accessibilityIdentifier = "perps.operation.banner"
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .air.groupedItem
        background.cornerRadius = 16
        cell.backgroundConfiguration = background
    }

    public init(data: PerpsHomeDisplayData, onAction: @escaping (PerpsHomeAction) -> Void) {
        state = PerpsHomeState(data: data, onAction: onAction)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Futures")
        view.backgroundColor = .air.groupedBackground
        view.addStretchedToBounds(subview: collection)
        collection.onNearBottom = { [weak self] in self?.onLoadMoreActivity?() }
        collection.accessibilityIdentifier = "perps.home.content"
        collection.contentInset.bottom = 32
        positions.onAction = { [weak self] in self?.state.send($0) }
        activity.onSelect = { [weak self] in self?.state.send(.activity($0)) }
        MarketSectionContentView.prepareForUse()
        _ = summaryRegistration; _ = onboardingRegistration; _ = marketRegistration; _ = operationRegistration
        state.$data.sink { [weak self] data in self?.render(data, operation: self?.state.operationStatus) }.store(in: &subscriptions)
        state.$operationStatus.sink { [weak self] status in
            guard let self else { return }
            render(state.data, operation: status)
        }.store(in: &subscriptions)
    }

    private func render(_ data: PerpsHomeDisplayData, operation: PerpsOperationStatusDisplayData?) {
        positions.data = data.positions
        var sections: [any ActivityListViewController.CustomSectionDataProvider] = []
        if data.showsOnboarding {
            sections.append(PerpsContentSection(id: "onboarding", inset: 16) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: onboardingRegistration, for: index, item: "onboarding")
            })
        } else {
            sections.append(PerpsContentSection(id: "summary") { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: summaryRegistration, for: index, item: data.positions)
            })
        }
        if let operation {
            sections.append(PerpsContentSection(id: "operation", inset: 16, bottomSpacing: 16, onSelect: operation.onSelect) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: operationRegistration, for: index, item: operation)
            })
        }
        if !positions.itemIdentifiers.isEmpty { sections.append(positions) }
        let markets = data.marketSections.filter { !$0.tokens.isEmpty }
        if !markets.isEmpty {
            sections.append(PerpsContentSection(id: "market-divider", height: 70) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: dividerRegistration, for: index, item: "market-divider")
            })
            for section in markets {
                sections.append(PerpsContentSection(id: "market:" + section.id, bottomSpacing: section.id == markets.last?.id ? 0 : 24) { [weak self] collection, index in
                    guard let self else { return UICollectionViewCell() }
                    return collection.dequeueConfiguredReusableCell(using: marketRegistration, for: index, item: section)
                })
            }
        }
        activity.accountID = data.positions.accountID
        activity.activities = data.activities
        if !activity.itemIdentifiers.isEmpty { sections.append(activity) }
        let showsChange = PerpsPositionsSummaryCell.showsChange(for: data.positions)
        let animatePositions = data.positions.shouldAnimatePositionsChange(from: previousPositions)
        let animateHeight = previousPositions?.status == .ready && previousShowsChange != nil && previousShowsChange != showsChange
        let animateOnboarding = previousPositions?.accountID == data.positions.accountID
            && previousShowsOnboarding != nil && previousShowsOnboarding != data.showsOnboarding
        let animated = (animatePositions || animateHeight || animateOnboarding) && hasCompletedInitialAppearance
            && viewIfLoaded?.window != nil && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        previousShowsChange = showsChange
        previousPositions = data.positions
        previousShowsOnboarding = data.showsOnboarding
        collection.update(sections: sections, animatingDifferences: animated)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A replacement account can be laid out offscreen before the pager
        // supplies its safe area. Keep the initial header below that inset.
        if !hasCompletedInitialAppearance { scrollToTop(animated: false) }
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasCompletedInitialAppearance {
            scrollToTop(animated: false)
            hasCompletedInitialAppearance = true
        }
        collection.visibleCells.compactMap { $0 as? PerpsPositionsSummaryCell }.forEach { $0.setPrivacyAnimationActive(true) }
        onVisibilityChanged?(true)
    }
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        collection.visibleCells.compactMap { $0 as? PerpsPositionsSummaryCell }.forEach { $0.setPrivacyAnimationActive(false) }
        onVisibilityChanged?(false)
    }
    public func update(data: PerpsHomeDisplayData) { state.update(data) }
    /// Embedded roots supply their chrome insets; standalone screens use UIKit's automatic adjustment.
    public func updateScrollInsets(_ safeAreaInsets: UIEdgeInsets) {
        loadViewIfNeeded()
        var insets = safeAreaInsets
        insets.bottom += 32
        guard collection.contentInsetAdjustmentBehavior != .never || collection.contentInset != insets else { return }
        let wasAtTop = abs(collection.contentOffset.y + collection.adjustedContentInset.top) < 0.5
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset = insets
        if wasAtTop || !hasCompletedInitialAppearance { scrollToTop(animated: false) }
    }
    public func updateOperationStatus(_ status: PerpsOperationStatusDisplayData?) { state.operationStatus = status }
    public override func scrollToTop(animated: Bool) { collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: animated) }
    public func makePositionsListController() -> PerpsPositionsVC { PerpsPositionsVC(state: state) }
}

@MainActor
public final class PerpsPositionsVC: WViewController {
    public var onLoadMoreActivity: (() -> Void)?
    public var onVisibilityChanged: ((Bool) -> Void)?
    private let state: PerpsHomeState
    private let positions = PerpsPositionsSectionDataProvider(id: "positions", showsHeader: false, previewLimit: nil)
    private let collection = PerpsCollectionView()
    private var subscription: AnyCancellable?
    private var previousPositions: PerpsPositionsDisplayData?
    public init(data: PerpsPositionsDisplayData, onAction: @escaping (PerpsHomeAction) -> Void) {
        state = PerpsHomeState(data: .init(positions: data), onAction: onAction)
        super.init(nibName: nil, bundle: nil)
    }
    fileprivate init(state: PerpsHomeState) { self.state = state; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Open Positions")
        view.backgroundColor = .air.groupedBackground
        view.addStretchedToBounds(subview: collection)
        collection.onNearBottom = { [weak self] in self?.onLoadMoreActivity?() }
        collection.accessibilityIdentifier = "perps.positions.list"
        collection.contentInset.bottom = 32
        positions.onAction = { [weak self] in self?.state.send($0) }
        subscription = state.$data.sink { [weak self] data in
            guard let self else { return }
            positions.data = data.positions
            let animated = data.positions.shouldAnimatePositionsChange(from: previousPositions)
                && viewIfLoaded?.window != nil && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
            previousPositions = data.positions
            collection.update(sections: [positions], animatingDifferences: animated)
        }
    }
    public override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onVisibilityChanged?(true) }
    public override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); onVisibilityChanged?(false) }
    public func update(data: PerpsPositionsDisplayData) {
        var snapshot = state.data
        snapshot.positions = data
        state.update(snapshot)
    }
}

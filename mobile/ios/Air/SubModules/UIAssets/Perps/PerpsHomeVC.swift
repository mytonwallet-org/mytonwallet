import SwiftUI
import UIActivityList
import UIComponents
import UIKit
import WalletContext
import WalletCore

private typealias PerpsSection = ActivityListViewController.CustomSectionDescriptor

@MainActor
public final class PerpsHomeVC: WViewController {
    public var onLoadMoreActivity: (() -> Void)?
    public var onVisibilityChanged: ((Bool) -> Void)?
    public var onOpenOnboarding: ((StoriesPresentationSource) -> Void)?
    public var onDismissOnboarding: (() -> Void)?
    private var data: PerpsHomeDisplayData
    private let onAction: (PerpsHomeAction) -> Void
    private let positions = PerpsPositionsSectionDataProvider(id: "positions", showsHeader: false, topSpacing: 0)
    private let balanceWithdrawal = PerpsBalanceWithdrawalSectionDataProvider()
    private let collection = PerpsCollectionView()
    private let activity = PerpsActivitySectionDataProvider()
    private var previousShowsChange: Bool?
    private var previousPositions: PerpsPositionsDisplayData?
    private var previousShowsOnboarding: Bool?
    private var hasCompletedInitialAppearance = false
    private lazy var summaryRegistration = UICollectionView.CellRegistration<PerpsPositionsSummaryCell, PerpsPositionsDisplayData> { cell, _, data in
        cell.configure(data)
    }
    private lazy var onboardingRegistration = UICollectionView.CellRegistration<PerpsOnboardingBannerCell, String> { [weak self] cell, _, _ in
        cell.onOpen = { [weak self, weak cell] in
            guard let self, let cell, data.showsOnboarding else { return }
            onOpenOnboarding?(cell.presentationSource())
        }
        cell.onDismiss = { [weak self] in self?.onDismissOnboarding?() }
    }
    private lazy var marketRegistration = UICollectionView.CellRegistration<MarketSectionCell, MarketSectionDisplayData> { [weak self] cell, _, section in
        guard let self else { return }
        let margins = collection.directionalLayoutMargins
        cell.market.configure(section, insets: .init(top: 0, leading: margins.leading + 16, bottom: 0, trailing: margins.trailing + 16),
                              onSeeAll: { [weak self] in self?.onAction(.marketSection(section.id)) },
                              onSelect: { [weak self] in self?.onAction(.marketToken(sectionID: section.id, tokenID: $0.id)) })
    }
    private let dividerRegistration = UICollectionView.CellRegistration<PerpsMarketDividerCell, String> { _, _, _ in }
    private let accountNoticeRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, message in
        cell.contentConfiguration = UIHostingConfiguration {
            TradeNoticeView(title: "", message: message, isInformational: true)
        }.margins(.all, 0)
        cell.accessibilityIdentifier = "perps.accountNotice"
    }
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
        self.data = data
        self.onAction = onAction
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
        positions.onAction = { [weak self] in self?.onAction($0) }
        balanceWithdrawal.onSelect = { [weak self] in self?.onAction(.withdrawBalance) }
        activity.onSelect = { [weak self] in self?.onAction(.activity($0)) }
        MarketSectionContentView.prepareForUse()
        _ = summaryRegistration; _ = onboardingRegistration; _ = marketRegistration; _ = operationRegistration; _ = accountNoticeRegistration
        render()
    }

    public func update(data: PerpsHomeDisplayData) {
        self.data = data
        if isViewLoaded { render() }
    }

    private func render() {
        let data = data
        positions.data = data.positions
        var sections: [any ActivityListViewController.CustomSectionDataProvider] = []
        if let accountNotice = data.accountNotice {
            sections.append(PerpsSection(id: "account-notice", contentInsets: .init(top: 8, leading: 16, bottom: 0, trailing: 16)) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: accountNoticeRegistration, for: index, item: accountNotice)
            })
        } else if data.showsOnboarding {
            sections.append(PerpsSection(id: "onboarding", contentInsets: .init(top: 0, leading: 16, bottom: 0, trailing: 16)) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: onboardingRegistration, for: index, item: "onboarding")
            })
        } else if data.positions.status != .ready || data.positions.hasOpenPositions {
            sections.append(PerpsSection(id: "summary", contentInsets: .zero) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: summaryRegistration, for: index, item: data.positions)
            })
        }
        if let operation = data.operationStatus {
            sections.append(PerpsSection(id: "operation", contentInsets: .init(top: 0, leading: 16, bottom: 16, trailing: 16),
                                         onSelect: operation.onSelect) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: operationRegistration, for: index, item: operation)
            })
        }
        if data.accountNotice == nil, !positions.itemIdentifiers.isEmpty { sections.append(positions) }
        balanceWithdrawal.data = data.accountNotice == nil ? data.balanceWithdrawal : nil
        if !balanceWithdrawal.itemIdentifiers.isEmpty { sections.append(balanceWithdrawal) }
        if let lastMarketID = data.marketSections.last?.id {
            sections.append(PerpsSection(id: "market-divider", height: 70) { [weak self] collection, index in
                guard let self else { return UICollectionViewCell() }
                return collection.dequeueConfiguredReusableCell(using: dividerRegistration, for: index, item: "market-divider")
            })
            for var section in data.marketSections {
                for index in section.tokens.indices { section.tokens[index].isStale = data.isMarketStale }
                let bottomSpacing: CGFloat = section.id == lastMarketID ? 0 : 24
                let margins = collection.directionalLayoutMargins
                // Market sections apply their own insets so carousel cells are recycled at the viewport edges
                sections.append(PerpsSection(id: "market:" + section.id, contentInsets: .init(top: 0, leading: -margins.leading, bottom: bottomSpacing, trailing: -margins.trailing)) { [weak self] collection, index in
                    guard let self else { return UICollectionViewCell() }
                    return collection.dequeueConfiguredReusableCell(using: marketRegistration, for: index, item: section)
                })
            }
        }
        activity.activities = data.activities
        activity.isStale = data.isActivityStale
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
    // Embedded roots supply insets even when a replacement child has no inherited safe area
    public func updateScrollInsets(_ safeAreaInsets: UIEdgeInsets, layoutMargins: UIEdgeInsets) {
        loadViewIfNeeded()
        if collection.updateHorizontalMargins(layoutMargins) { render() }
        let topInset = safeAreaInsets.top == 0 ? 16 : safeAreaInsets.top
        let insets = UIEdgeInsets(top: topInset, left: 0, bottom: safeAreaInsets.bottom + 32, right: 0)
        guard collection.contentInsetAdjustmentBehavior != .never || collection.contentInset != insets else { return }
        let wasAtTop = abs(collection.contentOffset.y + collection.adjustedContentInset.top) < 0.5
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset = insets
        if wasAtTop || !hasCompletedInitialAppearance { scrollToTop(animated: false) }
    }
    public override func scrollToTop(animated: Bool) { collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: animated) }
}

@MainActor
public final class PerpsPositionsVC: WViewController {
    public var onVisibilityChanged: ((Bool) -> Void)?
    private var data: PerpsPositionsDisplayData
    private let onAction: (PerpsHomeAction) -> Void
    private let positions = PerpsPositionsSectionDataProvider(id: "positions", showsHeader: false, previewLimit: nil)
    private let collection = PerpsCollectionView()
    private var previousPositions: PerpsPositionsDisplayData?
    public init(data: PerpsPositionsDisplayData, onAction: @escaping (PerpsHomeAction) -> Void) {
        self.data = data
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Open Positions")
        view.backgroundColor = .air.groupedBackground
        view.addStretchedToBounds(subview: collection)
        collection.accessibilityIdentifier = "perps.positions.list"
        collection.contentInset.bottom = 32
        positions.onAction = { [weak self] in self?.onAction($0) }
        render()
    }
    public override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onVisibilityChanged?(true) }
    public override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); onVisibilityChanged?(false) }
    public func update(data: PerpsPositionsDisplayData) {
        self.data = data
        if isViewLoaded { render() }
    }
    private func render() {
        positions.data = data
        let animated = data.shouldAnimatePositionsChange(from: previousPositions)
            && viewIfLoaded?.window != nil && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        previousPositions = data
        collection.update(sections: [positions], animatingDifferences: animated)
    }
}

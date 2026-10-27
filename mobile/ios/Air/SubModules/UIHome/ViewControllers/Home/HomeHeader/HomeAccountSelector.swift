//
//  HomeAccountSelector.swift
//
//  Created by nikstar on 19.11.2025.
//

import Combine
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies

public final class HomeAccountSelector: UIView, UICollectionViewDelegate {
    public enum Mode {
        case home
        case sidebar
    }

    private let viewModel: HomeHeaderViewModel
    private let mode: Mode
    private var selectionOverrideAccountId: String?
    private var selectedAccountId: String?
    private var currentLayoutMetrics: HomeCardLayoutMetrics = .screen
    private var pendingSelectionScroll = false
    private var pendingSelectionAnimated = false
    private var pendingSelectionCrossfade = false
    private var pendingSelectionRetryTask: Task<Void, Never>?
    private var accountContexts: [String: AccountContext] = [:]
    private var isUpdatingLayoutMetrics = false
    private var motionEnvironmentObservation: AnyCancellable?
    private var backgroundPreparation: Task<Void, Never>?
    private weak var edgeGradientLeading: UIView?
    private weak var edgeGradientTrailing: UIView?
    private let edgeGradientAnimator = HomeCardEdgeGradientAnimator()
    private lazy var scrollActivity = ScrollActivityMonitor { [weak self] isScrolling in
        self?.viewModel.isAccountScrolling = isScrolling
        if isScrolling {
            self?.backgroundPreparation?.cancel()
            self?.backgroundPreparation = nil
        } else {
            self?.prepareNeighborBackgrounds()
        }
        #if DEBUG || HOME_FRAME_PROBE
        if isScrolling { HomeFrameProbe.shared.begin() }
        #endif
    }

    private enum Section {
        case main
    }
    private enum Item: Hashable {
        case account(String)
    }

    private var collectionView: _CollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    var contentMargins = NSDirectionalEdgeInsets(top: 0, leading: compactInsetSectionHorizontalPadding, bottom: 0, trailing: compactInsetSectionHorizontalPadding) {
        didSet {
            guard oldValue != contentMargins else { return }
            setNeedsLayout()
        }
    }

    public var minimumHomeCardFontScale: CGFloat = 1 {
        didSet {
            guard oldValue != minimumHomeCardFontScale else { return }
            updateVisibleCardsLayout()
        }
    }

    public override var safeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { _ = newValue }
    }

    public convenience init(accountSource: AccountSource = .current, mode: Mode = .home) {
        self.init(viewModel: HomeHeaderViewModel(accountSource: accountSource), mode: mode)
    }

    public var onSelect: (String) -> Void {
        get { viewModel.onSelect }
        set { viewModel.onSelect = newValue }
    }

    public func setCardEffectsActive(_ active: Bool) {
        viewModel.isVisible = active
        if active { prepareNeighborBackgrounds() }
        else { backgroundPreparation?.cancel(); backgroundPreparation = nil }
    }

    /// The host owns the gradients and their layout; the selector owns their scroll timing.
    public func setEdgeGradients(leading: UIView, trailing: UIView) {
        edgeGradientLeading = leading
        edgeGradientTrailing = trailing
        updateEdgeGradients(animated: false)
    }

    private var carouselMotionEnabled: Bool {
        let environment = CardBackgroundAnimationEnvironment.shared
        return environment.cardEffectsEnabled && environment.animationsEnabled
            && !environment.lowPowerMode && !environment.reduceMotion
    }

    var usesCoverFlow: Bool {
        carouselMotionEnabled && !viewModel.isCollapsed && !viewModel.isCardHidden
    }

    private func updateEdgeGradients(animated: Bool) {
        guard let leading = edgeGradientLeading, let trailing = edgeGradientTrailing else { return }
        let away = viewModel.isAccountScrolling && !viewModel.isCollapsed
        let direction: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        edgeGradientAnimator.update(
            leading: leading, trailing: trailing,
            leadingOffset: away ? -direction * leading.bounds.width : 0,
            trailingOffset: away ? direction * trailing.bounds.width : 0,
            animated: animated && window != nil, motionEnabled: carouselMotionEnabled
        )
    }

    init(viewModel: HomeHeaderViewModel, mode: Mode = .home) {
        self.viewModel = viewModel
        self.mode = mode
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        collectionView = _CollectionView(frame: .zero, collectionViewLayout: makeLayout())

        let homeHeaderViewModel = self.viewModel

        let cellRegistration = UICollectionView.CellRegistration<HomeCard, String> { [weak self] cell, _, accountId in
            guard let self else { return }
            let accountContext = accountContext(for: accountId)
            cell.configure(
                headerViewModel: homeHeaderViewModel,
                accountContext: accountContext,
                layout: self.currentLayoutMetrics,
                minimumHomeCardFontScale: self.minimumHomeCardFontScale
            )
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .account(let id):
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
            }
        }

        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.isScrollEnabled = false
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.isHidden = true
            collectionView.bottomEdgeEffect.isHidden = true
            collectionView.rightEdgeEffect.isHidden = true
            collectionView.leftEdgeEffect.isHidden = true
        }
        collectionView.delegate = self

        setupObservers()
    }

    private func setupObservers() {
        motionEnvironmentObservation = CardBackgroundAnimationEnvironment.shared.objectWillChange
            .receive(on: RunLoop.main).sink { [weak self] in
                self?.collectionView.collectionViewLayout.invalidateLayout()
                self?.updateEdgeGradients(animated: false)
            }
        observe { [weak self] in
            guard let self else { return }
            // Track these even before the host has attached its gradient views.
            _ = viewModel.isAccountScrolling
            _ = viewModel.isCollapsed
            updateEdgeGradients(animated: true)
        }
        observe { [weak self] in
            guard let self else { return }
            _ = viewModel.isCollapsed
            _ = viewModel.isCardHidden
            collectionView.collectionViewLayout.invalidateLayout()
        }
        observe { [weak self] in
            guard let self else { return }

            let accountIds = makeAccountIds()
            let newItems = accountIds.map(Item.account)
            let currentItems = dataSource.snapshot().itemIdentifiers
            evictUnusedAccountContexts(keeping: accountIds)
            if newItems != currentItems {
                HomeTrace.record("cards.snapshot", "selector=\(ObjectIdentifier(self)) oldCount=\(currentItems.count) newCount=\(newItems.count)")
                pendingSelectionScroll = true
                var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
                snapshot.appendSections([.main])
                snapshot.appendItems(newItems)
                dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                    self?.scrollToSelectedIfPossible()
                }
            }
            syncSelection(with: accountIds)
        }

        if viewModel.accountSource == .current {
            observe { [weak self] in
                guard let self else { return }
                syncSelection(with: makeAccountIds())
            }
        }
    }

    private func makeAccountIds() -> [String] {
        return switch viewModel.accountSource {
        case .accountId(let accountId):
            [accountId]
        case .current:
            makeCurrentAccountIds()
        case .constant(let account):
            [account.id]
        }
    }

    private func makeCurrentAccountIds() -> [String] {
        switch mode {
        case .home:
            return Array(viewModel.accountStore.orderedAccountIds)
        case .sidebar:
            return Array(viewModel.accountStore.orderedAccountIdsWithTemporary)
        }
    }

    private func syncSelection(with accountIds: [String]) {
        if case .sidebar = mode {
            if let selectionOverrideAccountId, !accountIds.contains(selectionOverrideAccountId) {
                self.selectionOverrideAccountId = nil
            }
            viewModel.cardEffectsAccountIdOverride = selectionOverrideAccountId
        }

        let accountId = switch viewModel.accountSource {
        case .accountId(let accountId):
            accountId
        case .current:
            if case .sidebar = mode,
               let selectionOverrideAccountId,
               accountIds.contains(selectionOverrideAccountId) {
                selectionOverrideAccountId
            } else {
                viewModel.currentAccountId
            }
        case .constant(let account):
            account.id
        }
        updateSelection(to: accountId, animated: false)
    }

    private func updateSelection(to accountId: String, animated: Bool) {
        guard selectedAccountId != accountId || pendingSelectionScroll else { return }
        if selectedAccountId != accountId {
            // Swipes update selectedAccountId before activating the account, so only external
            // selections crossfade. Keep this intent across deferred layout/scroll retries.
            pendingSelectionCrossfade = mode == .home && selectedAccountId != nil && !animated
        }
        selectedAccountId = accountId
        pendingSelectionScroll = true
        pendingSelectionAnimated = animated
        scrollToSelectedIfPossible()
        if !isUserScrolling { prepareNeighborBackgrounds() }
    }

    private func prepareNeighborBackgrounds() {
        backgroundPreparation?.cancel()
        guard window != nil, viewModel.isVisible, !viewModel.isAccountScrolling,
              let selectedAccountId else { return }
        let ids = makeAccountIds()
        guard let index = ids.firstIndex(of: selectedAccountId) else { return }
        let neighbors = [index - 1, index + 1].filter { ids.indices.contains($0) }.map { ids[$0] }
        backgroundPreparation = Task { [weak self] in
            // Do not compete with the account commit or the first resumed frame.
            try? await Task.sleep(for: .milliseconds(300))
            for id in neighbors {
                guard !Task.isCancelled, let self, window != nil, viewModel.isVisible,
                      !viewModel.isAccountScrolling else { return }
                await MtwCardBackgroundView.prepareBackground(nft: accountContext(for: id).nft)
            }
        }
    }

    private func accountContext(for accountId: String) -> AccountContext {
        if let accountContext = accountContexts[accountId] {
            return accountContext
        }
        let accountContext = AccountContext(accountId: accountId)
        accountContexts[accountId] = accountContext
        return accountContext
    }

    private func evictUnusedAccountContexts(keeping accountIds: [String]) {
        let activeAccountIds = Set(accountIds)
        accountContexts = accountContexts.filter { activeAccountIds.contains($0.key) }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, env in
            let width = env.container.effectiveContentSize.width
            guard let self else { return nil }
            let metrics = width > 0 ? HomeCardLayoutMetrics.forContainerWidth(width, contentMargins: contentMargins) : currentLayoutMetrics
            return makeSection(for: metrics)
        }
    }

    private func makeSection(for metrics: HomeCardLayoutMetrics) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(.absolute(metrics.itemWidth), .absolute(metrics.itemHeight)))

        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(.absolute(metrics.itemWidth), .absolute(metrics.itemHeight)), subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        if #available(iOS 17.0, *) {
            section.orthogonalScrollingProperties.decelerationRate = .fast
        }
        section.contentInsets = .init(top: 0, leading: metrics.leadingInset, bottom: 0, trailing: metrics.trailingInset)
        section.interGroupSpacing = metrics.spacing

        section.visibleItemsInvalidationHandler = { [weak self] items, scrollOffset, env in
            guard let self else { return }
            guard !items.isEmpty else { return }
            var minDistance: CGFloat = .infinity
            var minDistanceIndex = 0

            let origin = -(collectionView.horizontalScrollView?.adjustedContentInset.left ?? 0)
            let offset = collectionView.horizontalScrollView?.contentOffset.x ?? scrollOffset.x
            let fractionalIndex = (offset - origin) / metrics.itemWidthWithSpacing
            let usesCoverFlow = self.usesCoverFlow
            for item in items {
                let idx = CGFloat(item.indexPath.row)
                let position = idx - fractionalIndex
                let pose = HomeCardCarouselPose.make(position: position, width: metrics.itemWidth, enabled: usesCoverFlow)
                item.transform3D = pose.transform
                item.center.x = metrics.leadingInset + metrics.itemWidth / 2 + idx * metrics.itemWidthWithSpacing + pose.offset
                item.zIndex = 10_000 - Int(min(100, abs(position)) * 100)

                let absDistance = abs(position)
                if absDistance < minDistance {
                    minDistance = absDistance
                    minDistanceIndex = item.indexPath.row
                }
            }

            self.updateFocusedItem(idx: minDistanceIndex)
        }

        return section
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if collectionView.frame != bounds {
            collectionView.frame = bounds
        }
        updateLayoutMetricsIfNeeded()
        updateEdgeGradients(animated: true)
        if let horizontalScrollView = collectionView.horizontalScrollView {
            scrollActivity.attach(to: horizontalScrollView)
        }
        if pendingSelectionScroll {
            scrollToSelectedIfPossible()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            scrollActivity.detach()
            backgroundPreparation?.cancel()
            backgroundPreparation = nil
        }
        guard window != nil, selectedAccountId != nil else { return }
        pendingSelectionScroll = true
        scrollToSelectedIfPossible()
    }

    private func updateLayoutMetricsIfNeeded() {
        let newMetrics = bounds.width > 0 ? HomeCardLayoutMetrics.forContainerWidth(bounds.width, contentMargins: contentMargins) : .screen
        guard newMetrics != currentLayoutMetrics else { return }
        HomeTrace.record("cards.invalidate", "selector=\(ObjectIdentifier(self)) reason=width oldWidth=\(currentLayoutMetrics.itemWidth) newWidth=\(newMetrics.itemWidth)")
        currentLayoutMetrics = newMetrics
        invalidateIntrinsicContentSize()
        isUpdatingLayoutMetrics = true
        UIView.performWithoutAnimation {
            updateVisibleCardsLayout()
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
        Task { @MainActor [weak self] in
            self?.isUpdatingLayoutMetrics = false
        }
        pendingSelectionScroll = true
        scrollToSelectedIfPossible()
    }

    private func updateVisibleCardsLayout() {
        collectionView?.visibleCells.forEach { cell in
            (cell as? HomeCard)?.updateLayoutMetrics(
                currentLayoutMetrics,
                minimumHomeCardFontScale: minimumHomeCardFontScale
            )
        }
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: currentLayoutMetrics.itemHeight)
    }

    public override func safeAreaInsetsDidChange() {
    }

    func updateFocusedItem(idx: Int) {
        guard !isUpdatingLayoutMetrics, isUserScrolling else { return }
        guard case .account(let id) = dataSource.itemIdentifier(for: IndexPath(item: idx, section: 0)) else { return }
        guard selectedAccountId != id else { return }
        selectedAccountId = id
        pendingSelectionCrossfade = false
        viewModel.onSelect(id)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    }

    public func setSelectionOverride(accountId: String?, animated: Bool) {
        selectionOverrideAccountId = accountId
        syncSelection(with: makeAccountIds())
        if animated {
            pendingSelectionAnimated = true
            scrollToSelectedIfPossible()
        }
    }

    private func scrollToSelectedIfPossible() {
        guard pendingSelectionScroll else { return }
        guard window != nil else { return }
        guard bounds.width > 0, collectionView.bounds.width > 0 else { return }
        guard let selectedAccountId else { return }
        guard let indexPath = dataSource.indexPath(for: .account(selectedAccountId)) else { return }
        guard !isUserScrolling else {
            schedulePendingSelectionRetryIfNeeded()
            return
        }

        collectionView.layoutIfNeeded()
        guard let horizontalScrollView = collectionView.horizontalScrollView, horizontalScrollView.bounds.width > 0 else {
            schedulePendingSelectionRetryIfNeeded()
            return
        }

        let targetOffsetX = targetOffsetX(for: indexPath)
        guard maxOffsetX(for: horizontalScrollView) + 0.5 >= targetOffsetX else {
            HomeTrace.record("cards.invalidate", "selector=\(ObjectIdentifier(self)) reason=selection-retry targetX=\(targetOffsetX) maxX=\(maxOffsetX(for: horizontalScrollView))")
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.setNeedsLayout()
            schedulePendingSelectionRetryIfNeeded()
            return
        }

        pendingSelectionRetryTask?.cancel()
        pendingSelectionRetryTask = nil
        scrollActivity.attach(to: horizontalScrollView)
        if pendingSelectionAnimated { scrollActivity.beginScrolling() }
        let targetOffset = CGPoint(x: clampedOffsetX(targetOffsetX, in: horizontalScrollView), y: horizontalScrollView.contentOffset.y)
        let shouldCrossfade = pendingSelectionCrossfade && !pendingSelectionAnimated
            && abs(horizontalScrollView.contentOffset.x - targetOffset.x) > 0.5
            && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        if shouldCrossfade {
            UIView.transition(with: collectionView, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
                UIView.performWithoutAnimation {
                    horizontalScrollView.setContentOffset(targetOffset, animated: false)
                    self.collectionView.layoutIfNeeded()
                }
            }
        } else {
            horizontalScrollView.setContentOffset(targetOffset, animated: pendingSelectionAnimated)
        }
        pendingSelectionScroll = false
        pendingSelectionAnimated = false
        pendingSelectionCrossfade = false
    }

    private func targetOffsetX(for indexPath: IndexPath) -> CGFloat {
        CGFloat(indexPath.item) * currentLayoutMetrics.itemWidthWithSpacing
    }

    private func maxOffsetX(for scrollView: UIScrollView) -> CGFloat {
        max(-scrollView.adjustedContentInset.left, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right)
    }

    private func clampedOffsetX(_ offsetX: CGFloat, in scrollView: UIScrollView) -> CGFloat {
        let minOffsetX = -scrollView.adjustedContentInset.left
        return min(max(offsetX, minOffsetX), maxOffsetX(for: scrollView))
    }

    private func schedulePendingSelectionRetryIfNeeded() {
        guard pendingSelectionRetryTask == nil else { return }
        pendingSelectionRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.pendingSelectionRetryTask = nil
            self?.scrollToSelectedIfPossible()
        }
    }

    private var isUserScrolling: Bool {
        guard let horizontalScrollView = collectionView.horizontalScrollView else { return false }
        return horizontalScrollView.isTracking || horizontalScrollView.isDecelerating
    }
}

private final class _CollectionView: UICollectionView {

    // hides unwanted animation of ScrollEdgeEffect view (iOS 26.1)
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        if subview.layer.animationKeys() != nil {
            subview.layer.removeAllAnimationsRecursive()
        }
    }

    var horizontalScrollView: UIScrollView? {
        for subview in subviews {
            if let scrollView = subview as? UIScrollView {
                return scrollView
            }
        }
        return nil
    }
}

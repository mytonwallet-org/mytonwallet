//
//  HomeAccountSelector.swift
//
//  Created by nikstar on 19.11.2025.
//

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
    private var pendingSelectionRetryTask: Task<Void, Never>?
    private var accountContexts: [String: AccountContext] = [:]
    private var isUpdatingLayoutMetrics = false

    private enum Section {
        case main
    }
    private enum Item: Hashable {
        case account(String)
    }

    private var collectionView: _CollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

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
        observe { [weak self] in
            guard let self else { return }

            let accountIds = makeAccountIds()
            let newItems = accountIds.map(Item.account)
            let currentItems = dataSource.snapshot().itemIdentifiers
            evictUnusedAccountContexts(keeping: accountIds)
            if newItems != currentItems {
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
        if case .sidebar = mode,
           let selectionOverrideAccountId,
           !accountIds.contains(selectionOverrideAccountId) {
            self.selectionOverrideAccountId = nil
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
        selectedAccountId = accountId
        pendingSelectionScroll = true
        pendingSelectionAnimated = animated
        scrollToSelectedIfPossible()
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
            let metrics = width > 0 ? HomeCardLayoutMetrics.forContainerWidth(width) : self?.currentLayoutMetrics ?? .screen
            return self?.makeSection(for: metrics)
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
        section.contentInsets = .init(top: 0, leading: metrics.inset, bottom: 0, trailing: metrics.inset)
        section.interGroupSpacing = metrics.spacing

        section.visibleItemsInvalidationHandler = { [weak self] items, scrollOffset, env in
            guard let self else { return }
            guard !items.isEmpty else { return }
            var minDistance: CGFloat = .infinity
            var minDistanceIndex = 0

            for item in items {
                let idx = CGFloat(item.indexPath.row)
                let position = idx - scrollOffset.x/metrics.itemWidthWithSpacing

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
        if collectionView.frame != bounds {
            collectionView.frame = bounds
        }
        updateLayoutMetricsIfNeeded()
        if pendingSelectionScroll {
            scrollToSelectedIfPossible()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, selectedAccountId != nil else { return }
        pendingSelectionScroll = true
        scrollToSelectedIfPossible()
    }

    private func updateLayoutMetricsIfNeeded() {
        let newMetrics = bounds.width > 0 ? HomeCardLayoutMetrics.forContainerWidth(bounds.width) : .screen
        guard newMetrics != currentLayoutMetrics else { return }
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
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.setNeedsLayout()
            schedulePendingSelectionRetryIfNeeded()
            return
        }

        pendingSelectionRetryTask?.cancel()
        pendingSelectionRetryTask = nil
        horizontalScrollView.setContentOffset(
            CGPoint(x: clampedOffsetX(targetOffsetX, in: horizontalScrollView), y: horizontalScrollView.contentOffset.y),
            animated: pendingSelectionAnimated
        )
        pendingSelectionScroll = false
        pendingSelectionAnimated = false
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

//
//  Section.swift
//  MyTonWalletAir
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

class HomeAccountSelector: UIView, UICollectionViewDelegate {
    
    private let viewModel: HomeHeaderViewModel
    private var selectedAccountId: String?
    
    private enum Section {
        case main
    }
    private enum Item: Hashable {
        case account(String)
    }
    
    private var collectionView: _CollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    override var safeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { _ = newValue }
    }
    
    init(viewModel: HomeHeaderViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        collectionView = _CollectionView(frame: .zero, collectionViewLayout: makeLayout())
        
        let homeHeaderViewModel = self.viewModel
        
        let cellRegistration = UICollectionView.CellRegistration<HomeCard, String> { cell, _, accountId in
            let accountContext = AccountContext(accountId: accountId)
            cell.configure(headerViewModel: homeHeaderViewModel, accountContext: accountContext)
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
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.main])
            snapshot.appendItems(accountIds.map(Item.account))
            dataSource.apply(snapshot, animatingDifferences: false)
            syncSelection(with: accountIds)
        }
        
        if viewModel.accountSource == .current {
            observe { [weak self] in
                guard let self else { return }
                updateSelection(to: viewModel.currentAccountId, animated: false)
            }
        }
    }
    
    private func makeAccountIds() -> [String] {
        switch viewModel.accountSource {
        case .accountId(let accountId):
            [accountId]
        case .current:
            Array(viewModel.accountStore.orderedAccountIds)
        case .constant(let account):
            [account.id]
        }
    }
    
    private func syncSelection(with accountIds: [String]) {
        let accountId = switch viewModel.accountSource {
        case .accountId(let accountId):
            accountId
        case .current:
            viewModel.currentAccountId
        case .constant(let account):
            account.id
        }
        updateSelection(to: accountId, animated: false)
    }
    
    private func updateSelection(to accountId: String, animated: Bool) {
        guard selectedAccountId != accountId else { return }
        guard dataSource.indexPath(for: .account(accountId)) != nil else { return }
        selectedAccountId = accountId
        scrollTo(accountId: accountId, animated: animated)
    }
    
    func makeLayout() -> UICollectionViewCompositionalLayout {

        let item = NSCollectionLayoutItem(layoutSize: .init(.absolute(itemWidth), .absolute(itemHeight)))
        
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(.absolute(itemWidth), .absolute(itemHeight)), subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        if #available(iOS 17.0, *) {
            section.orthogonalScrollingProperties.decelerationRate = .fast
        }
        section.contentInsets = .init(top: 0, leading: inset, bottom: 0, trailing: inset)
        section.interGroupSpacing = spacing
        
        section.visibleItemsInvalidationHandler = { [unowned self] items, scrollOffset, env in
            guard !items.isEmpty else { return }
            var minDistance: CGFloat = .infinity
            var minDistanceIndex = 0
            
            for item in items {
                let idx = CGFloat(item.indexPath.row)
                let position = idx - scrollOffset.x/itemWidthWithSpacing
                
                let absDistance = abs(position)
                if absDistance < minDistance {
                    minDistance = absDistance
                    minDistanceIndex = item.indexPath.row
                }
            }
            
            self.updateFocusedItem(idx: minDistanceIndex)
        }
        
        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
    
    override func layoutSubviews() {
        if collectionView.frame != self.bounds {
            collectionView.frame = self.bounds
            collectionView.setCollectionViewLayout(makeLayout(), animated: false)
            if let selectedAccountId {
                scrollTo(accountId: selectedAccountId, animated: false)
            }
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: itemHeight)
    }
    
    override func safeAreaInsetsDidChange() {
    }
    
    func updateFocusedItem(idx: Int) {
        guard case .account(let id) = dataSource.itemIdentifier(for: IndexPath(item: idx, section: 0)) else { return }
        guard selectedAccountId != id else { return }
        selectedAccountId = id
        if isUserScrolling {
            viewModel.onSelect(id)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    }
    
    func scrollTo(accountId: String, animated: Bool) {
        guard !isUserScrolling else { return }
        if let indexPath = dataSource.indexPath(for: .account(accountId)) {
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
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

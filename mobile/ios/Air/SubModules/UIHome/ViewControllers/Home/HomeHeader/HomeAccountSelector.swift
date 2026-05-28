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
import Combine

class HomeAccountSelector: UIView, UICollectionViewDelegate {
    
    let viewModel: HomeHeaderViewModel
    var onIsScrolling: (Bool) -> ()
    var selectedIdx = 0
    
    enum Section: Hashable {
        case main
    }
    enum Item: Hashable {
        case coverFlowItem(String)
    }
    
    var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    var scrollingUpdates = CurrentValueSubject<Bool, Never>(false)
    var cancellables = Set<AnyCancellable>()
    
    override var safeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { _ = newValue }
    }
    
    init(viewModel: HomeHeaderViewModel, onIsScrolling: @escaping (Bool) -> ()) {
        self.viewModel = viewModel
        self.onIsScrolling = onIsScrolling
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
            let accountViewModel = AccountViewModel(accountId: accountId)
            cell.configure(headerViewModel: homeHeaderViewModel, accountViewModel: accountViewModel)
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .coverFlowItem(let id):
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
            }
        }
        
        observe { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.main])
            if let accountId = viewModel.accountId {
                snapshot.appendItems([.coverFlowItem(accountId)])
            } else {
                snapshot.appendItems(viewModel.accountStore.orderedAccountIds.map(Item.coverFlowItem))
            }
            dataSource.apply(snapshot)
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
        
        scrollingUpdates
            .sink { [unowned self] isScrolling in
                if isScrolling {
                    onIsScrolling(true)
                }
            }
            .store(in: &cancellables)
        scrollingUpdates
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [unowned self] isScrolling in
                if !isScrolling {
                    onIsScrolling(false)
                }
            }
            .store(in: &cancellables)
    }
    
    func makeLayout() -> UICollectionViewCompositionalLayout {

        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight)))
        
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight)), subitems: [item])
        
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
            scrollingUpdates.send(minDistance > 1e-3)
        }
        
        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [self] in
            self.scrollTo(viewModel.currentAccountId, animated: false)
            observe { [weak self] in
                guard let self else { return }
                let accountId = viewModel.currentAccountId
                scrollTo(accountId, animated: false)
            }
        }
    }
    
    override func layoutSubviews() {
        if collectionView.frame != self.bounds {
            collectionView.frame = self.bounds
            collectionView.setCollectionViewLayout(makeLayout(), animated: true)
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: itemHeight)
    }
    
    override func safeAreaInsetsDidChange() {
    }
    
    func updateFocusedItem(idx: Int) {
        if idx != selectedIdx {
            selectedIdx = idx
            if case .coverFlowItem(let id) = dataSource.itemIdentifier(for: IndexPath(item: idx, section: 0)) {
                viewModel.onSelect(id)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    }
    
    func scrollTo(_ id: String, animated: Bool) {
        if let indexPath = dataSource.indexPath(for: .coverFlowItem(id)), let scrollView = collectionView.subviews.compactMap({ $0 as? UIScrollView }).first {
            if !scrollView.isTracking && !scrollView.isDecelerating {
                let idx = CGFloat(indexPath.row)
                let offset = CGPoint(x: -scrollView.adjustedContentInset.left + idx * itemWidthWithSpacing, y: 0)
                scrollView.setContentOffset(offset, animated: animated)
            }
        }
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
}

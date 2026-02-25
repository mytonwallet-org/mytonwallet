//
//  CoverFlowCollectionView.swift
//  CoverFlow
//
//  Created by nikstar on 15.08.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext
import Perception
import WalletCore
import Combine

private let itemSize = collapsedImageSize
private let itemSpacing: CGFloat = 84.0
private let rotationSensitivity: Double = 1.7
private let rotationAngle: Double = Angle.degrees(-15).radians
private let offsetSensitivity: Double = 1
private let offsetMultiplier: Double = 4
private let offsetMultiplier2: Double = -50
private let negativeHorizontalInset: CGFloat = -40

class _CoverFlowView: UIView, UICollectionViewDelegate {
    
    let viewModel: NftDetailsViewModel
    var nftListContextProvider: NftListContextProvider { viewModel.listContextProvider }
    var onIsScrolling: (Bool) -> ()
    var onSelect: (String) -> ()
    var selectedIdx = 0
    var selectedId: String?
    var hasInitialized = false
    
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

    private func horizontalInset(containerWidth: CGFloat) -> CGFloat {
        (containerWidth - itemSpacing) / 2
    }
    
    init(viewModel: NftDetailsViewModel, selectedId: String, onSelect: @escaping (String) -> (), onIsScrolling: @escaping (Bool) -> ()) {
        self.viewModel = viewModel
        self.selectedId = selectedId
        self.onSelect = onSelect
        self.onIsScrolling = onIsScrolling
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        let layout = UICollectionViewCompositionalLayout { [unowned self] _, env in
            let group = NSCollectionLayoutGroup.custom(layoutSize: .init(widthDimension: .absolute(itemSpacing), heightDimension: .absolute(itemSize))) { [itemSize, itemSpacing] _ in
                [NSCollectionLayoutGroupCustomItem(frame: CGRectMake(-(itemSize-itemSpacing)/2, 0, itemSize, itemSize))]
            }
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
            if #available(iOS 17.0, *) {
                section.orthogonalScrollingProperties.decelerationRate = .fast
            }
            let inset = horizontalInset(containerWidth: env.container.effectiveContentSize.width)
            section.contentInsets = .init(top: 0, leading: inset, bottom: inset, trailing: inset)
            section.visibleItemsInvalidationHandler = { [unowned self] items, scrollOffset, env in
                guard !items.isEmpty else { return }
                var minDistance: CGFloat = .infinity
                var minDistanceIndex = 0
                let inset = horizontalInset(containerWidth: env.container.effectiveContentSize.width)

                for item in items {
                    let idx = CGFloat(item.indexPath.row)
                    let calculatedCenterX = inset + itemSpacing/2 + idx * itemSpacing
                    let position = idx - scrollOffset.x/itemSpacing
                    let sign: CGFloat = position > 0 ? 1 : -1

                    let absDistance = abs(position)
                    if absDistance < minDistance {
                        minDistance = absDistance
                        minDistanceIndex = item.indexPath.row
                    }

                    let distance1 = position
                    let distance2 = sign * max(0, abs(distance1) - 1)
                    let offset = clamp(distance1 * offsetSensitivity, to: -1...1) * offsetMultiplier + distance2 * offsetMultiplier2

                    let angle = clamp(distance1 * rotationSensitivity, to: -1...1) * rotationAngle

                    let factor: CGFloat = 0.6
                    let pivot = factor * (position > 0 ? itemSize : -itemSize)

                    var t = CATransform3DIdentity
                    t.m34 = -1.0 / 150.0
                    t = CATransform3DTranslate(t, pivot, 0, 0)
                    t = CATransform3DRotate(t, angle, 0, 1, 0)
                    t = CATransform3DTranslate(t, -pivot, 0, 0)
                    item.transform3D = t

                    item.zIndex = -Int(position)

                    item.center.x = calculatedCenterX + offset
                }

                self.updateFocusedItem(idx: minDistanceIndex)
                scrollingUpdates.send(minDistance > 1e-3)
            }
            return section
        }
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        let cellRegistration = UICollectionView.CellRegistration<NftCellStatic, String> { [unowned self] cell, indexPath, itemIdentifier in
            cell.configure(
                nft: nftListContextProvider.nfts.first(id: itemIdentifier),
                onTap: { [unowned self] in
                    if viewModel.nft.id == itemIdentifier {
                        viewModel.onImageTap()
                    } else {
                        scrollTo(itemIdentifier, animated: true)
                    }
                },
                onLongTap: { [unowned self] in
                    if viewModel.nft.id == itemIdentifier {
                        viewModel.onImageLongTap()
                    }
                }
            )
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .coverFlowItem(let id):
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
            }
        }
        
        observe { [weak self] in
            guard let self else { return }
            var snapshot = dataSource.snapshot()
            snapshot.appendSections([.main])
            snapshot.appendItems(nftListContextProvider.nfts.map(\.id).map(Item.coverFlowItem))
            dataSource.apply(snapshot)
        }        
        
        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = true
        collectionView.isScrollEnabled = false
        
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
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if let selectedId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.scrollTo(selectedId, animated: false)
            }
        }
    }
    
    override func layoutSubviews() {
        collectionView.frame = self.bounds.insetBy(dx: negativeHorizontalInset, dy: 0)
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: itemSize)
    }
    
    func updateFocusedItem(idx: Int) {
        if idx != selectedIdx {
            if hasInitialized {
                Haptics.play(.selection)
            }
            selectedIdx = idx
            hasInitialized = true
            if case .coverFlowItem(let id) = dataSource.itemIdentifier(for: IndexPath(item: idx, section: 0)) {
                onSelect(id)
            }
        }
    }
    
    func scrollTo(_ id: String, animated: Bool) {
        if let indexPath = dataSource.indexPath(for: .coverFlowItem(id)), let scrollView = collectionView.subviews.compactMap({ $0 as? UIScrollView }).first {
            let idx = CGFloat(indexPath.row)
            let offset = CGPoint(x: -scrollView.adjustedContentInset.left + idx * itemSpacing, y: 0)
            scrollView.setContentOffset(offset, animated: animated)
        }
    }
}


struct _CoverFlowViewRepresentable: UIViewRepresentable {
    
    var viewModel: NftDetailsViewModel
    var selectedId: String
    var onSelect: (String) -> ()
    var onIsScrolling: (Bool) -> ()

    func makeUIView(context: Context) -> some UIView {
        let view = _CoverFlowView(viewModel: viewModel, selectedId: selectedId, onSelect: onSelect, onIsScrolling: onIsScrolling)
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    }
}

struct CoverFlowView: View {
    
    var viewModel: NftDetailsViewModel
    var selectedId: String
    var onSelect: (String) -> ()
    @State private var isScrolling = false
    
    var body: some View {
        WithPerceptionTracking {
            _CoverFlowViewRepresentable(viewModel: viewModel, selectedId: selectedId, onSelect: _onSelect, onIsScrolling: onIsScrolling)
                .frame(maxWidth: .infinity)
                .preference(key: CoverFlowIsScrollingPreference.self, value: isScrolling)
        }
    }
    
    func onIsScrolling(_ isScrolling: Bool) {
        self.isScrolling = isScrolling
    }
    
    func _onSelect(_ id: String) {
        onSelect(id)
    }
}

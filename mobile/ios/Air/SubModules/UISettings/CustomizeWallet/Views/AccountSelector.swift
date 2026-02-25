//
//  Section.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//


import UIKit
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Combine

private let itemWidth: CGFloat = 274
private let itemHeight: CGFloat = 176
private let itemSpacing: CGFloat = itemWidth
private let rotationAngle: Double = Angle.degrees(-12).radians
private let offsetAdjustment: CGFloat = -12

class _AccountSelectorView: UIView, UICollectionViewDelegate {
    
    let viewModel: CustomizeWalletViewModel
    var onIsScrolling: (Bool) -> ()
    var onSelect: (String) -> ()
    var selectedIdx = 0
    var hasInitialized = false
    var lastKnownBoundsWidth: CGFloat = 0
    
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
    
    init(viewModel: CustomizeWalletViewModel, onSelect: @escaping (String) -> (), onIsScrolling: @escaping (Bool) -> ()) {
        self.viewModel = viewModel
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
            let inset = max(0, (env.container.effectiveContentSize.width - itemSpacing) / 2)

            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight))
            )
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(.absolute(itemWidth), .absolute(itemHeight)),
                subitems: [item]
            )

            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
            if #available(iOS 17.0, *) {
                section.orthogonalScrollingProperties.decelerationRate = .fast
            }
            section.contentInsets = .init(top: 0, leading: inset, bottom: 0, trailing: inset)
            section.interGroupSpacing = 0

            section.visibleItemsInvalidationHandler = { [unowned self] items, scrollOffset, env in
                guard !items.isEmpty else { return }
                let inset = max(0, (env.container.effectiveContentSize.width - itemSpacing) / 2)

                var minDistance: CGFloat = .infinity
                var minDistanceIndex = 0

                for item in items {
                    let idx = CGFloat(item.indexPath.row)
                    let calculatedCenterX = inset + itemSpacing / 2 + idx * itemSpacing
                    let position = idx - scrollOffset.x / itemSpacing

                    let absDistance = abs(position)
                    if absDistance < minDistance {
                        minDistance = absDistance
                        minDistanceIndex = item.indexPath.row
                    }

                    let angle = clamp(position, to: -1...1) * rotationAngle
                    let offset = clamp(position, to: -1...1) * offsetAdjustment

                    var t = CATransform3DIdentity
                    t.m34 = -1.0 / 150.0
                    t = CATransform3DRotate(t, angle, 0, 1, 0)
                    item.transform3D = t

                    item.center.x = calculatedCenterX + offset
                }

                self.updateFocusedItem(idx: minDistanceIndex)
                scrollingUpdates.send(minDistance > 1e-3)
            }

            return section
        }

        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, accountId in
            let accountContext = AccountContext(accountId: accountId)
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    AccountSelectorCell(accountContext: accountContext)
                }
                .margins(.all, 0)
            }
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
            snapshot.appendItems(viewModel.accountStore.orderedAccountIds.map(Item.coverFlowItem))
            dataSource.apply(snapshot)
        }
        
        observe { [weak self] in
            guard let self else { return }
            let selectedId = viewModel.selectedAccountId
            scrollTo(selectedId, animated: true)
        }
        
        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.isScrollEnabled = false
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
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [self] in
            self.scrollTo(viewModel.selectedAccountId, animated: false)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds

        if abs(lastKnownBoundsWidth - bounds.width) > .ulpOfOne {
            lastKnownBoundsWidth = bounds.width
            collectionView.collectionViewLayout.invalidateLayout()
            scrollTo(viewModel.selectedAccountId, animated: false)
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: itemHeight)
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
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if case .coverFlowItem(let id) = dataSource?.itemIdentifier(for: indexPath) {
            scrollTo(id, animated: true)
        }
    }
    
    func scrollTo(_ id: String, animated: Bool) {
        if let indexPath = dataSource.indexPath(for: .coverFlowItem(id)), let scrollView = collectionView.subviews.compactMap({ $0 as? UIScrollView }).first {
            if !scrollView.isTracking && !scrollView.isDecelerating {
                let idx = CGFloat(indexPath.row)
                let inset = max(0, (scrollView.bounds.width - itemSpacing) / 2)
                let offset = CGPoint(x: -inset + idx * itemSpacing, y: 0)
                scrollView.setContentOffset(offset, animated: animated)
            }
        }
    }
}


struct _AccountSelectorViewRepresentable: UIViewRepresentable {
    
    var viewModel: CustomizeWalletViewModel
    var onSelect: (String) -> ()
    var onIsScrolling: (Bool) -> ()

    func makeUIView(context: Context) -> some UIView {
        let view = _AccountSelectorView(viewModel: viewModel, onSelect: onSelect, onIsScrolling: onIsScrolling)
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    }
}

struct AccountSelectorView: View {
    
    var viewModel: CustomizeWalletViewModel
    var onSelect: (String) -> ()
    @State private var isScrolling = false
    
    var body: some View {
        _AccountSelectorViewRepresentable(viewModel: viewModel, onSelect: _onSelect, onIsScrolling: onIsScrolling)
            .frame(maxWidth: .infinity)
    }
    
    func onIsScrolling(_ isScrolling: Bool) {
        self.isScrolling = isScrolling
    }
    
    func _onSelect(_ id: String) {
        onSelect(id)
    }
}

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
private let itemSpacing: CGFloat = 4 + itemWidth
private let rotationSensitivity: Double = 1
private let rotationAngle: Double = Angle.degrees(-15).radians
//private let offsetSensitivity: Double = 1
//private let offsetMultiplier: Double = 4
//private let offsetMultiplier2: Double = -50
//private let negativeHorizontalInset: CGFloat = -40

class _AccountSelectorView: UIView, UICollectionViewDelegate {
    
    let viewModel: CustomizeWalletViewModel
    var onIsScrolling: (Bool) -> ()
    var onSelect: (String) -> ()
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
        
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight)))
        
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight)), subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        if #available(iOS 17.0, *) {
            section.orthogonalScrollingProperties.decelerationRate = .fast
        }
        let inset: CGFloat = (UIScreen.main.bounds.width - itemSpacing /*- 2 * negativeHorizontalInset*/)/2
        section.contentInsets = .init(top: 0, leading: inset, bottom: 0, trailing: inset)
        section.interGroupSpacing = 4
        
        var date = Date()
        section.visibleItemsInvalidationHandler = { [unowned self] items, scrollOffset, env in
            guard !items.isEmpty else { return }
            let now = Date()
            var minDistance: CGFloat = .infinity
            var minDistanceIndex = 0
            
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
                let offset = 0.0 // clamp(distance1 * offsetSensitivity, to: -1...1) * offsetMultiplier + distance2 * offsetMultiplier2

                let angle = clamp(distance1 * rotationSensitivity, to: -1...1) * rotationAngle
                
                let factor: CGFloat = 0.6
                let pivot = factor * (position > 0 ? -itemWidth : itemWidth)
                
                var t = CATransform3DIdentity
                t.m34 = -1.0 / 150.0
//                t = CATransform3DTranslate(t, pivot, 0, 0)
                t = CATransform3DRotate(t, angle, 0, 1, 0)
//                t = CATransform3DTranslate(t, -pivot, 0, 0)
//                t = CATransform3DScale(t, 1 - abs(position) * 0.5, 1 - abs(position) * 0.5, 0)
                
//                t = CATransform3DTranslate(t, offset, 0, 0)
//
                
//                item.transform = .identity.translatedBy(x: offset, y: 0)
                item.transform3D = t
                
//                item.zIndex = -Int(position)
                
//                item.center.x = calculatedCenterX + offset
            }
            date = now
            
            self.updateFocusedItem(idx: minDistanceIndex)
            scrollingUpdates.send(minDistance > 1e-3)
        }
        
        
        let layout = UICollectionViewCompositionalLayout(section: section)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, accountId in
            let viewModel = AccountViewModel(accountId: accountId)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    AccountSelectorCell(viewModel: viewModel)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [self] in
            self.scrollTo(viewModel.selectedAccountId, animated: false)
        }
    }
    
    override func layoutSubviews() {
        collectionView.frame = self.bounds //.insetBy(dx: negativeHorizontalInset, dy: 0)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
    }
    
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        return super.systemLayoutSizeFitting(targetSize)
    }
    
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        return super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: itemHeight)
    }
    
    func updateFocusedItem(idx: Int) {
        if idx != selectedIdx {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedIdx = idx
            if case .coverFlowItem(let id) = dataSource.itemIdentifier(for: IndexPath(item: idx, section: 0)) {
                onSelect(id)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    }
    
    func scrollTo(_ id: String, animated: Bool) {
        if let indexPath = dataSource.indexPath(for: .coverFlowItem(id)), let scrollView = collectionView.subviews.compactMap({ $0 as? UIScrollView }).first {
            if !scrollView.isTracking && !scrollView.isDecelerating {
                let idx = CGFloat(indexPath.row)
                let offset = CGPoint(x: -scrollView.adjustedContentInset.left + idx * itemSpacing, y: 0)
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

import UIKit
import SwiftUI
import Kingfisher
import WalletContext
import UIComponents

private let itemSpacing: CGFloat = 84.0
private let rotationSensitivity: Double = 1.7
private let rotationAngle: Double = Angle.degrees(-15).radians
private let offsetSensitivity: Double = 1
private let offsetMultiplier: Double = 4
private let offsetMultiplier2: Double = -50
private let negativeHorizontalInset: CGFloat = -40

protocol CoverFlowDelegate: AnyObject {
    /// Happens at the end of deceleration. 
    func coverFlowDidSelectModel(_ model: NftDetailsItemModel)
    func coverFlowDidTapModel(_ model: NftDetailsItemModel, view: UIView, longTap: Bool)
    func onCoverFlowScrollProgress(_ progress: CGFloat, currentModel: NftDetailsItemModel)
}

class _CoverFlowView: UIView, UIScrollViewDelegate {
    private var selectedIdx = 0
    private let models: [NftDetailsItemModel]
    
    private enum UserImpact {
        case tapped, scrolling
    }
    
    private var userImpact: UserImpact?
    private var hapticPlayedIdFor: Int?
    private var isExternalDriving = false
    private var externalDrivenIndex: CGFloat?
    private weak var internalScrollView: UIScrollView?
    private var lastExternalSyncedIndex: CGFloat?

    private var needsInitialScroll = true
    private var orthogonalScrollDelegateProxy: CoverFlowOrthogonalScrollDelegateProxy?
    private var lastCollectionViewWidth: CGFloat = 0
    private func horizontalInset(containerWidth: CGFloat) -> CGFloat { (containerWidth - itemSpacing) / 2 }
    private let itemSize: CGFloat

    private enum Section: Hashable {
        case main
    }
    
    private enum Item: Hashable {
        case coverFlowItem(modelIndex: Int)
    }
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private let thumbnailDownloader: ImageDownloader
    private weak var colorCache: NftDetailsColorCache?
    private var tileCornerRadius: CGFloat

    weak var delegate: CoverFlowDelegate?
    
    var isActive: Bool = true {
        didSet {
            if isActive != oldValue {
                alpha = isActive ? 1 : 0
            }
        }
    }
    
    init(models: [NftDetailsItemModel], itemSize: CGFloat, thumbnailDownloader: ImageDownloader, colorCache: NftDetailsColorCache?, tileCornerRadius: CGFloat) {
        self.models = models
        self.itemSize = itemSize
        self.thumbnailDownloader = thumbnailDownloader
        self.colorCache = colorCache
        self.tileCornerRadius = tileCornerRadius
        
        super.init(frame: .fromSize(width: 400, height: itemSize))
        
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let layout = UICollectionViewCompositionalLayout { [unowned self] _, env in
            let group = NSCollectionLayoutGroup.custom(layoutSize: .init(
                widthDimension: .absolute(itemSpacing), heightDimension: .absolute(itemSize))) { [itemSize, itemSpacing] _ in
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

                // When the pager is driving us, use the externally supplied fractional index instead of the scroll view's actual offset.
                // This lets us hit every intermediate position even if the layout's snapping behaviour would otherwise resist
                // a non-boundary content offset.
                let effectiveScrollIndex = self.externalDrivenIndex ?? (scrollOffset.x / itemSpacing)

                for item in items {
                    let idx = CGFloat(item.indexPath.row)
                    let calculatedCenterX = inset + itemSpacing/2 + idx * itemSpacing
                    let position = idx - effectiveScrollIndex
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
                    // Cells left of center had *higher* zIndex (`-Int(position)`), so further-left tiles
                    // stacked on top after 3D rotation and stole taps meant for the immediate neighbour.
                    // Use symmetric falloff from center so the focused card is always on top for hit-testing.
                    item.zIndex = 10_000 - Int(round(abs(position) * 100))

                    // Legacy positioning matches `scrollOffset` from the invalidation handler on iOS 17–18.
                    // Pager-driven sync uses a fractional index while UIKit may keep `scrollOffset.x` on a snap boundary;
                    // only then apply the correction term (needed on newer OS snapping behavior).
                    if let externalIndex = self.externalDrivenIndex {
                        item.center.x = calculatedCenterX + offset - externalIndex * itemSpacing + scrollOffset.x
                    } else {
                        item.center.x = calculatedCenterX + offset
                    }
                }
                
                // Skip selection changes while the pager is driving our position to prevent loop: pager -> coverFlow -> onSelect → pager.
                // externalDrivenIndex being set means we are in pager-driven mode.
                // Only sync `selectedIdx` when the orthogonal scroll offset agrees with `minDistanceIndex`; otherwise
                // a stale `scrollOffset` / pre-scroll layout pass reports row 0 as centered and would wrongly notify
                // `coverFlowDidSelectModel` for that item while `selectedIdx` already matches an external selection.
                if self.userImpact == nil && !self.isExternalDriving && self.externalDrivenIndex == nil,
                   let sv = self.internalScrollView {
                    let rawRow = (sv.contentOffset.x + sv.adjustedContentInset.left) / itemSpacing
                    if abs(rawRow - CGFloat(minDistanceIndex)) < 0.5 {
                        self.updateFocusedItem(atCollectionRow: minDistanceIndex)
                    }
                }
                
                if let userImpact = self.userImpact, let delegate = self.delegate {
                    if let centeredItem = items.first(where: { $0.indexPath.row == minDistanceIndex }),
                       case .coverFlowItem(let itemIndex) = self.dataSource.itemIdentifier(for: centeredItem.indexPath) {
                        let idx = CGFloat(itemIndex)
                        let position = idx - scrollOffset.x / itemSpacing
                        let progress = clamp(-position, to: -0.5...0.5)
                        if abs(progress) > 0.40 && userImpact == .scrolling {
                            let newHapticPlayedIdFor = progress > 0 ? itemIndex : itemIndex - 1
                            if hapticPlayedIdFor != newHapticPlayedIdFor {
                                Haptics.play(.selection)
                                hapticPlayedIdFor = newHapticPlayedIdFor
                            }
                        }
                        delegate.onCoverFlowScrollProgress(progress, currentModel: models[itemIndex])
                    }
                }
            }
            return section
        }
                
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        let cellRegistration = UICollectionView.CellRegistration<_Cell, Int> { [weak self] cell, _, itemIndex in
            guard let self else { return }
            
            cell.tile.delegate = self
            cell.tile.thumbnailDownloader = self.thumbnailDownloader
            cell.tile.colorCache = self.colorCache
            cell.tile.configure(with: models[itemIndex], tileCornerRadius: self.tileCornerRadius)
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .coverFlowItem(let id):
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: id)
            }
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(models.map { Item.coverFlowItem(modelIndex: $0.index) })
        dataSource.apply(snapshot)
        
        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = true
        collectionView.isScrollEnabled = false
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.isHidden = true
            collectionView.bottomEdgeEffect.isHidden = true
            collectionView.leftEdgeEffect.isHidden = true
            collectionView.rightEdgeEffect.isHidden = true
        }
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: itemSize),
        ])
    }
    
    private func updateInternalScrollView() {
        guard let sv = collectionView.subviews.compactMap({ $0 as? UIScrollView }).first else { return }
        internalScrollView = sv
        
        if let existingProxy = sv.delegate as? CoverFlowOrthogonalScrollDelegateProxy {
            existingProxy.coverFlow = self
            orthogonalScrollDelegateProxy = existingProxy
            return
        }

        guard orthogonalScrollDelegateProxy == nil else { return }

        let proxy = CoverFlowOrthogonalScrollDelegateProxy()
        proxy.forwardTo = sv.delegate
        proxy.coverFlow = self
        sv.delegate = proxy
        orthogonalScrollDelegateProxy = proxy
    }
        
    override func layoutSubviews() {
        super.layoutSubviews()
        let newFrame = self.bounds.insetBy(dx: negativeHorizontalInset, dy: 0)
        let needsReScroll = needsInitialScroll || newFrame.width != lastCollectionViewWidth
        collectionView.frame = newFrame

        if needsReScroll {
            // Force the compositional layout to complete its first pass so the orthogonal
            // section's internal scroll view is created before we try to scroll to it.
            // Also re-run when width changes: the leading content inset is proportional to
            // container width, so a different width shifts the effective item position even
            // if the raw contentOffset.x is preserved by UIKit.
            collectionView.layoutIfNeeded()
            updateInternalScrollView()
            if internalScrollView != nil {
                needsInitialScroll = false
                lastCollectionViewWidth = newFrame.width
                scrollTo(index: selectedIdx, animated: false)
            }
        } else {
            updateInternalScrollView()
        }

        // `selectModel` often runs from the header before the orthogonal scroll view exists,
        // and the first `setContentOffset` can use a stale `adjustedContentInset` before
        // section insets settle. Tile 0 still looks centered; non-zero indices stay misaligned
        // unless we re-apply once `contentOffset`/insets match `selectedIdx`.
        syncScrollPositionToSelectionIfNeeded()
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: itemSize)
    }
    
    // MARK: - UIScrollViewDelegate (orthogonal scroll view)
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if let idx = externalDrivenIndex {
            let offset = CGPoint(x: -scrollView.adjustedContentInset.left + idx * itemSpacing, y: 0)
            scrollView.setContentOffset(offset, animated: false)
        }
        externalDrivenIndex = nil
        lastExternalSyncedIndex = nil
        userImpact = .scrolling
        hapticPlayedIdFor = selectedIdx
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            userImpact = nil
            finalizeSelection(scrollView: scrollView)
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userImpact = nil
        finalizeSelection(scrollView: scrollView)
    }

     func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
         userImpact = nil
         finalizeSelection(scrollView: scrollView)
     }

    private func finalizeSelection(scrollView: UIScrollView) {
        let itemCount = dataSource.snapshot().numberOfItems
        guard itemCount > 0 else { return }
        let rawIdx = (scrollView.contentOffset.x + scrollView.adjustedContentInset.left) / itemSpacing
        let idx = max(0, min(itemCount - 1, Int(round(rawIdx))))
        updateFocusedItem(atCollectionRow: idx)
    }
    
    /// `row` is the collection-view section-0 item index (0…n-1), not `NftDetailsItemModel.index`.
    private func updateFocusedItem(atCollectionRow row: Int) {
        guard case .coverFlowItem(let itemIndex) = dataSource.itemIdentifier(for: IndexPath(item: row, section: 0)),
              itemIndex != selectedIdx,
              let delegate else { return }
        selectedIdx = itemIndex
        delegate.coverFlowDidSelectModel(models[itemIndex])
    }

    @discardableResult
    private func scrollTo(index: Int, animated: Bool) -> Bool {
        guard let indexPath = dataSource.indexPath(for: .coverFlowItem(modelIndex: index)),
              let scrollView = internalScrollView else { return false }
        let idx = CGFloat(indexPath.row)
        let offset = CGPoint(x: -scrollView.adjustedContentInset.left + idx * itemSpacing, y: 0)
        scrollView.setContentOffset(offset, animated: animated)
        return true
    }

    /// Re-scroll when the orthogonal scroll view's offset does not match `selectedIdx`
    /// (inset/content size can settle one layout pass later than the first `scrollTo`).
    private func syncScrollPositionToSelectionIfNeeded() {
        guard bounds.width > 0,
              let sv = internalScrollView,
              dataSource.snapshot().numberOfItems > 0,
              let indexPath = dataSource.indexPath(for: .coverFlowItem(modelIndex: selectedIdx))
        else { return }
        let targetRow = indexPath.row
        let rawIdx = (sv.contentOffset.x + sv.adjustedContentInset.left) / itemSpacing
        guard abs(rawIdx - CGFloat(targetRow)) > 0.05 else { return }
        scrollTo(index: selectedIdx, animated: false)
    }

    func selectModel(_ model: NftDetailsItemModel) {
        externalDrivenIndex = nil
        lastExternalSyncedIndex = nil

        let index = model.index
        selectedIdx = index
        if !scrollTo(index: index, animated: false) {
            needsInitialScroll = true
        }
    }

    /// The tile for the currently focused item, if that cell is in the collection view’s visible window (`cellForItem` is non-nil).
    private func currentActiveCoverFlowTile() -> NftDetailsItemCoverFlowTile? {
        guard let indexPath = dataSource.indexPath(for: .coverFlowItem(modelIndex: selectedIdx)),
              let cell = collectionView.cellForItem(at: indexPath) as? _Cell else { return nil }
        return cell.tile
    }
    
    func setSelectedTileVisible(_ visible: Bool) {
        currentActiveCoverFlowTile()?.alpha = visible ? 1 : 0
    }

    /// Drive the cover-flow position from an external source (e.g. pager drag). `progress` is in [0, 1]: 0 = on currentItem, 1 = fully on next item.
    /// The call is a no-op while the user is scrolling the cover flow themselves.
    func setCoverFlowProgress(progress: CGFloat, currentModel: NftDetailsItemModel) {
        guard userImpact == nil else { return }
        guard let indexPath = dataSource.indexPath(for: .coverFlowItem(modelIndex: currentModel.index)) else { return }

        isExternalDriving = true
        let idx = CGFloat(indexPath.row)
        let fractionalIndex = idx + CGFloat(progress)

        // Store the desired fractional index.  visibleItemsInvalidationHandler reads this value and uses it instead of scrollOffset,
        // guaranteeing per-frame smooth 3-D transforms even when the orthogonal section's snapping behaviour would otherwise
        // resist a non-boundary content offset.
        externalDrivenIndex = fractionalIndex

        var didSyncScrollView = false
        if let sv = internalScrollView {
            let currentIndex = (sv.contentOffset.x + sv.adjustedContentInset.left) / itemSpacing
            let shouldSync = lastExternalSyncedIndex == nil
                || abs(currentIndex - fractionalIndex) >= 0.55
                || abs((lastExternalSyncedIndex ?? 0) - fractionalIndex) >= 0.55
            if shouldSync {
                let offset = CGPoint(x: -sv.adjustedContentInset.left + fractionalIndex * itemSpacing, y: 0)
                sv.setContentOffset(offset, animated: false)

                lastExternalSyncedIndex = fractionalIndex
                didSyncScrollView = true
            }
        }

        if !didSyncScrollView {
            collectionView.collectionViewLayout.invalidateLayout()
        }

        DispatchQueue.main.async { [weak self] in
            self?.isExternalDriving = false
        }
    }
}

extension _CoverFlowView: NftDetailsItemCoverFlowTileDelegate {
    
    func nftDetailsItemCoverFlowTile(_ tile: NftDetailsItemCoverFlowTile, didSelectModel model: NftDetailsItemModel, longTap: Bool) {
        if longTap {
            if selectedIdx == model.index {
                self.delegate?.coverFlowDidTapModel(model, view: tile, longTap: true)
            }
        } else {
            if selectedIdx == model.index {
                self.delegate?.coverFlowDidTapModel(model, view: tile, longTap: false)
            } else {
                self.userImpact = .tapped
                self.scrollTo(index: model.index, animated: true)
            }
        }
    }

    func nftDetailsItemCoverFlowTileGetActiveState(_ tile: NftDetailsItemCoverFlowTile) -> Bool { isActive }
}
    
final class _Cell: UICollectionViewCell  {
    let tile = NftDetailsItemCoverFlowTile()

    override init(frame: CGRect) {
        super.init(frame: frame)

        tile.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tile)
        
        NSLayoutConstraint.activate([
            tile.topAnchor.constraint(equalTo: contentView.topAnchor),
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tile.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tile.prepareForCollectionViewReuse()
    }
}

fileprivate extension _CoverFlowView {
    func orthogonalScrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollViewWillBeginDragging(scrollView)
    }

    func orthogonalScrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }

    func orthogonalScrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollViewDidEndDecelerating(scrollView)
    }

    func orthogonalScrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollViewDidEndScrollingAnimation(scrollView)
    }
}

/// Forwards all `UIScrollViewDelegate` callbacks to the delegate UIKit installed on the orthogonal
/// scroll view. Replacing that delegate entirely breaks compositional orthogonal scrolling on iOS 16-18
private final class CoverFlowOrthogonalScrollDelegateProxy: NSObject, UIScrollViewDelegate {
    weak var forwardTo: UIScrollViewDelegate?
    weak var coverFlow: _CoverFlowView?

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewDidScroll?(scrollView)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewDidZoom?(scrollView)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewWillBeginDragging?(scrollView)
        coverFlow?.orthogonalScrollViewWillBeginDragging(scrollView)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        forwardTo?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        forwardTo?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        coverFlow?.orthogonalScrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }

    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewWillBeginDecelerating?(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewDidEndDecelerating?(scrollView)
        coverFlow?.orthogonalScrollViewDidEndDecelerating(scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewDidEndScrollingAnimation?(scrollView)
        coverFlow?.orthogonalScrollViewDidEndScrollingAnimation(scrollView)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        forwardTo?.viewForZooming?(in: scrollView)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        forwardTo?.scrollViewWillBeginZooming?(scrollView, with: view)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        forwardTo?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        forwardTo?.scrollViewShouldScrollToTop?(scrollView) ?? true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewDidScrollToTop?(scrollView)
    }

    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        forwardTo?.scrollViewDidChangeAdjustedContentInset?(scrollView)
    }
}

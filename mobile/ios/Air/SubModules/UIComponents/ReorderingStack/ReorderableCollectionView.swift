import UIKit
import Foundation

@MainActor
public protocol ReorderableCollectionViewControllerDelegate: UIScrollViewDelegate {
    /// Notifies the delegate that an item was moved. Return `true` if the delegate updated the collection view itself
    /// (e.g. applied a diffable data source snapshot); the controller will not call `moveItem`. Return `false` to have
    /// the controller perform `moveItem` (for direct data source management).
    func reorderController(_ controller: ReorderableCollectionViewController, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) -> Bool
    func reorderController(_ controller: ReorderableCollectionViewController, canMoveItemAt indexPath: IndexPath) -> Bool
    func reorderController(_ controller: ReorderableCollectionViewController, previewForCell cell: UICollectionViewCell) -> ReorderableCollectionViewController.CellPreview?
    func reorderController(_ controller: ReorderableCollectionViewController, sizeForItemAt indexPath: IndexPath) -> CGSize?
    func reorderController(_ controller: ReorderableCollectionViewController, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration?
    func reorderController(_ controller: ReorderableCollectionViewController, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?)
    func reorderController(_ controller: ReorderableCollectionViewController, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?)
    func reorderController(_ controller: ReorderableCollectionViewController, didChangeReorderingStateByExternalActor isExternalActor: Bool)
    func reorderController(_ controller: ReorderableCollectionViewController, didSelectItemAt indexPath: IndexPath)
}

public extension ReorderableCollectionViewControllerDelegate {
    func reorderController(_ controller: ReorderableCollectionViewController, canMoveItemAt indexPath: IndexPath) -> Bool { true }
    func reorderController(_ controller: ReorderableCollectionViewController, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) -> Bool { false }
    func reorderController(_ controller: ReorderableCollectionViewController, sizeForItemAt indexPath: IndexPath) -> CGSize? { nil }
    func reorderController(_ controller: ReorderableCollectionViewController, previewForCell cell: UICollectionViewCell) -> ReorderableCollectionViewController.CellPreview? { nil }
    func reorderController(_ controller: ReorderableCollectionViewController, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? { nil }
    func reorderController(_ controller: ReorderableCollectionViewController, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) { }
    func reorderController(_ controller: ReorderableCollectionViewController, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) { }
    func reorderController(_ controller: ReorderableCollectionViewController, didChangeReorderingStateByExternalActor isExternalActor: Bool) { }
    func reorderController(_ controller: ReorderableCollectionViewController, didSelectItemAt indexPath: IndexPath) { }
}

/// Helper that adds drag-and-drop reordering to a collection view.
///
/// The controller is attached to a `UICollectionView` and manages interactive drag logic,
/// including auto-scroll. Acts as a delegate proxy: intercepts a set of delegate methods and forwards them. Only a minimal viable set of methods is proxied.
/// Additional methods will be added on demand.
///
/// Note: as of now, the dragging is supported inside a single section
@MainActor
public final class ReorderableCollectionViewController: NSObject {
    private enum AutoScrollDirection: CGFloat {
        case towardStart = -1
        case towardEnd = 1
    }

    /// Extended version of `CellPreview` for internal usage
    private struct InternalCellPreview {
        var view: UIView
        var centerOffset: CGSize
        var cornerRadius: CGFloat

        @MainActor
        var cellCenter: CGPoint {
            get { view.frame.center - centerOffset }
            set { view.center = newValue + centerOffset }
        }
    }
    
    public struct CellPreview {
        public var view: UIView
        public var cornerRadius: CGFloat
        public var makeSnapshot: Bool?
        
        public init(view: UIView, cornerRadius: CGFloat = 0, makeSnapshot: Bool? = nil) {
            self.view = view
            self.cornerRadius = cornerRadius
            self.makeSnapshot = makeSnapshot
        }
    }
    
    /// Prevents classic UICollectionView drag bug with fast cell swapping when the dragged cell nearly pauses over another cell
    private struct ReorderThrottle {
        var lastSwapSourceIndexPath: IndexPath?
        var lastSwapDestinationIndexPath: IndexPath?
        var lastSwapLocationInCollection: CGPoint?
        var lastSwapTime: Date?

        private let reverseSwapCooldown: TimeInterval = 0.5
        private let swapDistanceThreshold: CGFloat = 8

        func canMove(from source: IndexPath, to destination: IndexPath, at location: CGPoint) -> Bool {
            if let lastSource = lastSwapSourceIndexPath, let lastDestination = lastSwapDestinationIndexPath {
                if source == lastDestination && destination == lastSource {
                    guard let lastTime = lastSwapTime else { return false }
                    return Date().timeIntervalSince(lastTime) >= reverseSwapCooldown
                }
            }
            guard let lastLocation = lastSwapLocationInCollection else {
                return true
            }

            return location.distance(to: lastLocation) >= swapDistanceThreshold
        }

        mutating func acceptMove(from source: IndexPath, to destination: IndexPath, at location: CGPoint) {
            lastSwapSourceIndexPath = source
            lastSwapDestinationIndexPath = destination
            lastSwapLocationInCollection = location
            lastSwapTime = Date()
        }

        mutating func start(_ location: CGPoint) {
            lastSwapLocationInCollection = location
            lastSwapSourceIndexPath = nil
            lastSwapDestinationIndexPath = nil
            lastSwapTime = nil
        }
    }
    
    // These are for custom dragging
    private var customDragPreview: InternalCellPreview?
    private weak var dropTargetCell: UICollectionViewCell?
    private var lastDragLocationInCollection = CGPoint.zero
    private var centerOffset = CGSize.zero
    private var currentSourceIndexPath: IndexPath?
    private var longGestureRecognizer: UILongPressGestureRecognizer?
    private var reorderThrottle = ReorderThrottle()

    // These are for system menu and system drag handling
    private var dragSessionSourceIndexPath: IndexPath?

    // These are for both custom and system dragging
    private var currentDraggedIndexPath: IndexPath? // cell's reorderingState.dragging

    private var wasScrollingEnabled = true // when true, scrolling was enabled before drag; auto-scroll is applied during drag
    private var isFlowDirectionHorizontal: Bool = false
    private var autoScrollDirection: AutoScrollDirection?
    private var autoScrollDisplayLink: CADisplayLink?
    private let autoScrollSpeed: CGFloat = 6  // Points per frame
    private let autoScrollEdgeInset: CGFloat = 40
    
    public weak var delegate: ReorderableCollectionViewControllerDelegate?
    public let collectionView: UICollectionView
    
    public var scrollDirection: UICollectionView.ScrollDirection?

    private var _isReordering: Bool = false
    public var isReordering: Bool {
        get { _isReordering }
        set { setReorderingMode(newValue, externally: true) }
    }

    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()
        
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.04
        longPress.delegate = self
        longPress.isEnabled = false
        collectionView.addGestureRecognizer(longPress)
        longGestureRecognizer = longPress

        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationDidBecomeActive() {
        if isReordering {
            updateVisibleCells()
        }
    }

    public func updateCell(_ cell: UICollectionViewCell, indexPath: IndexPath) {
        guard let cell = cell as? ReorderableCell else {
            return
        }
        var state = ReorderableCellState()
        if isReordering {
            state.update(with: .reordering)
        }
        if currentDraggedIndexPath == indexPath {
            state.update(with: .dragging)
        }
        cell.reorderingState = state
    }

    private func updateCell(indexPath: IndexPath?) {
        if let indexPath, let cell = collectionView.cellForItem(at: indexPath) {
            updateCell(cell, indexPath: indexPath)
        }
    }

    private func updateVisibleCells() {
        collectionView.indexPathsForVisibleItems.forEach { updateCell(indexPath: $0) }
    }
    
    private func setReorderingMode(_ newValue: Bool, externally: Bool = false) {
        guard newValue != _isReordering else { return }
        _isReordering = newValue
        updateVisibleCells()
        collectionView.dragInteractionEnabled = !isReordering
        longGestureRecognizer?.isEnabled = isReordering
        delegate?.reorderController(self, didChangeReorderingStateByExternalActor: externally)
    }
    
    private func flowDirection(forSectionAt indexPath: IndexPath? = nil) -> UICollectionView.ScrollDirection {
        if let scrollDirection {
            return scrollDirection
        }
        
        let layout = collectionView.collectionViewLayout
        if let flow = layout as? UICollectionViewFlowLayout {
            return flow.scrollDirection
        }
        
        assertionFailure("Unsupported layout type: \(type(of: layout)). Assign a value to 'scrollDirection' to use a fixed direction.")
        return .vertical
    }

    private func indexPathForPoint(_ contentPoint: CGPoint) -> IndexPath? {
        let rectSize = CGFloat(10)
        let rect = CGRect(x: contentPoint.x - rectSize, y: contentPoint.y - rectSize, width: rectSize * 2, height: rectSize * 2)
        guard let attrs = collectionView.collectionViewLayout.layoutAttributesForElements(in: rect) else { return nil }
        for attr in attrs where attr.representedElementCategory == .cell {
            if attr.frame.contains(contentPoint) {
                return attr.indexPath
            }
        }
                
        // Process empty space after the last item in the section
        if let currentSourceIndexPath {
            let section = currentSourceIndexPath.section
            let itemCount = collectionView.numberOfItems(inSection: section)
            if itemCount > 0, let lastAttr = collectionView.layoutAttributesForItem(at: IndexPath(item: itemCount - 1, section: section)) {
                if isFlowDirectionHorizontal {
                    if contentPoint.x > lastAttr.frame.minX {
                        return IndexPath(item: itemCount-1, section: section)
                    }
                } else {
                    if contentPoint.y > lastAttr.frame.minY {
                        return IndexPath(item: itemCount-1, section: section)
                    }
                }
            }
        }
        return nil
    }
    
    private enum previewMode {
        case requiredFastSnapshot  // always make a snapshot
        case fastSnapshot
        case renderToImage // when dragging starts from the system menu (otherwise you get a white shadow)
        case empty         // we do not need a view, only bounds, frames and radii
    }
    
    private func preview(ofCell cell: UICollectionViewCell, mode: previewMode) -> InternalCellPreview {
        let cBounds = cell.bounds
                        
        // Get view to copy from. Default view is just cell's content view
        var view = cell.contentView
        var cornerRadius: CGFloat = 0
        var centerOffset = CGSize.zero
        var makeSnapshot = false
        if let cellPreview = delegate?.reorderController(self, previewForCell: cell) {
            var ms = cellPreview.makeSnapshot
            let customView = cellPreview.view
            if customView.isDescendant(of: view) {
                let cvCenter = customView.convert(customView.bounds.center, to: view)
                centerOffset = cvCenter - cBounds.center
            }
            if customView.superview != nil {
                ms = ms ?? true
            }
            view = customView
            cornerRadius = cellPreview.cornerRadius
            if let ms {
                makeSnapshot = ms
            }
        }
        if (mode == .requiredFastSnapshot) {
            makeSnapshot = true
        }

        // Note that view frame will always be calculated relative to the cell
        let vBounds = view.bounds
        let vFrame = CGRect(origin: (cBounds.center + centerOffset) - CGSize(width: vBounds.midX, height: vBounds.midY), size: vBounds.size)

        // No snapshot: return the view as is
        if !makeSnapshot {
            view.frame = vFrame
            return .init(view: view, centerOffset: centerOffset, cornerRadius: cornerRadius)
        }
                
        // Draw into the effective snapshot view. Use the fast path when possible.
        let snapshot: UIView
        switch mode {
        case .requiredFastSnapshot, .fastSnapshot:
            if let snap = view.snapshotView(afterScreenUpdates: false) {
                snapshot = snap
                snapshot.frame = vFrame
                break
            }
            fallthrough
        case .renderToImage:
            let format = UIGraphicsImageRendererFormat()
            format.scale = view.contentScaleFactor
            let image = UIGraphicsImageRenderer(bounds: vBounds, format: format).image { _ in
                view.drawHierarchy(in: vBounds, afterScreenUpdates: false)
            }
            let iv = UIImageView(frame: vFrame)
            iv.image = image
            snapshot = iv
        case .empty:
            snapshot = .init(frame: vFrame)
        }
        return .init(view: snapshot, centerOffset: centerOffset, cornerRadius: cornerRadius)
    }

    private func moveItem(source: IndexPath, destination: IndexPath, silent: Bool = false ) {
        guard source.section == destination.section else {
            assertionFailure("Cross section dragging is not supported yet")
            return
        }

        if !silent {
            Haptics.play(.drag)
        }

        if let delegate, source != destination {
            let delegateUpdatedUI = delegate.reorderController(self, moveItemAt: source, to: destination)
            if !delegateUpdatedUI {
                collectionView.performBatchUpdates {
                    collectionView.moveItem(at: source, to: destination)
                }
            }
        }
    }

    // MARK: - Gesture

    private func isControlOrInsideControl(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v is UIControl { return true }
            current = v.superview
        }
        return false
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if isReordering {
            handleLongPressInOrderingMode(gesture)
        }
    }
        
    private func beginOrderingMode(indexPath: IndexPath, location: CGPoint) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        guard let cvSuperview = collectionView.superview else { return }
        guard delegate?.reorderController(self, canMoveItemAt: indexPath) == true else { return }
        
        let preview = preview(ofCell: cell, mode: .requiredFastSnapshot)
        do {
            let v = preview.view
            v.frame = cell.convert(v.frame, to: cvSuperview)
            cvSuperview.addSubview(v)
            v.layer.cornerRadius = preview.cornerRadius
            v.layer.masksToBounds = true
            v.alpha = 0.8 // Simulate the system drag appearance
            customDragPreview = preview
        }
        
        centerOffset = location - cell.frame.center
        reorderThrottle.start(location)

        dropTargetCell = cell
        dropTargetCell?.isHidden = true
        currentDraggedIndexPath = indexPath
        updateCell(cell, indexPath: indexPath) // cell is hidden but update anyway so it has the correct appearance when dragging ends
        
        currentSourceIndexPath = indexPath
        lastDragLocationInCollection = location
        isFlowDirectionHorizontal = flowDirection(forSectionAt: indexPath) == .horizontal

        wasScrollingEnabled = collectionView.isScrollEnabled
        if !wasScrollingEnabled {
            collectionView.isScrollEnabled = false
        }
    }
        
    private func handleLongPressInOrderingMode(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: collectionView)
        
        switch gesture.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  collectionView.indexPathsForVisibleItems.contains(indexPath) else { return }
            beginOrderingMode(indexPath: indexPath, location: location)

        case .changed:
            guard let source = currentSourceIndexPath, customDragPreview != nil else { return }
            
            let adjusted = location - centerOffset
            lastDragLocationInCollection = adjusted
            self.customDragPreview?.cellCenter = collectionView.convert(adjusted, to: collectionView.superview)
            
            if wasScrollingEnabled {
                let visibleBounds = collectionView.bounds
                if isFlowDirectionHorizontal {
                    if adjusted.x < visibleBounds.minX + autoScrollEdgeInset {
                        autoScrollDirection = .towardStart
                    } else if adjusted.x > visibleBounds.maxX - autoScrollEdgeInset {
                        autoScrollDirection = .towardEnd
                    } else {
                        autoScrollDirection = nil
                    }
                } else {
                    if adjusted.y < visibleBounds.minY + autoScrollEdgeInset {
                        autoScrollDirection = .towardStart
                    } else if adjusted.y > visibleBounds.maxY - autoScrollEdgeInset {
                        autoScrollDirection = .towardEnd
                    } else {
                        autoScrollDirection = nil
                    }
                }
                if autoScrollDirection == nil {
                    stopAutoScroll()
                } else {
                    startAutoScroll()
                }
            }
            
            if let proposed = indexPathForPoint(adjusted), proposed.section == source.section, proposed != source {
                if reorderThrottle.canMove(from: source, to: proposed, at: adjusted) {
                    moveItem(source: source, destination: proposed)
                    currentSourceIndexPath = proposed
                    currentDraggedIndexPath = proposed
                    reorderThrottle.acceptMove(from: source, to: proposed, at: adjusted)
                }
            }
        
        case .ended, .cancelled:
            stopAutoScroll()
            animatePreviewBackAndCleanup()
        
        default:
            break
        }
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        guard autoScrollDisplayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleAutoScroll))
        link.add(to: .main, forMode: .common)
        autoScrollDisplayLink = link
    }

    private func stopAutoScroll() {
        autoScrollDisplayLink?.invalidate()
        autoScrollDisplayLink = nil
        autoScrollDirection = nil
    }

    @objc
    private func handleAutoScroll() {
        guard let autoScrollDirection else { return }

        let offset = collectionView.contentOffset
        var newOffset = offset
        let delta = autoScrollSpeed * autoScrollDirection.rawValue

        if isFlowDirectionHorizontal {
            newOffset.x += delta
            let maxOffsetX = max(0, collectionView.contentSize.width - collectionView.bounds.width)
            newOffset.x = max(0, min(maxOffsetX, newOffset.x))
            if newOffset != offset {
                lastDragLocationInCollection.x += newOffset.x - offset.x
            }
        } else {
            newOffset.y += delta
            let maxOffsetY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
            newOffset.y = max(0, min(maxOffsetY, newOffset.y))
            if newOffset != offset {
                lastDragLocationInCollection.y += newOffset.y - offset.y
            }
        }

        if newOffset != offset {
            collectionView.contentOffset = newOffset
            if let source = currentSourceIndexPath {
                if let proposed = indexPathForPoint(lastDragLocationInCollection), proposed.section == source.section, proposed != source {
                    if reorderThrottle.canMove(from: source, to: proposed, at: lastDragLocationInCollection) {
                        moveItem(source: source, destination: proposed)
                        currentSourceIndexPath = proposed
                        currentDraggedIndexPath = proposed
                        reorderThrottle.acceptMove(from: source, to: proposed, at: lastDragLocationInCollection)
                    }
                }
            }
        }
    }

    // MARK: - Drag finalizing

    private func animatePreviewBackAndCleanup() {
        // Clear some stuff immediately
        reorderThrottle = .init()
        let indexPath = currentSourceIndexPath
        let preview = customDragPreview
        customDragPreview = nil
        currentSourceIndexPath = nil
        guard var preview, let indexPath else {
            finalizePreview(preview)
            return
        }

        collectionView.layoutIfNeeded()
        guard let attrs = collectionView.layoutAttributesForItem(at: indexPath) else {
            finalizePreview(preview)
            return
        }
        
        // If already at the target, skip animation. Animate with distance adaptation otherwise
        let targetCenterInSV = collectionView.convert(attrs.frame.center, to: collectionView.superview)
        let distance = preview.cellCenter.distance(to: targetCenterInSV)
        guard distance > 0.0 else {
            finalizePreview(preview)
            return
        }
        let speed: CGFloat = 1200.0
        let duration = max(0.15, min(distance / speed, 0.25))
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut], animations: {
            preview.cellCenter = targetCenterInSV
            preview.view.layer.opacity = 1.0
        }, completion: { [weak self] _ in
            self?.finalizePreview(preview)
        })
    }
    
    private func finalizePreview(_ preview: InternalCellPreview?) {
        if let currentDraggedIndexPath {
            self.currentDraggedIndexPath = nil
            updateCell(indexPath: currentDraggedIndexPath)
        }
        dropTargetCell?.isHidden = false
        dropTargetCell = nil
        collectionView.isScrollEnabled = wasScrollingEnabled
        preview?.view.removeFromSuperview()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReorderableCollectionViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UILongPressGestureRecognizer else { return false }
        let location = gestureRecognizer.location(in: collectionView)
        if let hit = collectionView.hitTest(location, with: nil), isControlOrInsideControl(hit) { return false }
        return collectionView.indexPathForItem(at: location) != nil
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith
                                  other: UIGestureRecognizer) -> Bool {
        return !isReordering
    }
}

// MARK: - UICollectionViewDragDelegate, UICollectionViewDropDelegate

extension ReorderableCollectionViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession,
                               at indexPath: IndexPath) -> [UIDragItem] {
        guard !isReordering, let cell = collectionView.cellForItem(at: indexPath) else { return [] }
        guard collectionView.numberOfItems(inSection: indexPath.section) > 1 else { return [] }
        
        dragSessionSourceIndexPath = indexPath
        
        let dragItem = UIDragItem(itemProvider: NSItemProvider())
        dragItem.previewProvider = { [weak self] in
            guard let self else { return nil }
            let preview = preview(ofCell: cell, mode: .renderToImage)
            let dragParams = UIDragPreviewParameters(bounds: preview.view.bounds, cornerRadius: preview.cornerRadius)
            return UIDragPreview(view: preview.view, parameters: dragParams)
        }
        return  [dragItem]
    }

    public func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt
                               indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        let preview = preview(ofCell: cell, mode: .empty)
        return UIDragPreviewParameters(bounds: preview.view.frame, cornerRadius: preview.cornerRadius)
    }
    
    public func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt
                               indexPath: IndexPath) -> UIDragPreviewParameters? {
        self.collectionView(collectionView, dragPreviewParametersForItemAt: indexPath)
    }
    
    public func collectionView(_ collectionView: UICollectionView, dragSessionAllowsMoveOperation session: any UIDragSession) -> Bool {
        return !isReordering
    }


    public func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession) {
        currentDraggedIndexPath = dragSessionSourceIndexPath // the cell appearance...
        setReorderingMode(true) // ...will be updated here
    }

    public func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
        dragSessionSourceIndexPath = nil
        
        // Reset cell dragging's appearance in case it has not been done in performDropWith
        if let currentDraggedIndexPath {
            self.currentDraggedIndexPath = nil
            updateCell(indexPath: currentDraggedIndexPath)
        }
    }
        
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession,
                               withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard let src = dragSessionSourceIndexPath, let dest = destinationIndexPath, dest.section == src.section else {
            return .init(operation: .cancel)
        }
        return .init(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first, let source = item.sourceIndexPath,
              let destination = coordinator.destinationIndexPath,
              source.section == destination.section else { return }
        
        // Clear dragging state so the appearance update in dragSessionDidEnd does not conflict; the cell is updated in the animator's completion below.
        currentDraggedIndexPath = nil
        
        moveItem(source: source, destination: destination, silent: true)
        let animator = coordinator.drop(item.dragItem, toItemAt: destination)
        animator.addCompletion { [weak self] _ in
            self?.updateCell(indexPath: destination)
        }
    }
}

// MARK: - UICollectionViewDelegate, UIScrollViewDelegate

extension ReorderableCollectionViewController: UICollectionViewDelegate {
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScroll?(scrollView)
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.scrollViewWillBeginDragging?(scrollView)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        delegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }
    
    public func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt
                               indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isReordering else { return nil }
        guard let indexPath = indexPaths.first else { return nil }
        return delegate?.reorderController(self, contextMenuConfigurationForItemAt: indexPath, point: point)
    }

    public func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                               highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        let preview = preview(ofCell: cell, mode: .fastSnapshot)
        let view = preview.view
        let params = UIPreviewParameters(bounds: view.bounds, cornerRadius: preview.cornerRadius)
      
        let previewCenter = cell.bounds.center + preview.centerOffset
        let targetCenter = collectionView.convert(previewCenter, from: cell)
        let target = UIPreviewTarget(container: collectionView, center: targetCenter)

        return UITargetedPreview(view: view, parameters: params, target: target)
    }

    public func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                               dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        return self.collectionView(collectionView, contextMenuConfiguration: configuration, highlightPreviewForItemAt: indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration:
                               UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        delegate?.reorderController(self, willDisplayContextMenu: configuration, animator: animator)
    }

    public func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                               animator: (any UIContextMenuInteractionAnimating)?) {
        delegate?.reorderController(self, willEndContextMenuInteraction: configuration, animator: animator)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isReordering else { return } // if this check is removed, adjust the long-press gesture recognizer accordingly
        delegate?.reorderController(self, didSelectItemAt: indexPath)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ReorderableCollectionViewController: UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flow = collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        if let size = delegate?.reorderController(self, sizeForItemAt: indexPath) {
            return size
        }
        return flow.itemSize
    }
}

// MARK: - Helpers

private extension UIPreviewParameters {
    convenience init(bounds: CGRect, cornerRadius: CGFloat) {
        self.init()
        
        backgroundColor = .clear
        visiblePath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        let shadowRect = bounds.insetBy(dx: max(1, min(bounds.width / 2, 50)), dy: max(1, min(bounds.height / 2, 50)))
        shadowPath = UIBezierPath(roundedRect: shadowRect, cornerRadius: 0)
    }
}

// MARK: - ReorderableCell

public struct ReorderableCellState: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let reordering  = ReorderableCellState(rawValue: 1 << 0)
    public static let dragging    = ReorderableCellState(rawValue: 1 << 1)
}

public protocol ReorderableCell: UICollectionViewCell {
    var reorderingState: ReorderableCellState { get set }
}

// MARK: - Animations

/// Composable wiggle animation. Attach to any view (e.g. a cell) to get reorder wiggle without subclassing.
public final class WiggleBehavior {

    private weak var view: UIView?

    private let positionAnimationKey = "wiggle_position"
    private let rotationAnimationKey = "wiggle_rotation"
    
    /// Bounds used when the current wiggle animation was added. Used to avoid extended amplitude
    /// when the cell was configured before layout (zero/stale bounds).
    private var lastAppliedBounds: CGRect = .zero

    public init(view: UIView) {
        self.view = view
    }

    public var isWiggling: Bool = false {
        didSet {
            if isWiggling {
                startIfNeeded()
            } else {
                stopIfNeeded()
                lastAppliedBounds = .zero
            }
        }
    }

    /// Call from the host's prepareForReuse (e.g. cell) to stop animation when reused.
    public func prepareForReuse() {
        stopIfNeeded()
        lastAppliedBounds = .zero
    }
    
    private func layerHasAnimations(_ layer: CALayer) -> Bool {
        return layer.animation(forKey: positionAnimationKey) != nil
    }
    
    private func layerIsLargeEnough(_ layer: CALayer) -> Bool {
        // Minimum width to compute rotation from; avoids starting with zero bounds and wrong amplitude.
        let minBoundsWidth: CGFloat = 1
        return layer.bounds.width >= minBoundsWidth
    }
    
    /// Call from the host's layoutSubviews when the view's bounds may have changed (e.g. after scrolling into view).
    /// Restarts the wiggle with current bounds so amplitude is correct when the cell was first configured before layout.
    public func layoutDidChange() {
        guard isWiggling, let layer = view?.layer else { return }

        guard layerIsLargeEnough(layer) else { return }
        if !layerHasAnimations(layer) {
            startIfNeeded()
            return
        }
        if layer.bounds != lastAppliedBounds {
            stopIfNeeded()
            startIfNeeded()
        }
    }

    private func startIfNeeded() {
        guard let layer = view?.layer, !layerHasAnimations(layer), layerIsLargeEnough(layer) else {
            return
        }

        lastAppliedBounds = layer.bounds

        let position = CAKeyframeAnimation(keyPath: "position")
        do {
            let negativeDisplacement = -1.0
            position.duration = 0.4
            position.values = [
                CGPoint(x: negativeDisplacement, y: negativeDisplacement),
                CGPoint(x: 0, y: 0),
                CGPoint(x: negativeDisplacement, y: 0),
                CGPoint(x: 0, y: negativeDisplacement),
                CGPoint(x: negativeDisplacement, y: negativeDisplacement)
            ]
            position.calculationMode = .linear
            position.isRemovedOnCompletion = false
            position.repeatCount = .greatestFiniteMagnitude
            position.beginTime = TimeInterval.random(in: 0..<0.25)
            position.isAdditive = true
        }

        let transform = CAKeyframeAnimation(keyPath: "transform")
        do {
            // limit rotation amplitude to reasonable values depending on view's size
            let refAngle: CGFloat = 2.0
            let refSize = 70.0
            let angle = atan2(tan(refAngle * .pi / 180) * refSize, max(refSize, lastAppliedBounds.width))
            transform.duration = 0.3
            transform.valueFunction = CAValueFunction(name: .rotateZ)
            transform.values = [-angle, angle, -angle]
            transform.calculationMode = .linear
            transform.isRemovedOnCompletion = false
            transform.repeatCount = .greatestFiniteMagnitude
            transform.isAdditive = true
            transform.beginTime = TimeInterval.random(in: 0..<0.25)
        }

        layer.add(position, forKey: positionAnimationKey)
        layer.add(transform, forKey: rotationAnimationKey)
    }
    
    private func stopIfNeeded() {
        guard let layer = view?.layer, layerHasAnimations(layer) else {
            return
        }

        layer.removeAnimation(forKey: positionAnimationKey)
        layer.removeAnimation(forKey: rotationAnimationKey)

        guard let presentationLayer = layer.presentation() else {
            layer.removeAnimation(forKey: positionAnimationKey)
            layer.removeAnimation(forKey: rotationAnimationKey)
            return
        }

        let restPosition = layer.position
        let restTransform = layer.transform
        let currentPosition = presentationLayer.position
        let currentTransform = presentationLayer.transform

        // Match model to current visual state so removing animations doesn't snap
        layer.position = currentPosition
        layer.transform = currentTransform
        layer.removeAnimation(forKey: positionAnimationKey)
        layer.removeAnimation(forKey: rotationAnimationKey)

        let duration = 0.15
        let curve = CAMediaTimingFunction(name: .easeInEaseOut)

        let positionAnim = CABasicAnimation(keyPath: "position")
        positionAnim.fromValue = currentPosition
        positionAnim.toValue = restPosition
        positionAnim.duration = duration
        positionAnim.timingFunction = curve
        positionAnim.isRemovedOnCompletion = true
        layer.position = restPosition
        layer.add(positionAnim, forKey: "return_position")

        let transformAnim = CABasicAnimation(keyPath: "transform")
        transformAnim.fromValue = currentTransform
        transformAnim.toValue = restTransform
        transformAnim.duration = duration
        transformAnim.timingFunction = curve
        transformAnim.isRemovedOnCompletion = true
        layer.transform = restTransform
        layer.add(transformAnim, forKey: "return_transform")
    }
}

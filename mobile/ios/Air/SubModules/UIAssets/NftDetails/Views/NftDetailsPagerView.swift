import UIKit
import UIComponents

protocol NftDetailsPagerDelegate: NftDetailsActionsDelegate {
    func pagerDidSelectModel(_ pager: NftDetailsPagerView, model: NftDetailsItemModel)
    func pagerDidScroll(_ pager: NftDetailsPagerView, withProgress progress: CGFloat, fromModel: NftDetailsItemModel, toModel: NftDetailsItemModel?)
    func pagerDidRequestFullScreenPreview()
}

final class NftDetailsPagerView: UIView {
    typealias ItemModel = NftDetailsItemModel
    
    private var models: [ItemModel]
    private let colorResolver: NftDetailsColorResolver
    private weak var delegate: NftDetailsPagerDelegate?
    private(set) var currentIndex: Int

    struct LayoutGeometry: Equatable {
        let topSafeAreaInset: CGFloat
        let collapsedAreaHeight: CGFloat
        let pageWidth: CGFloat

        func toPageGeometry() -> NftDetailsPageView.LayoutGeometry {
            .init(
                expandedHeight: pageWidth,
                collapsedHeight: collapsedAreaHeight + topSafeAreaInset,
                width: pageWidth
            )
        }
        
        func expandedFrame() -> CGRect { .square(pageWidth) }
    }
    
    var layoutGeometry: LayoutGeometry {
        didSet {
            if layoutGeometry != oldValue {
                onLayoutGeometryChanged()
            }
        }
    }
    
    private(set) var isExpanded: Bool = false
    private(set) var isUserDragging: Bool = false
    private var needsInitialScroll = true
    private var ignoreDidScroll = false
    private var isAnimating: Bool = false

    private struct PageViewCacheItem {
        let view: NftDetailsPageView
    }

    private var pageViewCache: [String: PageViewCacheItem] = [:]

    private var heightConstraint: NSLayoutConstraint!
    private var collectionView: CollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var dataSource: UICollectionViewDiffableDataSource<_Section, String>!

    private enum _Section: Hashable { case main }

    init(
        models: [ItemModel],
        colorResolver: NftDetailsColorResolver,
        currentIndex: Int,
        layoutGeometry: LayoutGeometry,
        delegate: NftDetailsPagerDelegate,
        initiallyExpanded: Bool
    ) {
        assert(layoutGeometry.pageWidth > 0)

        self.models = models
        self.colorResolver = colorResolver
        self.currentIndex = currentIndex
        self.layoutGeometry = layoutGeometry
        self.delegate = delegate
        self.isExpanded = initiallyExpanded

        super.init(frame: .fromSize(width: layoutGeometry.pageWidth, height: 1000))

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        ignoreDidScroll = true
        do {
            defer { ignoreDidScroll = false }
            super.layoutSubviews()
        }
        
        if needsInitialScroll {
            needsInitialScroll = false
            collectionView.layoutIfNeeded()
            scrollToIndex(currentIndex, animated: false)
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        let itemSize = 2000.0 // should be enough. This is mainly for content touch support
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.estimatedItemSize = CGSize(width: layoutGeometry.pageWidth, height: itemSize)

        collectionView = CollectionView(frame: bounds, collectionViewLayout: flowLayout)
        collectionView.delegate = self
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        heightConstraint = heightAnchor.constraint(equalToConstant: 100)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: itemSize),
            heightConstraint,
        ])
        
        let cellRegistration = UICollectionView.CellRegistration<_PageCell, String> { [weak self] cell, _, modelId in
            // In RTL the physical item order is reversed, so resolve the logical model by id
            // instead of using `indexPath.row` (which is the physical position).
            guard let self, let index = self.models.firstIndex(where: { $0.id == modelId }) else { return }
            let pv = self.getOrCreatePageView(for: index)
            cell.setPageView(pv)
        }

        dataSource = UICollectionViewDiffableDataSource<_Section, String>(collectionView: collectionView) { cv, indexPath, item in
            cv.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        var snapshot = NSDiffableDataSourceSnapshot<_Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(arrangedModelIds)
        dataSource.apply(snapshot, animatingDifferences: false)

        scrollToIndex(currentIndex, animated: false)
        updateHeight()
    }

    private func getOrCreatePageView(for index: Int, layout: Bool = true) -> NftDetailsPageView {
        let idx = normalizeIndex(index)
        let model = models[idx]
        if let cached = pageViewCache[model.id] {
            if layout {
                cached.view.updateWith(layoutGeometry: layoutGeometry.toPageGeometry(), isExpanded: isExpanded)
            }
            cached.view.model.requestImage()
            return cached.view
        }
        
        let pv = NftDetailsPageView(
            model: model,
            colorResolver: colorResolver,
            layoutGeometry: layoutGeometry.toPageGeometry(),
            isExpanded: isExpanded,
            delegate: self
        )
        pageViewCache[model.id] = .init(view: pv)
        pv.model.requestImage()
        return pv
    }

    func removeModel(id: String, newModels: [ItemModel], newCurrentIndex: Int, animated: Bool) {
        guard models.contains(where: { $0.id == id }) else { return }
        self.models = newModels

        if let cached = pageViewCache.removeValue(forKey: id) {
            cached.view.removeFromSuperview()
        }

        currentIndex = normalizeIndex(newCurrentIndex)

        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([id])
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            self.ignoreDidScroll = true
            // Force layout so `contentSize` reflects the new item count before scrolling, otherwise
            // `setContentOffset` clamps to a stale (shorter) content width and lands one page short.
            self.collectionView.layoutIfNeeded()
            self.scrollToIndex(self.currentIndex, animated: false)
            self.ignoreDidScroll = false
            self.updateHeight()
        }
    }

    /// Reconciles the pager to an arbitrary new model list (insertions, removals and reorders),
    /// keyed by NFT id, then re-centers on `newCurrentIndex`. Cached page views for ids that are
    /// no longer present are torn down so they don't linger.
    func setModels(_ newModels: [ItemModel], newCurrentIndex: Int, animated: Bool) {
        let newIds = Set(newModels.map(\.id))
        for (id, cached) in pageViewCache where !newIds.contains(id) {
            cached.view.removeFromSuperview()
            pageViewCache.removeValue(forKey: id)
        }

        self.models = newModels
        currentIndex = normalizeIndex(newCurrentIndex)

        var snapshot = NSDiffableDataSourceSnapshot<_Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(arrangedModelIds)
        // Apply synchronously (no animation needed for a re-selection) and reposition through the same
        // path the first appearance uses: `needsInitialScroll` + `layoutSubviews`. Scrolling inside the
        // async `apply` completion raced with the appearance-transition layout, which restored the old
        // offset and left the page one off; deferring to `layoutSubviews` makes it land reliably.
        dataSource.apply(snapshot, animatingDifferences: false)

        needsInitialScroll = true
        setNeedsLayout()

        ignoreDidScroll = true
        collectionView.layoutIfNeeded()
        scrollToIndex(currentIndex, animated: false)
        ignoreDidScroll = false
        updateHeight()
    }

    private func onLayoutGeometryChanged() {
        updateHeight()
    }
    
    private func normalizeIndex(_ index: Int) -> Int {
        min(max(0, index), models.count - 1)
    }

    private func setCurrentIndex(_ index: Int, animated: Bool) {
        let newIndex = normalizeIndex(index)
        guard newIndex != currentIndex else { return }
        
        currentIndex = newIndex
        scrollToIndex(currentIndex, animated: animated)
        updateHeight()
        delegate?.pagerDidSelectModel(self, model: models[currentIndex])
    }

    /// Scrolls to `index` exactly like a user swipe: `scrollProgress` drives the background on every frame and `pagerDidSelectModel`
    /// fires only when the animation settles — no premature background flash.
    ///
    /// If the pager is already at the target offset (e.g. cover-flow user-scroll tracked the pager in real time),
    /// falls through to `setCurrentIndex` directly, since a zero-delta animated scroll never fires `scrollViewDidEndScrollingAnimation`.
    func animateToIndex(_ index: Int) {
        let newIndex = normalizeIndex(index)
        guard newIndex != currentIndex else { return }
        
        let targetOffsetX = contentOffsetX(forLogicalIndex: newIndex)
        if abs(collectionView.contentOffset.x - targetOffsetX) < 1 {
            setCurrentIndex(newIndex, animated: false)
        } else {
            scrollToIndex(newIndex, animated: true)
        }
    }

    private func scrollToIndex(_ index: Int, animated: Bool) {
        let offset = CGPoint(x: contentOffsetX(forLogicalIndex: index), y: 0)
        collectionView.setContentOffset(offset, animated: animated)
    }

    private func updateHeight() {
        let height = getOrCreatePageView(for: currentIndex).getFullHeight()
        heightConstraint.constant = height
        flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: height)
    }

    /// Set the pager's scroll position to match cover flow progress.
    /// progress is in [-0.5, 0.5]: -0.5 = halfway to previous item, 0.5 = halfway to next.
    func syncPagerWithCoverFlow(_ progress: CGFloat, currentModel: ItemModel) {
        guard !isExpanded else { return }
        let logicalProgress = CGFloat(currentModel.index) + progress
        let targetOffsetX = contentOffsetX(forLogicalProgress: logicalProgress)
        collectionView.setContentOffset(CGPoint(x: targetOffsetX, y: 0), animated: false)
    }

    // MARK: - RTL-aware page positioning
    //
    // `UICollectionViewFlowLayout` does not mirror itself for right-to-left languages, so the content
    // always grows left→right. To make the pager read right-to-left we reverse the physical item order
    // and translate between *logical* indices/progress (0 = first model) and *physical* content offsets.

    private var usesRightToLeftPageLayout: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    private var arrangedModelIds: [String] {
        let ids = models.map(\.id)
        return usesRightToLeftPageLayout ? ids.reversed() : ids
    }

    private var maxPageProgress: CGFloat {
        CGFloat(max(models.count - 1, 0))
    }

    private func physicalPage(forLogicalIndex index: Int) -> Int {
        let logicalIndex = normalizeIndex(index)
        if let item = dataSource?.indexPath(for: models[logicalIndex].id)?.item {
            return item
        }
        return usesRightToLeftPageLayout ? models.count - 1 - logicalIndex : logicalIndex
    }

    private func contentOffsetX(forLogicalIndex index: Int) -> CGFloat {
        CGFloat(physicalPage(forLogicalIndex: index)) * layoutGeometry.pageWidth
    }

    private func contentOffsetX(forLogicalProgress progress: CGFloat) -> CGFloat {
        let logicalProgress = min(max(progress, 0), maxPageProgress)
        let physicalProgress = usesRightToLeftPageLayout ? maxPageProgress - logicalProgress : logicalProgress
        return physicalProgress * layoutGeometry.pageWidth
    }

    private func logicalProgress(forContentOffsetX offsetX: CGFloat) -> CGFloat {
        let pageWidth = layoutGeometry.pageWidth
        guard pageWidth > 0 else { return CGFloat(currentIndex) }
        let physicalProgress = min(max(offsetX / pageWidth, 0), maxPageProgress)
        return usesRightToLeftPageLayout ? maxPageProgress - physicalProgress : physicalProgress
    }

    private let animationDuration: TimeInterval = 0.35

    private func collapse(scrollView: UIScrollView) {
        guard !isAnimating else { return }
        isAnimating = true
        isExpanded = false

        let centralPage = getOrCreatePageView(for: currentIndex)
        centralPage.collapse()
        let newHeight = centralPage.getFullHeight()

        heightConstraint.constant = newHeight
        flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: newHeight)

        Haptics.play(.transition)
        UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
            scrollView.contentOffset = .zero
            scrollView.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.isAnimating = false
        }
    }

    private func expand(extraScrollDownHeight: CGFloat, scrollView: UIScrollView) {
        guard !isAnimating else { return }
        isAnimating = true
        isExpanded = true

        let centralPage = getOrCreatePageView(for: currentIndex, layout: false)
        centralPage.expand(extraScrollDownHeight: extraScrollDownHeight)
        let newHeight = centralPage.getFullHeight()

        heightConstraint.constant = newHeight
        flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: newHeight)

        Haptics.play(.transition)
        UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
            scrollView.contentOffset = .zero
            scrollView.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.isAnimating = false
        }
    }

    private let scrollExpandThreshold = -10.0
    private let scrollExpandToFullScreenThreshold = -30.0
    private let scrollCollapseThreshold = 20.0
    
    private var canBeDraggedToFullScreen = false
    private var pendingProgrammaticExpand = false

    func simulateUserScrollToExpand(_ parentScrollView: UIScrollView) {
        pendingProgrammaticExpand = true
        parentScrollView.setContentOffset(.init(x: 0, y: scrollExpandThreshold - 5), animated: false)
    }

    private func simulateUserScrollToFullScreen(_ parentScrollView: UIScrollView) {
        canBeDraggedToFullScreen = true
        parentScrollView.setContentOffset(.init(x: 0, y: scrollExpandToFullScreenThreshold - 5), animated: false)
    }

    func handleEndDecelerating() {
        canBeDraggedToFullScreen = true
    }
    
    func handleEndDragging(willDecelerate decelerate: Bool) {
        if !decelerate {
            canBeDraggedToFullScreen = true
        }
    }
        
    func handleVerticalScroll(_ parentScrollView: UIScrollView) {
        let offsetY = parentScrollView.contentOffset.y
        if isExpanded {
            _ = getOrCreatePageView(for: currentIndex)
            if !isAnimating {
                if offsetY > scrollCollapseThreshold {
                    collapse(scrollView: parentScrollView)
                } else {
                    if offsetY < scrollExpandToFullScreenThreshold, canBeDraggedToFullScreen {
                        parentScrollView.panGestureRecognizer.isEnabled = false
                        parentScrollView.panGestureRecognizer.isEnabled = true
                        delegate?.pagerDidRequestFullScreenPreview()
                        collapse(scrollView: parentScrollView)
                    }
                }
            }
        } else {
            let shouldExpand = pendingProgrammaticExpand || (parentScrollView.isDragging && !parentScrollView.isDecelerating)
            if !isAnimating, offsetY < scrollExpandThreshold, shouldExpand {
                expand(extraScrollDownHeight: -offsetY, scrollView: parentScrollView)
                if pendingProgrammaticExpand {
                    pendingProgrammaticExpand = false
                    canBeDraggedToFullScreen = true // after programmatic expanding we can immediately go to full screen mode
                } else {
                    canBeDraggedToFullScreen = false // prevent further expanding until user lifts a finger
                }
            }
        }
    }

    private var parentScrollView: UIScrollView? {
        var v: UIView? = superview
        while v != nil, !(v is UIScrollView) { v = v?.superview }
        return v as? UIScrollView
    }
}

private final class _PageCell: UICollectionViewCell {
    private var pageView: NftDetailsPageView?

    private var pageViewTopConstraint: NSLayoutConstraint!
    private var pageViewLeadingConstraint: NSLayoutConstraint!

    func setPageView(_ pv: NftDetailsPageView) {
        guard pv !== pageView else { return }

        clearPageView()

        pageView = pv
        pv.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pv)

        pageViewTopConstraint = pv.topAnchor.constraint(equalTo: contentView.topAnchor)
        pageViewLeadingConstraint = pv.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        NSLayoutConstraint.activate([
            pageViewTopConstraint,
            pageViewLeadingConstraint
        ])
    }
    
    private func clearPageView() {
        NSLayoutConstraint.deactivate(
            [pageViewTopConstraint, pageViewLeadingConstraint].compactMap { $0 }
        )
        pageViewTopConstraint = nil
        pageViewLeadingConstraint = nil
        pageView?.removeFromSuperview()
        pageView = nil
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        clearPageView()
    }
}

extension NftDetailsPagerView: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let pageWidth = layoutGeometry.pageWidth
        guard pageWidth > 0, !ignoreDidScroll else { return }

        // Derive progress from the raw scroll offset rather than the stale `currentIndex`
        // so that fast multi-page swipes are reflected by the cover flow and background
        // on every frame, even before `currentIndex` is updated at the end of deceleration.
        let rawIndex = logicalProgress(forContentOffsetX: offsetX)
        let leftIndex = normalizeIndex(Int(floor(rawIndex)))
        let rightIndex = normalizeIndex(leftIndex + 1)
        let frac = rawIndex - CGFloat(leftIndex)

        let fromModel = models[leftIndex]
        let toModel = leftIndex < rightIndex ? models[rightIndex] : nil
                
        // Make sure that we schedule image loading for neighbours
        for i in normalizeIndex(leftIndex - 2)...normalizeIndex(rightIndex + 2) {
            models[i].requestImage()
        }
        
        delegate?.pagerDidScroll(self, withProgress: frac, fromModel: fromModel, toModel: toModel)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserDragging = true
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserDragging = false
        handleScrollEnd(scrollView: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isUserDragging = false
            handleScrollEnd(scrollView: scrollView)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        handleScrollEnd(scrollView: scrollView)
    }

    private func handleScrollEnd(scrollView: UIScrollView) {
        let pageIndex = normalizeIndex(Int(round(logicalProgress(forContentOffsetX: scrollView.contentOffset.x))))
        guard pageIndex != currentIndex else { return }

        let newPageView = getOrCreatePageView(for: pageIndex)

        if let parentSV = parentScrollView, parentSV.contentOffset.y + parentSV.adjustedContentInset.top > 0 {
            let newHeight = newPageView.getFullHeight()
            heightConstraint.constant = newHeight
            flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: newHeight)

            UIView.animate(withDuration: 0.25, animations: {
                parentSV.layoutIfNeeded()
            }, completion: { [weak self] _ in
                self?.setCurrentIndex(pageIndex, animated: false)
            })
        } else {
            setCurrentIndex(pageIndex, animated: false)
        }
    }
}

extension NftDetailsPagerView: NftDetailsPageViewDelegate {
    func pageDidRequestFullScreenPreview() {
        if let parentScrollView {
            simulateUserScrollToFullScreen(parentScrollView)
        }
    }
    
    func ntfDetailsOnConfigureAction(forModel model: ItemModel, action: ItemModel.Action) -> NftDetailsActionConfig? {
        delegate?.ntfDetailsOnConfigureAction(forModel: model, action: action)
    }
}

extension NftDetailsPagerView {
    
    private final class CollectionView: UICollectionView, UIGestureRecognizerDelegate {
        private var legacyFullWidthBackPan: UIPanGestureRecognizer?
        private var legacyFullWidthBackPanStartX: CGFloat?
        
        override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
            super.init(frame: frame, collectionViewLayout: layout)

            assert(panGestureRecognizer.delegate === self, "Something changed in UIKit. It's not critical, but it's worth knowing ASAP")
            if #available(iOS 26.0, *) {
                //
            } else {
                let p = UIPanGestureRecognizer()
                p.addTarget(self, action: #selector(handleFullWidthBackPan(_:)))
                p.delegate = self
                p.cancelsTouchesInView = false
                addGestureRecognizer(p)
                legacyFullWidthBackPan = p
            }
            
            isPagingEnabled = true
            showsHorizontalScrollIndicator = false
            clipsToBounds = false
            backgroundColor = .clear
            bounces = false
            if #available(iOS 26.0, *) {
                topEdgeEffect.isHidden = true
                bottomEdgeEffect.isHidden = true
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func isAtFirstPageEdge() -> Bool {
            // The first (logical) page is the one the interactive back gesture should pop from. In RTL the
            // physical page order is reversed, so that page sits at the *maximum* content offset, not the minimum.
            if effectiveUserInterfaceLayoutDirection == .rightToLeft {
                let maxOffsetX = contentSize.width + adjustedContentInset.right - bounds.width
                return contentOffset.x >= maxOffsetX - 1
            } else {
                let minOffsetX = -adjustedContentInset.left
                return contentOffset.x <= minOffsetX + 1
            }
        }
        
        private func locationIsInLeadingEdgeStrip(_ x: CGFloat) -> Bool {
            let leadingEdgeWidth: CGFloat = 28
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                return x >= bounds.width - leadingEdgeWidth
            default:
                return x <= leadingEdgeWidth
            }
        }
        
        private func isBackSwipe(translation: CGPoint, velocity: CGPoint) -> Bool {
            let minTranslation: CGFloat = 56
            let maxTranslation: CGFloat = 120
            let minVelocity: CGFloat = 50
            
            guard abs(translation.y) < abs(translation.x) * 0.75 else { return false }
            
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                guard translation.x < -minTranslation else { return false }
                return velocity.x < -minVelocity || translation.x < -maxTranslation
            default:
                guard translation.x > minTranslation else { return false }
                return velocity.x > minVelocity || translation.x > maxTranslation
            }
        }
        
        @objc private func handleFullWidthBackPan(_ gesture: UIPanGestureRecognizer) {
            guard let nav = nearestValidNavigationController else { return }
            
            switch gesture.state {
            case .began:
                legacyFullWidthBackPanStartX = gesture.location(in: self).x
            case .ended, .cancelled:
                defer { legacyFullWidthBackPanStartX = nil }
                guard isAtFirstPageEdge(), let startX = legacyFullWidthBackPanStartX, !locationIsInLeadingEdgeStrip(startX) else { return }
                let t = gesture.translation(in: self)
                let v = gesture.velocity(in: self)
                guard isBackSwipe(translation: t, velocity: v) else { return }
                nav.popViewController(animated: true)
            default:
                break
            }
        }
        
        private var nearestValidNavigationController: UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let vc = current as? UIViewController {
                    let nav = vc.navigationController
                    if nav?.viewControllers.count ?? 0 > 1 {
                        return nav
                    }
                    break
                }
                responder = current.next
            }
            return nil
        }
       
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            
            if gestureRecognizer === legacyFullWidthBackPan {
                return nearestValidNavigationController != nil && isAtFirstPageEdge()
            }
            
            // Allow swipe back from the left edge OR being at the first page
            if gestureRecognizer === panGestureRecognizer {
                let panLocationX = gestureRecognizer.location(in: superview).x - frame.minX
                if locationIsInLeadingEdgeStrip(panLocationX) {
                    return false
                }
                return true
            }
            
            return true
        }
        
        private func getInteractivePopRecognizers(_ nav: UINavigationController) -> [UIGestureRecognizer] {
            var result = [UIGestureRecognizer]()
            if let edge = nav.interactivePopGestureRecognizer {
                result.append(edge)
            }
            if #available(iOS 26.0, *) {
                if let content = nav.interactiveContentPopGestureRecognizer {
                    result.append(content)
                }
            }
            return result
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panGestureRecognizer, isAtFirstPageEdge(), let nav = nearestValidNavigationController else { return false }
            
            if getInteractivePopRecognizers(nav).contains(otherGestureRecognizer) {
                return otherGestureRecognizer.isEnabled
            }
            return false
        }
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            
            // Allow swipe vertically in legacy OS (make sense at the very first page)
            if gestureRecognizer == legacyFullWidthBackPan, otherGestureRecognizer.view is UIScrollView {
                return true
            }

            guard let nav = nearestValidNavigationController, isAtFirstPageEdge() else { return false }
            let interactiveRecognizers = getInteractivePopRecognizers(nav)
            
            func isPair(_ a: UIGestureRecognizer, _ b: UIGestureRecognizer) -> Bool {
                (gestureRecognizer === a && otherGestureRecognizer === b) || (gestureRecognizer === b && otherGestureRecognizer === a)
            }
            
            let panGR = panGestureRecognizer
            
            for gr in interactiveRecognizers {
                if isPair(panGR, gr) {
                    return gr.isEnabled
                }
            }
            
            if let full = legacyFullWidthBackPan {
                if isPair(full, panGR) {
                    return true
                }
                for gr in interactiveRecognizers {
                    if isPair(full, gr) {
                        return gr.isEnabled
                    }
                }
            }
            
            return false
        }
    }
}

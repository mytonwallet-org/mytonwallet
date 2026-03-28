import UIKit
import UIComponents

protocol NftDetailsPagerDelegate: NftDetailsActionsDelegate {
    func pagerDidSelectModel(_ pager: NftDetailsPagerView, model: NftDetailsItemModel)
    func pagerRequestSelectedCoverFlowItemFrame() -> CGRect
    func pagerDidChangeExpansionState(_ pager: NftDetailsPagerView)
    func pagerDidScroll(_ pager: NftDetailsPagerView, withProgress progress: CGFloat,
                        fromModel: NftDetailsItemModel, toModel: NftDetailsItemModel?)
    func pagerDidRequestFullScreenPreview(forModel model: NftDetailsItemModel, view: UIView)
    func pagerWantsToSwipeBackTheFirstPage()
}

final class NftDetailsPagerView: UIView {
    private let models: [NftDetailsItemModel]

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
    
    let hideStaticPreview: Bool

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
    private var isAnimating: Bool = false

    private struct PageViewCacheItem {
        let view: NftDetailsPageView
    }

    private var pageViewCache: [Int: PageViewCacheItem] = [:]

    private var heightConstraint: NSLayoutConstraint!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var dataSource: UICollectionViewDiffableDataSource<_Section, Int>!

    private enum _Section: Hashable { case main }

    init(
        models: [NftDetailsItemModel],
        currentIndex: Int,
        layoutGeometry: LayoutGeometry,
        delegate: NftDetailsPagerDelegate,
        hideStaticPreview: Bool,
        initiallyExpanded: Bool = false
    ) {
        assert(layoutGeometry.pageWidth > 0)

        self.models = models
        self.currentIndex = currentIndex
        self.layoutGeometry = layoutGeometry
        self.delegate = delegate
        self.hideStaticPreview = hideStaticPreview
        self.isExpanded = initiallyExpanded

        super.init(frame: .fromSize(width: layoutGeometry.pageWidth, height: 1000))

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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

        collectionView = UICollectionView(frame: bounds, collectionViewLayout: flowLayout)
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.clipsToBounds = false
        collectionView.backgroundColor = .clear
        collectionView.bounces = false
        collectionView.delegate = self
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.isHidden = true
            collectionView.bottomEdgeEffect.isHidden = true
        }
        collectionView.panGestureRecognizer.addTarget(self, action: #selector(handleDismissPan))
        
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
        
        let cellRegistration = UICollectionView.CellRegistration<_PageCell, Int> { [weak self] cell, _, modelIndex in
            guard let self else { return }
            let pv = self.getOrCreatePageView(for: modelIndex)
            cell.setPageView(pv)
        }

        dataSource = UICollectionViewDiffableDataSource<_Section, Int>(collectionView: collectionView) { cv, indexPath, item in
            cv.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        var snapshot = NSDiffableDataSourceSnapshot<_Section, Int>()
        snapshot.appendSections([.main])
        snapshot.appendItems(Array(0..<models.count))
        dataSource.apply(snapshot, animatingDifferences: false)

        scrollToIndex(currentIndex, animated: false)
        updateHeight()
    }
    
    @objc private func handleDismissPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        let translation = gestureRecognizer.translation(in: self)
        let velocity = gestureRecognizer.velocity(in: self)
        if gestureRecognizer.state == .ended {
            if translation.x > 30 && abs(translation.y) < translation.x {
                if velocity.x > 500 {
                    if collectionView.contentOffset.x.isZero {
                        delegate?.pagerWantsToSwipeBackTheFirstPage()
                    }
                }
            }
        }
    }
        
    private func getOrCreatePageView(for index: Int, layout: Bool = true) -> NftDetailsPageView {
        let idx = normalizeIndex(index)
        if let cached = pageViewCache[idx] {
            if layout {
                cached.view.updateWith(layoutGeometry: layoutGeometry.toPageGeometry(), isExpanded: isExpanded)
            }
            cached.view.model.requestImage()
            return cached.view
        }
        
        let pv = NftDetailsPageView(
            model: models[idx],
            layoutGeometry: layoutGeometry.toPageGeometry(),
            isExpanded: isExpanded,
            delegate: self
        )
        pageViewCache[idx] = .init(view: pv)
        pv.model.requestImage()
        return pv
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
        
        if isExpanded {
            let page = getOrCreatePageView(for: currentIndex, layout: false)
            page.playLottieIfPossible()
        }
    }

    /// Scrolls to `index` exactly like a user swipe: `scrollProgress` drives the background on every frame and `pagerDidSelectModel`
    /// fires only when the animation settles — no premature background flash.
    ///
    /// If the pager is already at the target offset (e.g. cover-flow user-scroll tracked the pager in real time),
    /// falls through to `setCurrentIndex` directly, since a zero-delta animated scroll never fires `scrollViewDidEndScrollingAnimation`.
    func animateToIndex(_ index: Int) {
        let newIndex = normalizeIndex(index)
        guard newIndex != currentIndex else { return }
        
        let targetOffsetX = CGFloat(newIndex) * layoutGeometry.pageWidth
        if abs(collectionView.contentOffset.x - targetOffsetX) < 1 {
            setCurrentIndex(newIndex, animated: false)
        } else {
            scrollToIndex(newIndex, animated: true)
        }
    }

    private func scrollToIndex(_ index: Int, animated: Bool) {
        let offset = CGPoint(x: CGFloat(index) * layoutGeometry.pageWidth, y: 0)
        collectionView.setContentOffset(offset, animated: animated)
    }

    private func updateHeight() {
        let height = getOrCreatePageView(for: currentIndex).getFullHeight()
        heightConstraint.constant = height
        flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: height)
    }

    /// Set the pager's scroll position to match cover flow progress.
    /// progress is in [-0.5, 0.5]: -0.5 = halfway to previous item, 0.5 = halfway to next.
    func syncPagerWithCoverFlow(_ progress: CGFloat, currentModelId: String) {
        guard !isExpanded else { return }
        guard let itemIndex = models.findIndexById(currentModelId) else { return }
        let targetOffsetX = (CGFloat(itemIndex) + CGFloat(progress)) * layoutGeometry.pageWidth
        collectionView.setContentOffset(CGPoint(x: targetOffsetX, y: 0), animated: false)
    }

    private let animationDuration: TimeInterval = 0.35

    private func collapse(scrollView: UIScrollView) {
        guard !isAnimating, let delegate else { return }
        isAnimating = true
        isExpanded = false
        delegate.pagerDidChangeExpansionState(self)

        let centralPage = getOrCreatePageView(for: currentIndex)
        var startFrame = delegate.pagerRequestSelectedCoverFlowItemFrame()
        startFrame.origin.y -= scrollView.contentOffset.y
        centralPage.collapse(previewEndFrame: startFrame)
        let newHeight = centralPage.getFullHeight()

        heightConstraint.constant = newHeight
        flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: newHeight)

        Haptics.play(.transition)
        UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
            scrollView.contentOffset = .zero
            scrollView.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.isAnimating = false
            centralPage.commitCollapsion()
        }
    }

    private func expand(extraScrollDownHeight: CGFloat, scrollView: UIScrollView) {
        guard !isAnimating, let delegate else { return }
        isAnimating = true
        isExpanded = true
        delegate.pagerDidChangeExpansionState(self)

        let centralPage = getOrCreatePageView(for: currentIndex, layout: false)
        let startFrame = delegate.pagerRequestSelectedCoverFlowItemFrame()
        centralPage.expand(extraScrollDownHeight: extraScrollDownHeight, previewStartFrame: startFrame)
        let newHeight = centralPage.getFullHeight()

        heightConstraint.constant = newHeight
        flowLayout.itemSize = CGSize(width: layoutGeometry.pageWidth, height: newHeight)

        Haptics.play(.transition)
        UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
            scrollView.contentOffset = .zero
            scrollView.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.isAnimating = false
            centralPage.commitExpansion()
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
            let centralPage = getOrCreatePageView(for: currentIndex)
            centralPage.updateExpandedPreview(extraScrollDownHeight: -offsetY)
            if !isAnimating {
                if offsetY > scrollCollapseThreshold {
                    collapse(scrollView: parentScrollView)
                } else {
                    if offsetY < scrollExpandToFullScreenThreshold, canBeDraggedToFullScreen {
                        centralPage.expandToFullScreenPreview()
                    }
                }
            }
        } else {
            let shouldExpand = pendingProgrammaticExpand || (parentScrollView.isDragging && !parentScrollView.isDecelerating)
            if !isAnimating, offsetY < scrollExpandThreshold, shouldExpand {
                expand(extraScrollDownHeight: -offsetY, scrollView: parentScrollView)
                pendingProgrammaticExpand = false
                canBeDraggedToFullScreen = false // prevent further expanding until user lifts a finger
            }
        }
    }

    private var parentScrollView: UIScrollView? {
        var v: UIView? = superview
        while v != nil, !(v is UIScrollView) { v = v?.superview }
        return v as? UIScrollView
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard point.y > collectionView.frame.maxY else {
            return super.hitTest(point, with: event)
        }

        let pointAtBottomOfContent = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.maxY - 1)
        return collectionView.hitTest(pointAtBottomOfContent, with: event) ?? collectionView
    }
}

private final class _PageCell: UICollectionViewCell {
    private var pageView: NftDetailsPageView?

    private var pageViewTopConstraint: NSLayoutConstraint!
    private var pageViewLeadingConstraint: NSLayoutConstraint!

    func setPageView(_ pv: NftDetailsPageView) {
        guard pv !== pageView else { return }

        pageView?.removeFromSuperview()

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
}

extension NftDetailsPagerView: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let pageWidth = layoutGeometry.pageWidth
        guard pageWidth > 0 else { return }

        // Derive progress from the raw scroll offset rather than the stale `currentIndex`
        // so that fast multi-page swipes are reflected by the cover flow and background
        // on every frame, even before `currentIndex` is updated at the end of deceleration.
        let rawIndex = offsetX / pageWidth
        let leftIndex = normalizeIndex(Int(rawIndex))
        let rightIndex = normalizeIndex(leftIndex + 1)
        let frac = rawIndex - CGFloat(leftIndex)

        let fromModel = models[leftIndex]
        let toModel = leftIndex < rightIndex ? models[rightIndex] : nil
        
        // Hide previews for static (scrolled to exact page boundaries) states
        let isHidden = hideStaticPreview && !frac.isZero
        getOrCreatePageView(for: leftIndex, layout: false).setPreviewHidden(isHidden)
        if toModel != nil {
            getOrCreatePageView(for: rightIndex, layout: false).setPreviewHidden(isHidden)
        }
        
        // Make sure that we schedule image loading for neighbours
        for i in normalizeIndex(leftIndex - 2)...normalizeIndex(rightIndex + 1) {
            models[i].requestImage()
        }
        
        // We requested image loading for the center and for the right page. A special request to
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
        let pageIndex = normalizeIndex(Int(round(scrollView.contentOffset.x / layoutGeometry.pageWidth)))
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
    func ntfDetailsOnConfigureToolbarButton(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsToolbarButtonConfig? {
        delegate?.ntfDetailsOnConfigureToolbarButton(forModel: model, action: action)
    }

    func nftDetailsOnRenewDomain(forModel model: NftDetailsItemModel) {
        delegate?.nftDetailsOnRenewDomain(forModel: model)
    }

    func nftDetailsOnShowCollection(forModel model: NftDetailsItemModel) {
        delegate?.nftDetailsOnShowCollection(forModel: model)
    }

    func pageDidRequestFullScreenPreview(forModel model: NftDetailsItemModel, view: UIView) {
        delegate?.pagerDidRequestFullScreenPreview(forModel: model, view: view)
    }
}

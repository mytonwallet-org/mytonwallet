import UIKit
import Kingfisher

protocol NftDetailsMainHeaderViewDelegate: AnyObject {
    func headerCoverFlowDidSelectModel(_ model: NftDetailsItemModel)
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModelId: String)
    func headerCoverFlowDidTapSelectedModel()
    func headerDidChangePreviewVisibilityInternaly(_ headerView: NftDetailsMainHeaderView)
}

class NftDetailsMainHeaderView: UIView {
    private weak var delegate: NftDetailsMainHeaderViewDelegate?

    private var coverFlowTopConstraint: NSLayoutConstraint!
    private var previewTransformAnimator: UIViewPropertyAnimator?
    private var previewExpandAnimator: UIViewPropertyAnimator?
    
    private let gradientLayer = CAGradientLayer()
    private let coverFlowView: _CoverFlowView
    private let preview: NftDetailsItemPreview
    private var selectedModel: NftDetailsItemModel
    private let models: [NftDetailsItemModel]
    private var fullScreenOverlay: NftDetailsFullScreenOverlay?

    struct LayoutGeometry: Equatable {
        let topSafeAreaInset: CGFloat
        let collapsedAreaHeight: CGFloat
        let pageWidth: CGFloat
        let carouselItemSize: CGFloat = 144
        let carouselTileCornerRadius: CGFloat = 12
        var fullCollapsedHeight: CGFloat { collapsedAreaHeight + topSafeAreaInset }
        var coverFlowTop: CGFloat { topSafeAreaInset }
        var previewCenterY: CGFloat { topSafeAreaInset + carouselItemSize / 2 }
    }
    
    @MainActor
    private class ScheduledAction {
        private static var counter = 0
        private var workItem: DispatchWorkItem?
        
        func cancel() {
            Self.counter += 1
            workItem?.cancel()
            workItem = nil
        }
        
        func schedule(after delay: TimeInterval, execute body: @escaping () -> Void) {
            cancel()
            let myCounter = Self.counter
            let workItem = DispatchWorkItem {
                if Self.counter == myCounter {
                    body()
                }
            }
            self.workItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private var scheduledAction = ScheduledAction()
    
    private struct State {
        var isExpanded: Bool
        var isHidden: Bool
        var isFullScreen: Bool
        var canShowPreview: Bool
    }
    
    private var state: State
    
    var layoutGeometry: LayoutGeometry {
        didSet {
            guard layoutGeometry != oldValue else { return }
            coverFlowTopConstraint.constant = layoutGeometry.coverFlowTop
            preview.centerYConstraint?.constant = layoutGeometry.previewCenterY
        }
    }
    
    init(frame: CGRect, models: [NftDetailsItemModel], selectedModel: NftDetailsItemModel,
         delegate: NftDetailsMainHeaderViewDelegate, layoutGeometry: LayoutGeometry,
         coverFlowThumbnailDownloader: ImageDownloader, colorCache: NftDetailsColorCache?) {
        self.selectedModel = selectedModel
        self.delegate = delegate
        self.models = models
        self.coverFlowView = _CoverFlowView(
            models: models,
            itemSize: layoutGeometry.carouselItemSize,
            thumbnailDownloader: coverFlowThumbnailDownloader,
            colorCache: colorCache,
            tileCornerRadius: layoutGeometry.carouselTileCornerRadius
        )
        self.preview = NftDetailsItemPreview(layoutGeometry: .init(
            collapsedSize: .init(width: layoutGeometry.carouselItemSize, height: layoutGeometry.carouselItemSize),
            collapsedCornerRadius: layoutGeometry.carouselTileCornerRadius
        ))
        self.layoutGeometry = layoutGeometry
        self.state = State(
            isExpanded: false,
            isHidden: true,
            isFullScreen: false,
            canShowPreview: true
        )
        
        super.init(frame: frame)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        gradientLayer.frame = bounds.copyWith(height: layoutGeometry.fullCollapsedHeight + 60)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        
        if let result {
            if result.isDescendant(of: coverFlowView) {
                return result
            }
        }
        return nil
    }

    private func setup() {
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.3).cgColor,
            UIColor.black.withAlphaComponent(0.0).cgColor
        ]
        gradientLayer.locations = [0, 1]
        layer.addSublayer(gradientLayer)

        coverFlowView.delegate = self
        coverFlowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverFlowView)
        
        preview.setImageHidden(state.isHidden)
        preview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)

        coverFlowTopConstraint = coverFlowView.topAnchor.constraint(equalTo: topAnchor, constant: layoutGeometry.coverFlowTop)
        preview.centerYConstraint = preview.centerYAnchor.constraint(equalTo: topAnchor, constant: layoutGeometry.previewCenterY)
        preview.centerXConstraint = preview.centerXAnchor.constraint(equalTo: centerXAnchor)
        NSLayoutConstraint.activate([
            coverFlowTopConstraint,
            coverFlowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverFlowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            preview.centerXConstraint!,
            preview.centerYConstraint!,
        ])
        
        coverFlowView.selectModel(byId: selectedModel.id)
    }
    
    private func scheduleToBeVisible() {
        
    }
    
    /// Select the model externally (on init() or by the pager). No animation is required here.
    func selectModel(_ model: NftDetailsItemModel) {        
        selectedModel = model
        coverFlowView.selectModel(byId: model.id)
        
        scheduledAction.cancel()
        preview.cancelLottiePlayback()

        let hasLottie = model.item.lottieUrl != nil
        let isLoading = model.processedImageState.isLoading
            
        // Let's schedule Lottie auto-start OR self-appearance from hidden state (to show a spinner)
        if state.isExpanded, hasLottie || isLoading {
            scheduledAction.schedule(after: 0.5) { [weak self] in
                guard let self, self.selectedModel === model, self.state.isExpanded, self.state.canShowPreview else { return }
                
                // We still loading, just appear itself
                let isLoading = self.selectedModel.processedImageState.isLoading
                if isLoading {
                    if self.state.isHidden {
                        self.makePreviewVisible()
                        self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
                    }
                    return
                }
                
                // We have Lottie: start it
                if hasLottie  {
                    if self.state.isHidden  {
                        self.makePreviewVisible()
                        self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
                    }
                    
                    // Have not idea why but this helps prevents flushes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        _ = self.preview.startLottiePlayback()
                    }
                }
            }
        }
    }
    
    func syncCoverFlowWithPager(progress: CGFloat, currentItemId: String) {
        if state.isExpanded {
            coverFlowView.setSelectedTileVisible(true)
        }
        coverFlowView.setCoverFlowProgress(currentItemId: currentItemId, progress: progress)
    }
    
    var isPreviewHidden: Bool { state.isHidden }
    
    func setCanShowPreview(_ newValue: Bool) {
        guard state.canShowPreview != newValue else { return }
        state.canShowPreview = newValue
        if newValue {
            
        } else {
            // Immediately hides preview, cancels all schedules
            scheduledAction.cancel()
            state.isHidden = true
            UIView.performWithoutAnimation {
                preview.setImageHidden(true)
            }
        }
    }
    
    private func setPreviewAndTileHidden(_ isHidden: Bool, updateState: Bool = true) {
        if updateState {
            state.isHidden = isHidden
        }
        preview.setImageHidden(isHidden)
        coverFlowView.setSelectedTileVisible(isHidden)
    }
    
    private func updateGradient() {
        gradientLayer.opacity = state.isExpanded ? 0 : 1
    }

    private func stopExpandCollapseAnimation() {
        previewExpandAnimator?.stopAnimation(true, )
        previewExpandAnimator?.finishAnimation(at: .current)
        previewExpandAnimator = nil
    }
    
    private func stopTransformAnimation() {
        previewTransformAnimator?.stopAnimation(true)
        previewTransformAnimator?.finishAnimation(at: .current)
        previewTransformAnimator = nil
    }

    private func expandCollapse(isExpanded: Bool) {
        let duration = isExpanded ? 0.2 : 0.1
        let lg = layoutGeometry
        let centerYConstraint = preview.centerYConstraint

        stopExpandCollapseAnimation()
        previewExpandAnimator = UIViewPropertyAnimator(duration: duration, curve: .easeOut)
        previewExpandAnimator?.addAnimations {
            self.updateGradient()
            self.coverFlowView.isActive = !isExpanded

            if isExpanded {
                self.preview.prepareToExpandAnimation(expandedWidth: lg.pageWidth)
                centerYConstraint?.constant = lg.pageWidth / 2
            } else {
                self.preview.prepareToCollapseAnimation(expandedWidth: lg.pageWidth)
                centerYConstraint?.constant = lg.previewCenterY
            }
            
            self.layoutIfNeeded()
        }
        previewExpandAnimator?.addCompletion { _ in
            if !isExpanded {
                self.setPreviewAndTileHidden(true)
            } else {
                _ = self.preview.startLottiePlayback()
            }
        }
        previewExpandAnimator?.startAnimation()
        
        preview.runCornerRadiusAnimation(duration: duration, expandedWidth: lg.pageWidth, isExpand: isExpanded)
    }
    
    private func makePreviewVisible() {
        assert(state.isHidden)

        state.isHidden = false
        UIView.performWithoutAnimation {
            preview.selectModel(selectedModel)
            preview.setImageHidden(false)
        }
    }
    
    func handleVerticalScroll(_ scrollView: UIScrollView, isExpanded: Bool) {

        // Very limited processing in the full-screen state
        if state.isFullScreen {
            state.isExpanded = isExpanded
            updateGradient()
            return
        }
        
        
        let offsetY = scrollView.contentOffset.y
        let y1 = isExpanded ? 0.0 : max(0, offsetY)
        coverFlowTopConstraint.constant = layoutGeometry.coverFlowTop - y1
        
        // In expanded state with a non-zero offset
        // We also show loading items, just to show spinnee
        if state.isExpanded, offsetY != 0, state.isHidden {
            state.canShowPreview = true
            makePreviewVisible()
        }
        
        // Expand/Collapse
        if state.isExpanded != isExpanded {
            state.isExpanded = isExpanded
            if state.isExpanded {
                if state.isHidden {
                    makePreviewVisible()
                    coverFlowView.setSelectedTileVisible(false)
                }
            } else {
                UIView.performWithoutAnimation {
                    preview.cancelLottiePlayback()
                }
            }
            expandCollapse(isExpanded: isExpanded)
        }
        
        stopTransformAnimation()
        if let previewExpandAnimator, previewExpandAnimator.state == .active {
            let restTime = (1.0 - previewExpandAnimator.fractionComplete) * previewExpandAnimator.duration
            previewTransformAnimator = UIViewPropertyAnimator(duration: restTime, curve: .easeOut)
            previewTransformAnimator?.addAnimations {
                self.preview.transform = self.getTransform(offsetY: offsetY, isExpanded: isExpanded)
            }
            previewTransformAnimator?.startAnimation()
        } else {
            preview.transform = getTransform(offsetY: offsetY, isExpanded: isExpanded)
        }
    }
    
    private func getTransform(offsetY: CGFloat, isExpanded: Bool) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        if isExpanded {
            let scale = (layoutGeometry.pageWidth - min(0, offsetY)) / layoutGeometry.pageWidth
            transform = transform.translatedBy(x: 0, y: -offsetY / 2).scaledBy(x: scale, y: scale)
        } else {
            transform = transform.translatedBy(x: 0, y: -max(0, offsetY))
        }
        return transform
    }
    
    func dismissFullScreen() -> Bool {
        guard state.isFullScreen, let fullScreenOverlay else { return false }
        return fullScreenOverlay.dismiss()
    }
    
    func openFullScreenPreview() {
        guard fullScreenOverlay == nil, let parentView = superview else { return }
        
        stopExpandCollapseAnimation()
        stopTransformAnimation()
        
        state.isFullScreen = true
        
        if state.isExpanded {
            coverFlowView.setSelectedTileVisible(false)
            UIView.animate(withDuration: 0.3, animations: {
                self.coverFlowView.isActive = true
            })
        } else {
            preview.selectModel(selectedModel)
            setPreviewAndTileHidden(false)
        }
        preview.switchToRealImage(true)

        fullScreenOverlay = NftDetailsFullScreenOverlay(frame: bounds)
        fullScreenOverlay?.presentWithFlyingTransition(from: preview, in: parentView, onPrepare: { [weak self] in
            guard let self else { return }
            if !state.isExpanded {
                self.preview.prepareToExpandAnimation(expandedWidth: layoutGeometry.pageWidth)
                preview.runCornerRadiusAnimation(duration: 0.1, expandedWidth: layoutGeometry.pageWidth, isExpand: true)
            }
        }) { [weak self] way in
            self?.exitFullScreenPreview(way: way)
        }
    }
    
    private func exitFullScreenPreview(way: NftDetailsFullScreenOverlay.DismissWay) {
        assert(state.isFullScreen && !state.isExpanded)
        
        let animationDuration1: TimeInterval
        let animationDuration2: TimeInterval
        
        switch way {
        case .normal, .singleTap, .throwDown:
            animationDuration1 = 0.3
            animationDuration2 = 0.28
        case .throwUp:
            animationDuration1 = 0.25
            animationDuration2 = 0.20
        }
        
        // At this moment we have preview in the full screen overlay. We need to animate it to the collapsed position
        preview.cancelLottiePlayback()
        preview.prepareToCollapseAnimation(expandedWidth: layoutGeometry.pageWidth)
        preview.centerYConstraint?.constant = layoutGeometry.previewCenterY
        UIView.animate(
            withDuration: animationDuration1,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.38,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: {
                self.preview.superview?.layoutIfNeeded()
            },
            completion: { _ in
                self.finalizeExitFullScreenPreviewStep()
            }
        )
        
        preview.runCornerRadiusAnimation(duration: animationDuration2, expandedWidth: layoutGeometry.pageWidth, isExpand: false)
        
        UIView.animate(withDuration: 0.2) {
            self.fullScreenOverlay?.backgroundColor = .clear
        }
    }
    
    private func finalizeExitFullScreenPreviewStep() {
        preview.addToParent(self, bindToTop: true, yConstant: layoutGeometry.previewCenterY)
        state.isFullScreen = false
        preview.switchToRealImage(false)
        setPreviewAndTileHidden(true)
        fullScreenOverlay?.removeFromSuperview()
        fullScreenOverlay = nil
    }
}

extension NftDetailsMainHeaderView: CoverFlowDelegate {    
    func coverFlowDidTapModel(_ model: NftDetailsItemModel, view: UIView,  longTap: Bool) {
        if longTap {
            openFullScreenPreview()
        } else {
            assert(model === selectedModel)
            delegate?.headerCoverFlowDidTapSelectedModel()
        }
    }
        
    func coverFlowDidSelectModel(_ model: NftDetailsItemModel) {
        selectedModel = model
        if !state.isHidden {
            preview.selectModel(model)
        }
        delegate?.headerCoverFlowDidSelectModel(model)
    }
    
    func onCoverFlowScrollProgress(_ progress: CGFloat, currentItemId: String) {
        delegate?.headerCoverFlowDidScroll(withProgress: progress, currentModelId: currentItemId)
    }
}

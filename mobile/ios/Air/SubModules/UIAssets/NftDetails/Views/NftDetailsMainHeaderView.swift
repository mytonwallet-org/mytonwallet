import UIKit
import Kingfisher

protocol NftDetailsMainHeaderViewDelegate: AnyObject {
    func headerCoverFlowDidSelectModel(_ model: NftDetailsItemModel)
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModel: NftDetailsItemModel)
    func headerCoverFlowDidTapSelectedModel()
    func headerDidChangePreviewVisibilityInternaly(_ headerView: NftDetailsMainHeaderView)
}

class NftDetailsMainHeaderView: UIView {
    private weak var delegate: NftDetailsMainHeaderViewDelegate?

    private var coverFlowTopConstraint: NSLayoutConstraint!
    private var previewExpandAnimator: UIViewPropertyAnimator?
    
    private let gradientLayer = CAGradientLayer()
    private let pageWipeMask = CAGradientLayer()
    private let coverFlowContainer = UIView()
    private let coverFlowView: _CoverFlowView
    private let preview: NftDetailsItemPreview
    private var selectedModel: NftDetailsItemModel
    private var models: [NftDetailsItemModel]
    private var fullScreenOverlay: NftDetailsFullScreenOverlay?
    private var inlineZoom: NftDetailsInlineZoom?
    private var navigationImageSamples: [ObjectIdentifier: NftDetailsImageSample] = [:]
    var isInlineZoomActive: Bool { inlineZoom != nil }
    var canBeginInlineZoom: Bool { state.isExpanded && !state.isFullScreen && inlineZoom == nil && state.canShowPreview && selectedModel.processedImageState.isLoaded }
    private var isLottiePlaybackEnabled = false
    weak var overlayParentView: UIView?

    struct LayoutGeometry: Equatable {
        let topSafeAreaInset: CGFloat
        let leadingSafeAreaInset: CGFloat
        let trailingSafeAreaInset: CGFloat
        let collapsedAreaHeight: CGFloat
        let pageWidth: CGFloat
        let expandedImageFrame: CGRect
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
            coverFlowTopConstraint.constant = state.isExpanded
                ? layoutGeometry.expandedImageFrame.midY - layoutGeometry.carouselItemSize / 2
                : layoutGeometry.coverFlowTop
            let scale = state.isExpanded ? layoutGeometry.expandedImageFrame.width / layoutGeometry.carouselItemSize : 1
            coverFlowView.transform = CGAffineTransform(scaleX: scale, y: scale)
            if preview.superview === self, inlineZoom == nil {
                if state.isExpanded {
                    preview.prepareToExpandAnimation(expandedWidth: layoutGeometry.expandedImageFrame.width)
                }
                preview.centerYConstraint?.constant = state.isExpanded ? layoutGeometry.expandedImageFrame.midY : layoutGeometry.previewCenterY
            }
        }
    }
    
    init(frame: CGRect, models: [NftDetailsItemModel], selectedModel: NftDetailsItemModel,
         delegate: NftDetailsMainHeaderViewDelegate, layoutGeometry: LayoutGeometry,
         coverFlowThumbnailDownloader: ImageDownloader, colorResolver: NftDetailsColorResolver) {
        self.selectedModel = selectedModel
        self.delegate = delegate
        self.models = models
        self.coverFlowView = _CoverFlowView(
            models: models,
            itemSize: layoutGeometry.carouselItemSize,
            thumbnailDownloader: coverFlowThumbnailDownloader,
            colorResolver: colorResolver,
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(
            x: -layoutGeometry.leadingSafeAreaInset,
            y: 0,
            width: bounds.width + layoutGeometry.leadingSafeAreaInset + layoutGeometry.trailingSafeAreaInset,
            height: layoutGeometry.fullCollapsedHeight + 60
        )
        CATransaction.commit()
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
        coverFlowContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverFlowContainer)
        coverFlowView.translatesAutoresizingMaskIntoConstraints = false
        coverFlowContainer.addSubview(coverFlowView)
        
        preview.setImageHidden(state.isHidden)
        preview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)

        coverFlowTopConstraint = coverFlowContainer.topAnchor.constraint(equalTo: topAnchor, constant: layoutGeometry.coverFlowTop)
        preview.centerYConstraint = preview.centerYAnchor.constraint(equalTo: topAnchor, constant: layoutGeometry.previewCenterY)
        preview.centerXConstraint = preview.centerXAnchor.constraint(equalTo: centerXAnchor)
        NSLayoutConstraint.activate([
            coverFlowTopConstraint,
            coverFlowContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverFlowContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverFlowView.topAnchor.constraint(equalTo: coverFlowContainer.topAnchor),
            coverFlowView.bottomAnchor.constraint(equalTo: coverFlowContainer.bottomAnchor),
            coverFlowView.leadingAnchor.constraint(equalTo: coverFlowContainer.leadingAnchor),
            coverFlowView.trailingAnchor.constraint(equalTo: coverFlowContainer.trailingAnchor),
            
            preview.centerXConstraint!,
            preview.centerYConstraint!,
        ])
        
        coverFlowView.selectModel(selectedModel)
    }
        
    /// Select the model externally (on init() or by the pager). No animation is required here.
    func selectModel(_ model: NftDetailsItemModel) {
        let didChangeModel = selectedModel !== model
        selectedModel = model
        coverFlowView.selectModel(model)
        
        scheduledAction.cancel()
        if didChangeModel {
            if state.isHidden { preview.setImageHidden(true) }
            else { preview.cancelLottiePlayback() }
        }

        scheduleExpandedPreviewUpdate(for: model)
    }

    func setLottiePlaybackEnabled(_ isEnabled: Bool) {
        guard isLottiePlaybackEnabled != isEnabled else { return }
        isLottiePlaybackEnabled = isEnabled
        coverFlowView.setLottiePlaybackEnabled(isEnabled)

        guard isEnabled else {
            scheduledAction.cancel()
            if state.isHidden { preview.setImageHidden(true) }
            else { preview.cancelLottiePlayback() }
            return
        }

        scheduleExpandedPreviewUpdate(for: selectedModel)
    }

    private func scheduleExpandedPreviewUpdate(for model: NftDetailsItemModel) {
        let hasLottie = model.item.lottieUrl != nil
        let isLoading = model.processedImageState.isLoading
        guard isLottiePlaybackEnabled, state.isExpanded, (hasLottie || isLoading) else { return }

        // Schedule Lottie auto-start or reveal the preview while its static image is loading.
        scheduledAction.schedule(after: 0.5) { [weak self] in
            guard let self, self.isLottiePlaybackEnabled, self.selectedModel === model,
                  self.state.isExpanded, self.state.canShowPreview else { return }

            if self.selectedModel.processedImageState.isLoading {
                if self.state.isHidden {
                    self.makePreviewVisible()
                    self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
                }
                return
            }

            if hasLottie {
                if self.state.isHidden {
                    self.makePreviewVisible()
                    self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
                }

                // Have no idea why but this helps prevents flushes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    guard self.isLottiePlaybackEnabled, self.selectedModel === model,
                          self.state.isExpanded, self.state.canShowPreview, !self.state.isHidden else { return }
                    _ = self.preview.startLottiePlayback()
                }
            }
        }
    }
    
    func removeModel(id: String, newModels: [NftDetailsItemModel], newSelectedModel: NftDetailsItemModel, animated: Bool) {
        self.models = newModels
        coverFlowView.removeModel(id: id, newModels: newModels, newSelectedModel: newSelectedModel, animated: animated)
        selectedModel = newSelectedModel
        if !state.isHidden {
            preview.selectModel(newSelectedModel)
        }
    }

    /// Reconciles the header (and its cover flow) to an arbitrary new model list (insertions,
    /// removals and reorders), then focuses `newSelectedModel`.
    func setModels(_ newModels: [NftDetailsItemModel], newSelectedModel: NftDetailsItemModel, animated: Bool) {
        self.models = newModels
        coverFlowView.setModels(newModels, newSelectedModel: newSelectedModel, animated: animated)
        selectedModel = newSelectedModel
        if !state.isHidden {
            preview.selectModel(newSelectedModel)
        }
    }

    func syncCoverFlowWithPager(progress: CGFloat, currentModel: NftDetailsItemModel) {
        if state.isExpanded {
            coverFlowView.setSelectedTileVisible(true)
        }
        coverFlowView.setCoverFlowProgress(progress: progress, currentModel: currentModel)
    }
    
    var isPreviewHidden: Bool { state.isHidden }

    func navigationBackgroundColor(for model: NftDetailsItemModel, in rectInWindow: CGRect, fallback: UIColor) -> UIColor? {
        guard state.isExpanded || state.isFullScreen || inlineZoom != nil else { return nil }
        var backdrop = fallback
        if let overlay = fullScreenOverlay {
            let color = overlay.layer.presentation()?.backgroundColor ?? overlay.backgroundColor?.cgColor
            if let color {
                let overlayColor = UIColor(cgColor: color)
                backdrop = fallback.nftBlended(with: overlayColor.withAlphaComponent(1), fraction: overlayColor.cgColor.alpha)
            }
        }
        guard case .loaded(let processed) = model.processedImageState, let image = processed.originalImage else { return backdrop }
        let imageFrame: CGRect
        if state.isHidden && !state.isFullScreen {
            imageFrame = convert(layoutGeometry.expandedImageFrame, to: nil)
        } else if let layer = preview.layer.presentation(), let windowLayer = window?.layer.presentation() {
            imageFrame = layer.convert(preview.bounds, to: windowLayer)
        } else {
            imageFrame = preview.convert(preview.bounds, to: nil)
        }
        guard imageFrame.width > 0, imageFrame.height > 0 else { return backdrop }
        let id = ObjectIdentifier(image)
        if navigationImageSamples[id] == nil {
            if navigationImageSamples.count >= 4 { navigationImageSamples.removeAll() }
            navigationImageSamples[id] = NftDetailsImageSample(image: image)
        }
        let rect = CGRect(x: (rectInWindow.minX - imageFrame.minX) / imageFrame.width,
                          y: (rectInWindow.minY - imageFrame.minY) / imageFrame.height,
                          width: rectInWindow.width / imageFrame.width,
                          height: rectInWindow.height / imageFrame.height)
        return navigationImageSamples[id]?.color(in: rect, over: backdrop)
    }
    
    func setCanShowPreview(_ newValue: Bool, staticModel: NftDetailsItemModel?) {
        state.canShowPreview = newValue
        if newValue {
            // A cancelled swipe returns to the existing player, at its current
            // frame. An intermediate boundary belonging to another page must
            // not briefly reveal the outgoing NFT.
            if staticModel === selectedModel, preview.isRenderingPageTransition {
                state.isHidden = false
                preview.setImageHidden(false)
                coverFlowView.setSelectedTileVisible(false)
            }
        } else if !state.isHidden {
            scheduledAction.cancel()
            state.isHidden = true
            if !state.isExpanded || !preview.beginPageTransition() {
                preview.setImageHidden(true)
            }
        }
    }
    
    /// Composite the live selected page over the other page with the same wipe
    /// that Metal uses for static NFTs. Only mask geometry changes during a swipe.
    func updateNativePageTransition(_ transition: NftDetailsPageTransitionState<NftDetailsItemModel>,
                                    color: UIColor) -> NftDetailsItemModel? {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard preview.isRenderingPageTransition, state.isExpanded else {
            if layer.mask === pageWipeMask {
                layer.mask = nil
                backgroundColor = .clear
            }
            return nil
        }
        pageWipeMask.frame = bounds
        layer.mask = pageWipeMask
        backgroundColor = color
        guard case let .transition(left, right, progress) = transition,
              left === selectedModel || right === selectedModel else {
            // Fast multi-page dragging may move past both neighbours of the
            // outgoing NFT before the pager commits its new selected item.
            pageWipeMask.opacity = 0
            return nil
        }
        pageWipeMask.opacity = 1
        NftDetailsPageWipe.configure(pageWipeMask, progress: progress, showingLeft: left === selectedModel,
            isRTL: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        return left === selectedModel ? right : left
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
        if let animator = previewExpandAnimator, animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
        }
        previewExpandAnimator = nil
    }
    

    private func expandCollapse(isExpanded: Bool) {
        let duration = isExpanded ? NftDetailsMediaMotion.duration : NftDetailsMediaMotion.collapseDuration
        let lg = layoutGeometry
        let centerYConstraint = preview.centerYConstraint

        stopExpandCollapseAnimation()
        preview.switchToRealImage(false)
        previewExpandAnimator = UIViewPropertyAnimator(duration: duration, dampingRatio: NftDetailsMediaMotion.damping)
        previewExpandAnimator?.addAnimations {
            self.updateGradient()
            self.coverFlowView.isActive = !isExpanded
            let scale = isExpanded ? lg.expandedImageFrame.width / lg.carouselItemSize : 1
            self.coverFlowView.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.coverFlowTopConstraint.constant = isExpanded
                ? lg.expandedImageFrame.midY - lg.carouselItemSize / 2 : lg.coverFlowTop

            if isExpanded {
                self.preview.prepareToExpandAnimation(expandedWidth: lg.expandedImageFrame.width)
                centerYConstraint?.constant = lg.expandedImageFrame.midY
            } else {
                self.preview.prepareToCollapseAnimation(expandedWidth: lg.expandedImageFrame.width)
                centerYConstraint?.constant = lg.previewCenterY
            }
            
            self.layoutIfNeeded()
        }
        previewExpandAnimator?.addCompletion { position in
            guard position == .end, self.state.isExpanded == isExpanded else { return }
            if !isExpanded {
                self.coverFlowView.restoreSelectedLottieViewer(from: self.preview)
                self.setPreviewAndTileHidden(true)
                self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
            } else if self.isLottiePlaybackEnabled {
                _ = self.preview.startLottiePlayback()
            }
        }
        previewExpandAnimator?.startAnimation()
        
        preview.runCornerRadiusAnimation(duration: duration, expandedWidth: lg.expandedImageFrame.width, isExpand: isExpanded)
    }
    
    private func makePreviewVisible() {
        assert(state.isHidden)

        state.isHidden = false
        UIView.performWithoutAnimation {
            preview.selectModel(selectedModel)
            preview.setImageHidden(false)
            if let viewer = coverFlowView.takeSelectedLottieViewer() {
                preview.adoptLottieViewer(viewer)
            }
            coverFlowView.setSelectedTileVisible(false)
            preview.layoutIfNeeded()
        }
    }
    
    func handleVerticalScroll(_ scrollView: UIScrollView, isExpanded: Bool) {

        guard inlineZoom == nil else { return }
        // Very limited processing in the full-screen state
        if state.isFullScreen {
            state.isExpanded = isExpanded
            updateGradient()
            // Prepare the carousel underneath the overlay before it becomes
            // visible during dismissal, not after the flying image lands.
            UIView.performWithoutAnimation {
                self.updateCoverFlowGeometry()
                self.layoutIfNeeded()
            }
            return
        }
        
        
        let offsetY = scrollView.contentOffset.y
        
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
            }
            expandCollapse(isExpanded: isExpanded)
        }
        
        // Scroll geometry follows the finger in this frame, independently of
        // the expansion animation. Retargeting a spring every tick adds latency.
        UIView.performWithoutAnimation {
            preview.transform = getTransform(offsetY: offsetY, isExpanded: isExpanded)
            coverFlowContainer.transform = preview.transform
        }
    }
    
    private var isAtmosphereReturning = false
    var needsBackgroundAtmosphere: Bool { state.isFullScreen || inlineZoom != nil || isAtmosphereReturning }

    func setAtmosphereHeight(_ height: CGFloat) {
        preview.setAtmosphereHeight(height, pageWidth: layoutGeometry.expandedImageFrame.width)
    }

    private func getTransform(offsetY: CGFloat, isExpanded: Bool) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        if isExpanded {
            let width = layoutGeometry.expandedImageFrame.width
            let scale = (width - min(0, offsetY)) / max(1, width)
            transform = transform.translatedBy(x: 0, y: -offsetY / 2).scaledBy(x: scale, y: scale)
        } else {
            transform = transform.translatedBy(x: 0, y: -max(0, offsetY))
        }
        return transform
    }
    
    func handleInlinePinch(_ gesture: UIPinchGestureRecognizer, onEnd: @escaping () -> Void) {
        switch gesture.state {
        case .began:
            guard canBeginInlineZoom, let parent = overlayParentView ?? superview else { onEnd(); return }
            scheduledAction.cancel()
            stopExpandCollapseAnimation()
            if state.isHidden { makePreviewVisible() }
            preview.switchToRealImage(true)
            preview.clipsToBounds = true
            layoutIfNeeded()
            inlineZoom = NftDetailsInlineZoom(content: preview, source: self, parent: parent, gesture: gesture) { [weak self] in
                guard let self else { onEnd(); return }
                self.isAtmosphereReturning = true
                self.inlineZoom = nil
                self.preview.clipsToBounds = false
                self.preview.switchToRealImage(false, animated: true, duration: 0.22) { [weak self] in
                    guard let self else { return }
                    self.isAtmosphereReturning = false
                    self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
                }
                self.delegate?.headerDidChangePreviewVisibilityInternaly(self)
                self.scheduleExpandedPreviewUpdate(for: self.selectedModel)
                onEnd()
            }
            delegate?.headerDidChangePreviewVisibilityInternaly(self)
            inlineZoom?.update(gesture)
        case .changed:
            inlineZoom?.update(gesture)
        case .ended, .cancelled, .failed:
            inlineZoom?.finish()
        default:
            break
        }
    }

    func dismissFullScreen() -> Bool {
        guard state.isFullScreen, let fullScreenOverlay else { return false }
        return fullScreenOverlay.dismiss()
    }
    
    func openFullScreenPreview() {
        guard fullScreenOverlay == nil, inlineZoom == nil, let parentView = overlayParentView ?? superview else { return }
        
        stopExpandCollapseAnimation()
        
        state.isFullScreen = true
        
        if state.isExpanded {
            coverFlowView.setSelectedTileVisible(false)
            if state.isHidden {
                state.canShowPreview = true
                makePreviewVisible()
            }
        } else {
            if state.isHidden { makePreviewVisible() }
            setPreviewAndTileHidden(false)
        }
        preview.switchToRealImage(true)
        preview.clipsToBounds = true
        delegate?.headerDidChangePreviewVisibilityInternaly(self)

        fullScreenOverlay = NftDetailsFullScreenOverlay(frame: bounds)
        fullScreenOverlay?.presentWithFlyingTransition(from: preview, in: parentView, onPrepare: { [weak self] in
            guard let self else { return }
            self.preview.prepareToExpandAnimation(expandedWidth: layoutGeometry.pageWidth)
            if !state.isExpanded {
                preview.runCornerRadiusAnimation(duration: NftDetailsMediaMotion.duration, expandedWidth: layoutGeometry.pageWidth, isExpand: true)
            }
        }) { [weak self] way in
            self?.exitFullScreenPreview(way: way)
        }
    }
    
    private func exitFullScreenPreview(way: NftDetailsFullScreenOverlay.DismissWay) {
        assert(state.isFullScreen)
        
        let animationDuration1: TimeInterval
        let animationDuration2: TimeInterval
        
        switch way {
        case .normal, .singleTap, .throwDown:
            animationDuration1 = NftDetailsMediaMotion.duration
            animationDuration2 = 0.28
        case .throwUp:
            animationDuration1 = NftDetailsMediaMotion.duration
            animationDuration2 = 0.20
        }
        
        guard let overlay = fullScreenOverlay else { return }
        UIView.performWithoutAnimation {
            self.updateCoverFlowGeometry()
            self.layoutIfNeeded()
        }
        
        preview.switchToRealImage(true)
        let targetY = state.isExpanded ? layoutGeometry.expandedImageFrame.midY : layoutGeometry.previewCenterY
        if state.isExpanded {
            preview.prepareToExpandAnimation(expandedWidth: layoutGeometry.expandedImageFrame.width)
        } else {
            preview.prepareToCollapseAnimation(expandedWidth: layoutGeometry.expandedImageFrame.width)
        }
        let targetCenter = convert(
            CGPoint(x: bounds.midX, y: targetY),
            to: overlay
        )
        preview.centerYConstraint?.constant = targetCenter.y
        preview.centerXConstraint?.constant = targetCenter.x - overlay.bounds.midX
        UIView.animate(
            withDuration: animationDuration1,
            delay: 0,
            usingSpringWithDamping: NftDetailsMediaMotion.damping,
            initialSpringVelocity: 0.38,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: {
                self.preview.transform = .identity
                overlay.layoutIfNeeded()
            },
            completion: { _ in
                self.finalizeExitFullScreenPreviewStep()
            }
        )
        
        preview.runCornerRadiusAnimation(duration: animationDuration2, expandedWidth: layoutGeometry.expandedImageFrame.width, isExpand: state.isExpanded)
        
        UIView.animate(withDuration: 0.2) {
            self.fullScreenOverlay?.backgroundColor = .clear
        }
    }
    
    private func finalizeExitFullScreenPreviewStep() {
        // The window may have resized again while the dismissal was animating.
        if state.isExpanded {
            preview.prepareToExpandAnimation(expandedWidth: layoutGeometry.expandedImageFrame.width)
        } else {
            preview.prepareToCollapseAnimation(expandedWidth: layoutGeometry.expandedImageFrame.width)
        }
        preview.addToParent(self, bindToTop: true,
                            yConstant: state.isExpanded ? layoutGeometry.expandedImageFrame.midY : layoutGeometry.previewCenterY)
        state.isFullScreen = false
        preview.clipsToBounds = false
        preview.switchToRealImage(!state.isExpanded, animated: state.isExpanded, duration: 0.22)
        updateCoverFlowGeometry()
        if !state.isExpanded { coverFlowView.restoreSelectedLottieViewer(from: preview) }
        setPreviewAndTileHidden(!state.isExpanded)
        delegate?.headerDidChangePreviewVisibilityInternaly(self)
        fullScreenOverlay?.removeFromSuperview()
        fullScreenOverlay = nil
    }

    private func updateCoverFlowGeometry() {
        let scale = state.isExpanded ? layoutGeometry.expandedImageFrame.width / layoutGeometry.carouselItemSize : 1
        coverFlowView.transform = CGAffineTransform(scaleX: scale, y: scale)
        coverFlowTopConstraint.constant = state.isExpanded
            ? layoutGeometry.expandedImageFrame.midY - layoutGeometry.carouselItemSize / 2 : layoutGeometry.coverFlowTop
        coverFlowContainer.transform = .identity
        coverFlowView.isActive = !state.isExpanded
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
    
    func onCoverFlowScrollProgress(_ progress: CGFloat, currentModel: NftDetailsItemModel) {
        delegate?.headerCoverFlowDidScroll(withProgress: progress, currentModel: currentModel)
    }
}

import UIKit
import WalletContext
import UIComponents

protocol NftDetailsFullScreenOverlayContent: UIView {
    var centerYConstraint: NSLayoutConstraint? { get set }
    var centerXConstraint: NSLayoutConstraint? { get set }
}

extension NftDetailsFullScreenOverlayContent {
    private func removeCenterConstraints() {
        var oldConstraints: [NSLayoutConstraint] = []
        if let oldCenterXConstraint = centerXConstraint {
            oldConstraints.append(oldCenterXConstraint)
        }
        if let oldCenterYConstraint = centerYConstraint {
            oldConstraints.append(oldCenterYConstraint)
        }
        NSLayoutConstraint.deactivate(oldConstraints)
        
        self.centerXConstraint = nil
        self.centerYConstraint = nil
    }
    
    func addToParent(_ parent: UIView, bindToTop: Bool, yConstant: CGFloat, xConstant: CGFloat = 0) {
        removeCenterConstraints()
        
        parent.addSubview(self)
        
        centerXConstraint = centerXAnchor.constraint(equalTo: parent.centerXAnchor, constant: xConstant)
        if bindToTop {
            centerYConstraint = centerYAnchor.constraint(equalTo: parent.topAnchor, constant: yConstant )
        } else {
            centerYConstraint = centerYAnchor.constraint(equalTo: parent.centerYAnchor, constant: yConstant )
        }
        NSLayoutConstraint.activate([centerXConstraint!, centerYConstraint!])
    }
}


class NftDetailsFullScreenOverlay: UIView {
    
    private let doubleTapZoomScale: CGFloat = 3.0

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 4.0
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.bouncesZoom = true
        sv.bounces = false
        sv.alwaysBounceVertical = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.clipsToBounds = false
        if #available(iOS 26.0, *) {
            sv.topEdgeEffect.isHidden = true
        }
        return sv
    }()
    
    private let contentContainerView = UIView()
    private var contentContainerWidthConstraint: NSLayoutConstraint!
    private var contentContainerHeightConstraint: NSLayoutConstraint!
    private weak var content: NftDetailsFullScreenOverlayContent?
    private var dismissPanGesture: UIPanGestureRecognizer?
    private let pinchTouchGuard = NftDetailsPinchTouchGuard()
    private var onDismiss: ((DismissWay) -> Void)?

    private enum State {
        case idle, presenting, normal, dismissing
    }
    
    private var state = State.idle
    

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateContainerSize()
        scrollView.layoutIfNeeded()
        centerContent()
        if state == .idle || state == .presenting {
            scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        }
    }

    private func updateContainerSize() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
                                                
        // Content is always square (matches NFT image aspect ratio expectations)
        let fittedSize = scrollView.bounds.width
        guard contentContainerWidthConstraint.constant != fittedSize else { return }
        contentContainerWidthConstraint.constant = fittedSize
        contentContainerHeightConstraint.constant = fittedSize
    }
    
    private func updateBackground() {
        if scrollView.zoomScale == 1.0 {
            let start = CGFloat(0)
            let end = max(CGFloat(180), bounds.height * 0.25)
            let offset = max(start, min(end, abs(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)))
            backgroundColor = UIColor.black.withAlphaComponent(1 - (offset - start) / (end - start))
        } else {
            backgroundColor = UIColor.black
        }
    }

    private func centerContent() {
        let scrollSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let hInset = max((scrollSize.width - contentSize.width) / 2, 0)
        let vInset = max((scrollSize.height - contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: vInset, left: hInset, bottom: vInset, right: hInset)
    }

    private func setup() {
        accessibilityIdentifier = "NFTMediaViewer"
        accessibilityViewIsModal = true
        semanticContentAttribute = .forceLeftToRight
        scrollView.semanticContentAttribute = .forceLeftToRight
        contentContainerView.semanticContentAttribute = .forceLeftToRight

        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentContainerView)

        contentContainerWidthConstraint = contentContainerView.widthAnchor.constraint(equalToConstant: bounds.width)
        contentContainerHeightConstraint = contentContainerView.heightAnchor.constraint(equalToConstant: bounds.width)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentContainerWidthConstraint,
            contentContainerHeightConstraint,
        ])

        // Double-tap on content toggles zoom: resets to 1× if zoomed, zooms in if at 1
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap on background dismisses when at base zoom.
        // Single tap must wait for double-tap to fail so they don't conflict.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        tap.require(toFail: doubleTap)

        
        let dismissPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPanGesture.delegate = self
        dismissPanGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(dismissPanGesture)
        self.dismissPanGesture = dismissPanGesture
        pinchTouchGuard.canClaim = { [weak self] in self?.state == .normal }
        pinchTouchGuard.onClaimChanged = { [weak self, weak tap, weak doubleTap, weak dismissPanGesture] claimed in
            tap?.isEnabled = !claimed
            doubleTap?.isEnabled = !claimed
            dismissPanGesture?.isEnabled = !claimed
            if claimed {
                self?.scrollView.transform = .identity
                self?.backgroundColor = .black
            }
        }
        addGestureRecognizer(pinchTouchGuard)
    }
    
    func presentWithFlyingTransition(from content: NftDetailsFullScreenOverlayContent, in parentView: UIView,
                                     onPrepare: () -> Void, onDismiss: @escaping (DismissWay) -> Void) {
        guard state == .idle, superview == nil else {
            assertionFailure()
            return
        }

        self.onDismiss = onDismiss
        self.content = content
        state = .presenting
        backgroundColor = .clear

        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            leftAnchor.constraint(equalTo: parentView.leftAnchor),
            rightAnchor.constraint(equalTo: parentView.rightAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
        ])
        parentView.layoutIfNeeded()
                        
        let startFrame = content.convert(content.bounds, to: self)
        content.transform = .identity
        content.addToParent(contentContainerView, bindToTop: false, yConstant: 0)
        onPrepare()
        layoutIfNeeded()
        centerContent()
        layoutIfNeeded()
        let endFrame = content.convert(content.bounds, to: self)
        content.transform = CGAffineTransform(
            a: startFrame.width / max(1, endFrame.width), b: 0, c: 0,
            d: startFrame.height / max(1, endFrame.height),
            tx: startFrame.midX - endFrame.midX, ty: startFrame.midY - endFrame.midY
        )
        Haptics.play(.transition)
        UIView.animate(withDuration: NftDetailsMediaMotion.duration * 0.75, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { self.backgroundColor = .black }
        UIView.animate(withDuration: NftDetailsMediaMotion.duration, delay: 0,
                       usingSpringWithDamping: NftDetailsMediaMotion.damping, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            content.transform = .identity
        } completion: { _ in
            self.state = .normal
        }
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard !pinchTouchGuard.isClaimed else { return }
        if scrollView.zoomScale == 1.0 {
            dismiss(.singleTap)
        }
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        guard !pinchTouchGuard.isClaimed else { return }
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gr.location(in: contentContainerView)
            let zoomRect = zoomRect(for: doubleTapZoomScale, centeredAt: point)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    private func zoomRect(for scale: CGFloat, centeredAt point: CGPoint) -> CGRect {
        let w = scrollView.bounds.width / scale
        let h = scrollView.bounds.height / scale
        return CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
    }

    @objc private func handleDismissPan(_ gr: UIPanGestureRecognizer) {
        guard !pinchTouchGuard.isClaimed, state == .normal,
              scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001 else { return }
        let translation = gr.translation(in: self)
        switch gr.state {
        case .began, .changed:
            // Follow the finger directly, without UIScrollView's overscroll resistance.
            let progress = min(1, abs(translation.y) / max(1, bounds.height * 0.5))
            let scale = UIAccessibility.isReduceMotionEnabled ? 1 : 1 - progress * 0.08
            scrollView.transform = CGAffineTransform(translationX: translation.x * 0.25, y: translation.y).scaledBy(x: scale, y: scale)
            backgroundColor = UIColor.black.withAlphaComponent(max(0, 1 - abs(translation.y) / 200))
        case .ended, .cancelled:
            let velocity = gr.velocity(in: self)
            if gr.state == .ended,
               abs(translation.y) > bounds.height * 0.2 || (abs(velocity.y) > 800 && abs(translation.y) > 12) {
                dismiss(velocity.y < 0 ? .throwUp : .throwDown)
            } else {
                UIView.animate(withDuration: NftDetailsMediaMotion.duration, delay: 0,
                               usingSpringWithDamping: NftDetailsMediaMotion.damping, initialSpringVelocity: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.scrollView.transform = .identity
                    self.backgroundColor = .black
                }
            }
        default:
            break
        }
    }

    enum DismissWay {
        case normal, throwUp, throwDown, singleTap
    }

    @discardableResult
    func dismiss(_ way: DismissWay = .normal) -> Bool {
        guard state == .normal, let content else { return false }
        state = .dismissing
        
        Haptics.play(.transition)
        
        let currentFrame = content.convert(content.bounds, to: self)
        let scale = currentFrame.width / max(1, content.bounds.width)
        content.addToParent(self, bindToTop: true, yConstant: currentFrame.midY,
                            xConstant: currentFrame.midX - bounds.midX)
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
        layoutIfNeeded()

        onDismiss?(way)
        return true
    }
}

extension NftDetailsFullScreenOverlay: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGesture, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return !pinchTouchGuard.isClaimed && state == .normal && scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001
            && abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === dismissPanGesture
            && (otherGestureRecognizer === scrollView.panGestureRecognizer
                || otherGestureRecognizer === scrollView.pinchGestureRecognizer)
    }
}

extension NftDetailsFullScreenOverlay: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentContainerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        if state == .normal { backgroundColor = .black }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if state == .normal, dismissPanGesture?.state != .changed, dismissPanGesture?.state != .began {
            updateBackground()
        }
    }
}

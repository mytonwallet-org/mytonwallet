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
    /// Content is always square (matches NFT image aspect ratio expectations)
    private let scrollView = MediaZoomView(frame: .zero)
    private var contentContainerView: UIView { scrollView.contentContainerView }
    private weak var content: NftDetailsFullScreenOverlayContent?
    private var dismissPanGesture: UIPanGestureRecognizer?
    private let pinchTouchGuard = PinchTouchGuard()
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
        scrollView.updateContentSize()
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
        scrollView.centerContent()
    }

    private func setup() {
        accessibilityIdentifier = "NFTMediaViewer"
        accessibilityViewIsModal = true
        semanticContentAttribute = .forceLeftToRight
        scrollView.semanticContentAttribute = .forceLeftToRight
        contentContainerView.semanticContentAttribute = .forceLeftToRight

        scrollView.onZoom = { [weak self] in
            guard let self, self.state == .normal else { return }
            self.backgroundColor = .black
        }
        scrollView.onScroll = { [weak self] in
            guard let self, self.state == .normal,
                  self.dismissPanGesture?.state != .changed, self.dismissPanGesture?.state != .began else { return }
            self.updateBackground()
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        UIView.animate(withDuration: MediaViewerMotion.duration * 0.75, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { self.backgroundColor = .black }
        UIView.animate(withDuration: MediaViewerMotion.duration, delay: 0,
                       usingSpringWithDamping: MediaViewerMotion.damping, initialSpringVelocity: 0,
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
        scrollView.toggleZoom(at: gr.location(in: contentContainerView))
    }

    @objc private func handleDismissPan(_ gr: UIPanGestureRecognizer) {
        guard !pinchTouchGuard.isClaimed, state == .normal, scrollView.isAtMinimumZoom else { return }
        let translation = gr.translation(in: self)
        switch gr.state {
        case .began, .changed:
            // Follow the finger directly, without UIScrollView's overscroll resistance.
            scrollView.transform = MediaViewerMotion.getDismissTransform(for: translation, in: bounds)
            backgroundColor = UIColor.black.withAlphaComponent(MediaViewerMotion.getBackdropAlpha(for: translation))
        case .ended, .cancelled:
            let velocity = gr.velocity(in: self)
            if gr.state == .ended, MediaViewerMotion.shouldDismiss(translation: translation, velocity: velocity, in: bounds) {
                dismiss(velocity.y < 0 ? .throwUp : .throwDown)
            } else {
                UIView.animate(withDuration: MediaViewerMotion.duration, delay: 0,
                               usingSpringWithDamping: MediaViewerMotion.damping, initialSpringVelocity: 0,
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
        return !pinchTouchGuard.isClaimed && state == .normal && scrollView.isAtMinimumZoom
            && abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === dismissPanGesture
            && (otherGestureRecognizer === scrollView.panGestureRecognizer
                || otherGestureRecognizer === scrollView.pinchGestureRecognizer)
    }
}

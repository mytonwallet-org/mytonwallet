import UIKit

/// Telegram's pinch to zoom on an inline image, with the anchoring of the NFT viewer.
///
/// Pinching lifts a copy of the image above the whole window: it scales from 1x to 10x around the point between
/// the fingers, follows them as they move, dims everything behind it, and springs back into place on release.
/// A second recognizer claims two-finger touches at once, so an enclosing list never scrolls under the pinch.
@MainActor
public final class ImagePinchZoom: NSObject, UIGestureRecognizerDelegate {
    private static let maximumScale: CGFloat = 10
    private static let dimmingAlpha: CGFloat = 0.5

    private weak var imageView: UIImageView?
    /// How the image's container rounds it, so the lifted copy starts with the same corners and loses them as it grows
    public var cornerRadius: CGFloat
    public var maskedCorners: CACornerMask
    private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private let touchGuard = PinchTouchGuard()
    private var session: Session?

    @MainActor
    private final class Session {
        let overlay = UIView()
        let dimmingView = UIView()
        let copy = UIImageView()
        let sourceCenter: CGPoint
        let anchor: CGPoint
        var lastLocation: CGPoint
        var translation = CGPoint.zero
        var touchCount: Int

        init(sourceCenter: CGPoint, anchor: CGPoint, touchCount: Int) {
            self.sourceCenter = sourceCenter
            self.anchor = anchor
            self.lastLocation = anchor
            self.touchCount = touchCount
        }
    }

    /// `cornerRadius` and `maskedCorners` describe how the image's container rounds it, so the lifted copy starts
    /// with the same corners and loses them as it grows
    public init(imageView: UIImageView, cornerRadius: CGFloat = 0, maskedCorners: CACornerMask = [
        .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
    ]) {
        self.imageView = imageView
        self.cornerRadius = cornerRadius
        self.maskedCorners = maskedCorners
        super.init()
        imageView.isUserInteractionEnabled = true
        pinchGesture.delegate = self
        imageView.addGestureRecognizer(pinchGesture)
        touchGuard.canClaim = { [weak self] in self?.imageView?.image != nil }
        touchGuard.onClaimChanged = { [weak self] isClaimed in self?.setScrollingSuspended(isClaimed) }
        imageView.addGestureRecognizer(touchGuard)
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer === touchGuard
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        imageView?.image != nil && imageView?.window != nil
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            begin(gesture)
        case .changed:
            update(gesture)
        case .ended, .cancelled, .failed:
            finish()
        default:
            break
        }
    }

    private func begin(_ gesture: UIPinchGestureRecognizer) {
        guard session == nil, let imageView, let window = imageView.window else { return }
        let frame = imageView.convert(imageView.bounds, to: window)
        let session = Session(
            sourceCenter: CGPoint(x: frame.midX, y: frame.midY),
            anchor: gesture.location(in: window),
            touchCount: gesture.numberOfTouches
        )
        session.overlay.frame = window.bounds
        session.overlay.isUserInteractionEnabled = false
        session.dimmingView.frame = window.bounds
        session.dimmingView.backgroundColor = .black
        session.dimmingView.alpha = 0
        session.overlay.addSubview(session.dimmingView)
        session.copy.image = imageView.image
        session.copy.contentMode = imageView.contentMode
        session.copy.clipsToBounds = true
        session.copy.backgroundColor = imageView.backgroundColor
        session.copy.layer.cornerRadius = cornerRadius
        session.copy.layer.maskedCorners = maskedCorners
        session.copy.layer.cornerCurve = .continuous
        session.copy.bounds = CGRect(origin: .zero, size: frame.size)
        session.copy.center = session.sourceCenter
        session.overlay.addSubview(session.copy)
        window.addSubview(session.overlay)
        imageView.alpha = 0
        self.session = session
        if !touchGuard.isClaimed { setScrollingSuspended(true) }
    }

    private func update(_ gesture: UIPinchGestureRecognizer) {
        guard let session, let window = session.overlay.window else { return }
        let location = gesture.location(in: window)
        // Lifting one finger changes the centroid without moving the image
        if gesture.numberOfTouches == session.touchCount {
            session.translation.x += location.x - session.lastLocation.x
            session.translation.y += location.y - session.lastLocation.y
        }
        session.lastLocation = location
        session.touchCount = gesture.numberOfTouches
        let zoom = min(Self.maximumScale, max(1, gesture.scale))
        session.copy.transform = CGAffineTransform(
            a: zoom, b: 0, c: 0, d: zoom,
            tx: (session.sourceCenter.x - session.anchor.x) * (zoom - 1) + session.translation.x,
            ty: (session.sourceCenter.y - session.anchor.y) * (zoom - 1) + session.translation.y
        )
        let progress = min(1, zoom - 1)
        session.dimmingView.alpha = Self.dimmingAlpha * progress
        session.copy.layer.cornerRadius = cornerRadius * (1 - progress)
    }

    private func finish() {
        guard let session else { return }
        self.session = nil
        let timing = UISpringTimingParameters(dampingRatio: 1)
        let animator = UIViewPropertyAnimator(
            duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.36,
            timingParameters: timing
        )
        animator.addAnimations {
            session.copy.transform = .identity
            session.copy.layer.cornerRadius = self.cornerRadius
            session.dimmingView.alpha = 0
        }
        animator.addCompletion { [weak self] _ in
            self?.imageView?.alpha = 1
            session.overlay.removeFromSuperview()
            if self?.touchGuard.isClaimed != true { self?.setScrollingSuspended(false) }
        }
        animator.startAnimation()
    }

    /// Keeps enclosing lists still for the whole two-finger sequence. It turns off their pan rather than their
    /// scrolling: a scroll view that can't scroll leaves the safe area out of its insets, which moves a list resting at
    /// its end by the home indicator's height.
    private func setScrollingSuspended(_ isSuspended: Bool) {
        guard let imageView else { return }
        if isSuspended {
            guard suspendedScrollViews.isEmpty else { return }
            var scrollViews: [UIScrollView] = []
            var ancestor = imageView.superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView, scrollView.isScrollEnabled,
                   scrollView.panGestureRecognizer.isEnabled {
                    scrollView.panGestureRecognizer.isEnabled = false
                    scrollViews.append(scrollView)
                }
                ancestor = view.superview
            }
            suspendedScrollViews = scrollViews
        } else {
            suspendedScrollViews.forEach { $0.panGestureRecognizer.isEnabled = true }
            suspendedScrollViews = []
        }
    }

    private var suspendedScrollViews: [UIScrollView] = []
}

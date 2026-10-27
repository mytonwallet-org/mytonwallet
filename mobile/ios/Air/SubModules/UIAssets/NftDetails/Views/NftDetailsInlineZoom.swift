import UIKit

/// Claims the entire two-finger sequence before UIPinchGestureRecognizer reaches
/// its scale threshold. It remains active when one finger lifts, until both are up.
/// Observation never prevents the system pinch or delays one-finger scrolling.
final class NftDetailsPinchTouchGuard: UIGestureRecognizer {
    var canClaim: () -> Bool = { false }
    var onClaimChanged: (Bool) -> Void = { _ in }
    private(set) var isClaimed = false
    private var trackedTouches = Set<UITouch>()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches.formUnion(touches)
        updateTouchCount(trackedTouches.count)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if isClaimed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches.subtract(touches)
        updateTouchCount(trackedTouches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches.subtract(touches)
        updateTouchCount(trackedTouches.count)
    }

    func updateTouchCount(_ count: Int) {
        if !isClaimed, count >= 2, canClaim() {
            isClaimed = true
            onClaimChanged(true)
            state = .began
        } else if count == 0 {
            // Release in reset, after all recognizers handle the final touch-up.
            state = isClaimed ? .ended : .failed
        }
    }

    override func reset() {
        super.reset()
        trackedTouches.removeAll()
        if isClaimed {
            isClaimed = false
            onClaimChanged(false)
        }
    }
}

/// UIKit adaptation of Telegram's media gestures: preserve the pinch anchor, track
/// the finger centroid, and spring back to the source when the gesture ends.
enum NftDetailsMediaMotion {
    static var duration: TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.32 }
    static var collapseDuration: TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.28 }
    static let damping: CGFloat = 0.94
}

@MainActor
final class NftDetailsInlineZoom {
    private let overlay = UIView()
    private let dimmingView = UIView()
    private let content: NftDetailsFullScreenOverlayContent
    private let source: UIView
    private let sourceY: CGFloat
    private let sourceX: CGFloat
    private let sourceTransform: CGAffineTransform
    private let sourceCenter: CGPoint
    private let sourceScale: CGFloat
    private let anchor: CGPoint
    private var lastLocation: CGPoint
    private var translation = CGPoint.zero
    private var touchCount: Int
    private var isFinishing = false
    private let completion: () -> Void

    init(content: NftDetailsFullScreenOverlayContent, source: UIView, parent: UIView,
         gesture: UIPinchGestureRecognizer, completion: @escaping () -> Void) {
        self.content = content
        self.source = source
        self.completion = completion
        sourceY = content.centerYConstraint?.constant ?? 0
        sourceX = content.centerXConstraint?.constant ?? 0
        sourceTransform = content.transform
        let frame = content.convert(content.bounds, to: parent)
        sourceCenter = CGPoint(x: frame.midX, y: frame.midY)
        sourceScale = frame.width / max(1, content.bounds.width)
        anchor = gesture.location(in: parent)
        lastLocation = anchor
        touchCount = gesture.numberOfTouches

        overlay.frame = parent.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        parent.addSubview(overlay)
        dimmingView.frame = overlay.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0
        overlay.addSubview(dimmingView)
        content.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)
        content.addToParent(overlay, bindToTop: true, yConstant: sourceCenter.y,
                            xConstant: sourceCenter.x - overlay.bounds.midX)
        overlay.layoutIfNeeded()
    }

    func update(_ gesture: UIPinchGestureRecognizer) {
        guard !isFinishing else { return }
        let location = gesture.location(in: overlay)
        if gesture.numberOfTouches == touchCount {
            translation.x += location.x - lastLocation.x
            translation.y += location.y - lastLocation.y
        }
        lastLocation = location
        touchCount = gesture.numberOfTouches
        let zoom = min(6, max(1, gesture.scale))
        content.transform = CGAffineTransform(
            a: sourceScale * zoom, b: 0, c: 0, d: sourceScale * zoom,
            tx: (sourceCenter.x - anchor.x) * (zoom - 1) + translation.x,
            ty: (sourceCenter.y - anchor.y) * (zoom - 1) + translation.y
        )
        dimmingView.alpha = min(0.65, (zoom - 1) * 0.35)
    }

    func finish(animated: Bool = true) {
        guard !isFinishing else { return }
        isFinishing = true
        UIView.animate(withDuration: animated ? NftDetailsMediaMotion.duration : 0,
                       delay: 0, usingSpringWithDamping: NftDetailsMediaMotion.damping,
                       initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.content.transform = CGAffineTransform(scaleX: self.sourceScale, y: self.sourceScale)
            self.dimmingView.alpha = 0
        } completion: { _ in
            self.content.addToParent(self.source, bindToTop: true, yConstant: self.sourceY, xConstant: self.sourceX)
            self.content.transform = self.sourceTransform
            self.source.layoutIfNeeded()
            self.overlay.removeFromSuperview()
            self.completion()
        }
    }
}

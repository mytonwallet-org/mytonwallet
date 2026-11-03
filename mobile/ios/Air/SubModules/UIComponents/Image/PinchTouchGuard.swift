import UIKit

/// Claims the whole two-finger sequence before `UIPinchGestureRecognizer` reaches its scale threshold, and stays
/// claimed when one finger lifts, until both are up. Observing never prevents the system pinch or delays one-finger
/// scrolling.
public final class PinchTouchGuard: UIGestureRecognizer {
    public var canClaim: () -> Bool = { false }
    public var onClaimChanged: (Bool) -> Void = { _ in }
    public private(set) var isClaimed = false
    private var trackedTouches = Set<UITouch>()

    public init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches.formUnion(touches)
        updateTouchCount(trackedTouches.count)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if isClaimed { state = .changed }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches.subtract(touches)
        updateTouchCount(trackedTouches.count)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches.subtract(touches)
        updateTouchCount(trackedTouches.count)
    }

    public func updateTouchCount(_ count: Int) {
        if !isClaimed, count >= 2, canClaim() {
            isClaimed = true
            onClaimChanged(true)
            state = .began
        } else if count == 0 {
            // Released in `reset`, after all recognizers handle the final touch-up
            state = isClaimed ? .ended : .failed
        }
    }

    public override func reset() {
        super.reset()
        trackedTouches.removeAll()
        if isClaimed {
            isClaimed = false
            onClaimChanged(false)
        }
    }
}

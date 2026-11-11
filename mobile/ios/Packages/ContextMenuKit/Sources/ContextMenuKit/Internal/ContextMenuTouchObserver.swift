import UIKit

/// Tells when fingers come down on its view and when the last one lets go, without recognizing anything, so that it
/// never takes the touches from the view's controls or other recognizers
@MainActor
final class ContextMenuTouchObserver: UIGestureRecognizer {
    private let onChange: @MainActor (_ isTouching: Bool) -> Void
    private var touchCount = 0

    init(onChange: @escaping @MainActor (_ isTouching: Bool) -> Void) {
        self.onChange = onChange
        super.init(target: nil, action: nil)
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if self.touchCount == 0 {
            self.onChange(true)
        }
        self.touchCount += touches.count
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        self.release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        self.release(touches)
    }

    override func reset() {
        super.reset()
        if self.touchCount > 0 {
            self.touchCount = 0
            self.onChange(false)
        }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func release(_ touches: Set<UITouch>) {
        self.touchCount = max(0, self.touchCount - touches.count)
        guard self.touchCount == 0 else {
            return
        }
        self.onChange(false)
        // Failing ends the recognizer's turn without taking anything from the others
        self.state = .failed
    }
}

import UIKit

struct ContextMenuInteractivePanDirections: OptionSet {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let right = ContextMenuInteractivePanDirections(rawValue: 1 << 0)
    static let left = ContextMenuInteractivePanDirections(rawValue: 1 << 1)
}

final class ContextMenuInteractivePanGestureRecognizer: UIPanGestureRecognizer {
    private let allowedDirections: (CGPoint) -> ContextMenuInteractivePanDirections

    private var validatedGesture = false
    private var firstLocation: CGPoint = .zero
    private var currentAllowedDirections: ContextMenuInteractivePanDirections = []

    init(target: Any?, action: Selector?, allowedDirections: @escaping (CGPoint) -> ContextMenuInteractivePanDirections) {
        self.allowedDirections = allowedDirections
        super.init(target: target, action: action)

        self.maximumNumberOfTouches = 1
        self.delaysTouchesBegan = false
    }

    override func reset() {
        super.reset()
        self.validatedGesture = false
        self.currentAllowedDirections = []
        self.firstLocation = .zero
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view = self.view else {
            self.state = .failed
            return
        }

        let point = touch.location(in: view)
        let allowedDirections = self.allowedDirections(point)
        if allowedDirections.isEmpty {
            self.state = .failed
            return
        }

        super.touchesBegan(touches, with: event)
        self.firstLocation = point
        self.currentAllowedDirections = allowedDirections
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else {
            self.state = .failed
            return
        }

        let location = touch.location(in: self.view)
        let translation = CGPoint(x: location.x - self.firstLocation.x, y: location.y - self.firstLocation.y)
        let absTranslationX = abs(translation.x)
        let absTranslationY = abs(translation.y)

        var fireBegan = false

        if !self.validatedGesture {
            if !self.currentAllowedDirections.contains(.left), translation.x < 0.0 {
                self.state = .failed
                return
            } else if !self.currentAllowedDirections.contains(.right), translation.x > 0.0 {
                self.state = .failed
                return
            }

            let totalMovement = sqrt(absTranslationX * absTranslationX + absTranslationY * absTranslationY)
            if totalMovement > 10.0 {
                if absTranslationX >= absTranslationY {
                    self.validatedGesture = true
                    fireBegan = true
                } else {
                    self.state = .failed
                    return
                }
            } else if absTranslationY > 2.0 && absTranslationY > absTranslationX * 2.0 {
                self.state = .failed
                return
            } else if absTranslationX > 2.0 && absTranslationX > absTranslationY * 2.0 {
                self.validatedGesture = true
                fireBegan = true
            }
        }

        if self.validatedGesture {
            super.touchesMoved(touches, with: event)
            if fireBegan, self.state == .possible {
                self.state = .began
            }
        }
    }
}

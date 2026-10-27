import UIKit
import WalletCore
import WalletContext

// Gesture-backed taps let the ancestor scroll views cancel a drag across the card.
public class MtwCardTapView: UIView {
    public var onTap: (() -> Void)?
    public private(set) var lastTapLocation: CGPoint?

    public override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) { activate(at: gesture.location(in: self)) }

    public func activate(at point: CGPoint) {
        lastTapLocation = point
        onTap?()
    }

    public override func accessibilityActivate() -> Bool {
        guard onTap != nil else { return false }
        activate(at: CGPoint(x: bounds.midX, y: bounds.midY))
        return true
    }
}

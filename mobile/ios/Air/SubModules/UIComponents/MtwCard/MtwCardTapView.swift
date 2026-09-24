import UIKit

// Gesture-backed taps let the ancestor scroll views cancel a drag across the card.
public class MtwCardTapView: UIView {
    public var onTap: (() -> Void)?

    public override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onTap?() }

    public override func accessibilityActivate() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }
}

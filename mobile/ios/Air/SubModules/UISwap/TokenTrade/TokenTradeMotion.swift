import UIKit
import UIComponents

@MainActor enum TokenTradeMotion {
    static let duration: TimeInterval = 0.32

    static var enabled: Bool {
        let environment = CardBackgroundAnimationEnvironment.shared
        return environment.animationsEnabled && environment.applicationActive
            && !environment.lowPowerMode && !environment.reduceMotion
    }

    static func animate(_ animated: Bool, changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        if animated && enabled {
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                           animations: changes, completion: completion)
        } else {
            UIView.performWithoutAnimation(changes)
            completion?(true)
        }
    }

    static func place(_ view: UIView, in frame: CGRect) {
        // A scroll view stores its content offset in bounds.origin.
        let bounds = CGRect(origin: view.bounds.origin, size: frame.size)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if view.bounds.isEmpty, !bounds.isEmpty {
            // Newly visible content enters at its destination, never from a zero-sized frame.
            UIView.performWithoutAnimation {
                view.bounds = bounds
                view.center = center
                view.layoutIfNeeded()
            }
            return
        }
        if view.bounds != bounds { view.bounds = bounds }
        if view.center != center { view.center = center }
    }
}

/// Retains both sides of a visibility change until their layer animations finish.
final class TokenTradePresenceView: UIView {
    let content = WBlurredContentView()
    private let wrappedView: UIView
    private(set) var showsContent = false

    init(_ view: UIView) {
        wrappedView = view
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = true
        addSubview(content)
        content.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = true
        content.alpha = 0
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        TokenTradeMotion.place(content, in: bounds)
        TokenTradeMotion.place(wrappedView, in: bounds)
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard showsContent != visible else { return }
        showsContent = visible
        isUserInteractionEnabled = visible
        accessibilityElementsHidden = !visible
        let hiddenTransform = CGAffineTransform(translationX: 0, y: visible ? 6 : -4).scaledBy(x: 0.94, y: 0.94)
        if visible, content.alpha == 0 {
            content.transform = hiddenTransform
            content.blurRadius = animated ? 4 : 0
        }
        TokenTradeMotion.animate(animated) {
            self.content.alpha = visible ? 1 : 0
            self.content.transform = visible || !animated ? .identity : hiddenTransform
            self.content.blurRadius = visible || !animated ? 0 : 4
        }
    }
}

/// The touch target stays fixed while only its visible content responds to a press.
class TokenTradePressButton: UIButton {
    let content = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        content.isUserInteractionEnabled = false
        content.accessibilityElementsHidden = true
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        TokenTradeMotion.place(content, in: bounds)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let changes = {
                self.content.transform = self.isHighlighted && TokenTradeMotion.enabled
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
                self.content.alpha = self.isEnabled ? (self.isHighlighted ? 0.75 : 1) : 0.45
            }
            if TokenTradeMotion.enabled {
                UIView.animate(withDuration: isHighlighted ? 0.1 : TokenTradeMotion.duration, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
            } else { UIView.performWithoutAnimation(changes) }
        }
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            TokenTradeMotion.animate(window != nil) {
                self.content.alpha = self.isEnabled ? 1 : 0.45
            }
        }
    }
}

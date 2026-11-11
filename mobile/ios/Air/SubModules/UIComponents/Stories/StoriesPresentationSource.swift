import UIKit

/// A visible card and its action, valid only while they represent the same content.
@MainActor public final class StoriesPresentationSource {
    private weak var view: UIView?
    private weak var backgroundView: UIView?
    private weak var button: UIButton?
    private let isValid: () -> Bool
    private var prepareForPresentation: (() -> (() -> Void))?
    private var restoreAppearance: (() -> Void)?
    private var hiddenState: Bool?
    private var snapshot: UIView?
    private var backgroundSnapshot: UIView?
    let cornerRadius: CGFloat

    public init(view: UIView, backgroundView: UIView? = nil, button: UIButton, cornerRadius: CGFloat = 26, isValid: @escaping () -> Bool = { true }) {
        self.view = view
        self.backgroundView = backgroundView
        self.button = button
        self.cornerRadius = cornerRadius
        self.isValid = isValid
    }

    public convenience init(view: UIView, backgroundView: UIView? = nil, button: UIButton, cornerRadius: CGFloat = 26,
                            prepareForPresentation: @escaping () -> (() -> Void),
                            isValid: @escaping () -> Bool = { true }) {
        self.init(view: view, backgroundView: backgroundView, button: button, cornerRadius: cornerRadius, isValid: isValid)
        self.prepareForPresentation = prepareForPresentation
    }

    struct Anchor {
        let view: UIView
        let button: UIButton
        let frame: CGRect
        let buttonFrame: CGRect
    }

    func resolve(in container: UIView) -> Anchor? {
        guard isValid(), let view, let button, !view.isHidden || hiddenState != nil, !button.isHidden,
              let window = view.window, window === container.window, button.window === window,
              !view.bounds.isEmpty, !button.bounds.isEmpty,
              view.convert(view.bounds, to: window).intersects(window.bounds) else { return nil }
        if hiddenState == nil, restoreAppearance == nil { restoreAppearance = prepareForPresentation?() }
        return .init(view: view, button: button, frame: view.convert(view.bounds, to: container),
                     buttonFrame: button.convert(button.bounds, to: container))
    }

    func makeSnapshot(_ anchor: Anchor) -> UIView? {
        guard isValid(), view === anchor.view else { return nil }
        if hiddenState != nil { return snapshot }
        let isBackgroundHidden = backgroundView?.isHidden ?? false
        backgroundView?.isHidden = true
        defer { backgroundView?.isHidden = isBackgroundHidden }
        let wasHidden = anchor.button.isHidden
        anchor.button.isHidden = true
        defer { anchor.button.isHidden = wasHidden }
        // A bitmap keeps the transition snapshot independent of live video in the window
        snapshot = UIImageView(image: anchor.view.makeLayerImage())
        return snapshot
    }

    func makeBackgroundSnapshot(_ anchor: Anchor) -> UIView? {
        guard isValid(), view === anchor.view, let backgroundView else { return nil }
        if hiddenState != nil { return backgroundSnapshot }
        backgroundSnapshot = UIImageView(image: backgroundView.makeLayerImage())
        return backgroundSnapshot
    }

    func hide(_ anchor: Anchor) {
        guard isValid(), view === anchor.view else { return }
        if hiddenState == nil { hiddenState = anchor.view.isHidden }
        anchor.view.isHidden = true
        restoreAppearance?()
        restoreAppearance = nil
    }

    func restore() {
        defer { hiddenState = nil; snapshot = nil; backgroundSnapshot = nil; restoreAppearance = nil }
        guard isValid() else { return }
        restoreAppearance?()
        if let hiddenState { view?.isHidden = hiddenState }
    }
}

import UIKit

public struct ContextMenuInteractionTriggers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let tap = ContextMenuInteractionTriggers(rawValue: 1 << 0)
    public static let longPress = ContextMenuInteractionTriggers(rawValue: 1 << 1)
}

@MainActor
public final class ContextMenuInteraction: NSObject, UIGestureRecognizerDelegate {
    private let triggers: ContextMenuInteractionTriggers
    private let longPressDuration: TimeInterval
    private let sourcePortal: ContextMenuSourcePortal?
    private let pressAnimation: ContextMenuPressAnimation?
    private let activationViewProvider: ((UIView) -> UIView?)?
    private let activationHitTestProvider: ((UIView, CGPoint) -> Bool)?
    private let onWillPresent: (() -> Void)?
    private let onDidDismiss: (() -> Void)?
    private let presentationReferenceProvider: ((UIView) -> ContextMenuPresentationReference)?
    private let configurationProvider: (UIView) -> ContextMenuConfiguration?

    private weak var sourceView: UIView?
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var pressAnimationGestureRecognizer: ContextMenuPressAnimationGestureRecognizer?
    private weak var presentedOverlayView: ContextMenuOverlayView?

    public init(
        triggers: ContextMenuInteractionTriggers = [.tap, .longPress],
        longPressDuration: TimeInterval = 0.32,
        sourcePortal: ContextMenuSourcePortal? = nil,
        pressAnimation: ContextMenuPressAnimation? = nil,
        activationViewProvider: ((UIView) -> UIView?)? = nil,
        activationHitTestProvider: ((UIView, CGPoint) -> Bool)? = nil,
        onWillPresent: (() -> Void)? = nil,
        onDidDismiss: (() -> Void)? = nil,
        configurationProvider: @escaping (UIView) -> ContextMenuConfiguration?
    ) {
        self.triggers = triggers
        self.longPressDuration = longPressDuration
        self.sourcePortal = sourcePortal
        self.pressAnimation = pressAnimation
        self.activationViewProvider = activationViewProvider
        self.activationHitTestProvider = activationHitTestProvider
        self.onWillPresent = onWillPresent
        self.onDidDismiss = onDidDismiss
        self.presentationReferenceProvider = nil
        self.configurationProvider = configurationProvider
        super.init()
    }

    init(
        triggers: ContextMenuInteractionTriggers = [.tap, .longPress],
        longPressDuration: TimeInterval = 0.32,
        sourcePortal: ContextMenuSourcePortal? = nil,
        pressAnimation: ContextMenuPressAnimation? = nil,
        activationViewProvider: ((UIView) -> UIView?)? = nil,
        activationHitTestProvider: ((UIView, CGPoint) -> Bool)? = nil,
        onWillPresent: (() -> Void)? = nil,
        onDidDismiss: (() -> Void)? = nil,
        presentationReferenceProvider: ((UIView) -> ContextMenuPresentationReference)? = nil,
        configurationProvider: @escaping (UIView) -> ContextMenuConfiguration?
    ) {
        self.triggers = triggers
        self.longPressDuration = longPressDuration
        self.sourcePortal = sourcePortal
        self.pressAnimation = pressAnimation
        self.activationViewProvider = activationViewProvider
        self.activationHitTestProvider = activationHitTestProvider
        self.onWillPresent = onWillPresent
        self.onDidDismiss = onDidDismiss
        self.presentationReferenceProvider = presentationReferenceProvider
        self.configurationProvider = configurationProvider
        super.init()
    }

    public func attach(to view: UIView) {
        self.detach()
        self.sourceView = view

        if self.triggers.contains(.tap) {
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
            tapGestureRecognizer.delegate = self
            view.addGestureRecognizer(tapGestureRecognizer)
            self.tapGestureRecognizer = tapGestureRecognizer
        }

        if self.triggers.contains(.longPress) {
            if let pressAnimation {
                let pressAnimationGestureRecognizer = ContextMenuPressAnimationGestureRecognizer(target: self, action: #selector(self.handlePressAnimationLongPress(_:)))
                pressAnimationGestureRecognizer.activationDuration = self.longPressDuration
                pressAnimationGestureRecognizer.beginDelay = pressAnimation.beginDelay
                pressAnimationGestureRecognizer.pressInDuration = pressAnimation.pressInDuration
                pressAnimationGestureRecognizer.allowableMovement = pressAnimation.allowableMovement
                pressAnimationGestureRecognizer.delegate = self
                pressAnimationGestureRecognizer.activationProgress = { [weak self] progress, update in
                    guard let self, let sourceView = self.sourceView, let pressAnimation = self.pressAnimation else {
                        return
                    }
                    let targetView = self.resolveActivationView(for: sourceView)
                    ContextMenuPressAnimationApplier.apply(
                        pressAnimation,
                        to: targetView,
                        progress: progress,
                        update: update
                    )
                }
                view.addGestureRecognizer(pressAnimationGestureRecognizer)
                self.pressAnimationGestureRecognizer = pressAnimationGestureRecognizer
            } else {
                let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(_:)))
                longPressGestureRecognizer.minimumPressDuration = self.longPressDuration
                longPressGestureRecognizer.delegate = self
                view.addGestureRecognizer(longPressGestureRecognizer)
                self.longPressGestureRecognizer = longPressGestureRecognizer
            }
        }
    }

    public func detach() {
        if let tapGestureRecognizer {
            tapGestureRecognizer.view?.removeGestureRecognizer(tapGestureRecognizer)
        }
        if let longPressGestureRecognizer {
            longPressGestureRecognizer.view?.removeGestureRecognizer(longPressGestureRecognizer)
        }
        if let pressAnimationGestureRecognizer {
            pressAnimationGestureRecognizer.cancelPressAnimation()
            pressAnimationGestureRecognizer.view?.removeGestureRecognizer(pressAnimationGestureRecognizer)
        }
        self.tapGestureRecognizer = nil
        self.longPressGestureRecognizer = nil
        self.pressAnimationGestureRecognizer = nil
        self.sourceView = nil
    }

    @objc private func handleTap() {
        guard self.presentedOverlayView == nil else {
            return
        }
        self.presentMenu(triggeredByLongPress: false)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        self.handleLongPressState(recognizer)
    }

    @objc private func handlePressAnimationLongPress(_ recognizer: UIGestureRecognizer) {
        self.handleLongPressState(recognizer)
    }

    private func handleLongPressState(_ recognizer: UIGestureRecognizer) {
        guard let sourceView = recognizer.view else {
            return
        }

        let pointInWindow = sourceView.convert(recognizer.location(in: sourceView), to: nil)
        switch recognizer.state {
        case .began:
            if self.presentedOverlayView == nil {
                self.cancelCompetingGestureRecognizers(on: sourceView, excluding: recognizer)
                self.presentMenu(triggeredByLongPress: true)
            }
        case .changed:
            self.presentedOverlayView?.beginExternalSelection(at: pointInWindow)
            self.presentedOverlayView?.updateExternalSelection(at: pointInWindow)
        case .ended:
            self.presentedOverlayView?.endExternalSelection(performAction: true)
        case .cancelled, .failed:
            self.presentedOverlayView?.endExternalSelection(performAction: false)
        default:
            break
        }
    }

    private func presentMenu(triggeredByLongPress: Bool) {
        guard let sourceView else {
            return
        }
        guard let configuration = self.configurationProvider(sourceView) else {
            return
        }
        if triggeredByLongPress {
            ContextMenuHaptics.playLongPressActivation()
        }
        let presentationReference = self.resolvePresentationReference(for: sourceView)
        self.onWillPresent?()
        guard let overlayView = ContextMenuPresenter.present(
            configuration: configuration,
            from: sourceView,
            presentationReference: presentationReference
        ) else {
            self.onDidDismiss?()
            return
        }
        overlayView.onDidDismiss = { [weak self, weak overlayView] in
            guard let self else {
                return
            }
            if self.presentedOverlayView === overlayView {
                self.presentedOverlayView = nil
            }
            self.onDidDismiss?()
        }
        self.presentedOverlayView = overlayView
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let activationHitTestProvider, let sourceView = gestureRecognizer.view else {
            return true
        }

        let point = touch.location(in: sourceView)
        return activationHitTestProvider(sourceView, point)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return true
    }

    private func resolvePresentationReference(for sourceView: UIView) -> ContextMenuPresentationReference {
        if let presentationReferenceProvider {
            return presentationReferenceProvider(sourceView)
        } else {
            return ContextMenuPresentationReference.from(view: self.resolveActivationView(for: sourceView), sourcePortal: self.sourcePortal)
        }
    }

    private func resolveActivationView(for sourceView: UIView) -> UIView {
        self.activationViewProvider?(sourceView) ?? sourceView
    }

    private func cancelCompetingGestureRecognizers(on sourceView: UIView, excluding activeRecognizer: UIGestureRecognizer) {
        for recognizer in sourceView.gestureRecognizers ?? [] {
            guard recognizer !== activeRecognizer,
                  recognizer !== self.tapGestureRecognizer,
                  recognizer !== self.longPressGestureRecognizer,
                  recognizer !== self.pressAnimationGestureRecognizer else {
                continue
            }
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }
}

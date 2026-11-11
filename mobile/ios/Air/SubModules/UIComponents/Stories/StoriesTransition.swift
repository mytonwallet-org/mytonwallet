import UIKit

final class StoriesTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool
    private var animator: UIViewPropertyAnimator?

    init(isPresenting: Bool) { self.isPresenting = isPresenting }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        TradeMotion.enabled ? (isPresenting ? 0.65 : 0.4) : 0.2
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: transitionContext).startAnimation()
    }

    func interruptibleAnimator(using context: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
        if let animator { return animator }
        let key: UITransitionContextViewControllerKey = isPresenting ? .to : .from
        guard let controller = context.viewController(forKey: key) as? StoriesViewController else {
            let empty = UIViewPropertyAnimator(duration: 0, curve: .linear)
            empty.addCompletion { _ in context.completeTransition(false) }
            return empty
        }
        let view = controller.view!
        let container = context.containerView
        let source = controller.presentationSource
        let anchor = TradeMotion.enabled ? source?.resolve(in: container) : nil
        guard let anchor, let card = source?.makeSnapshot(anchor),
              let background = source?.makeBackgroundSnapshot(anchor) else {
            return fallback(context: context, controller: controller)
        }
        let fullFrame = isPresenting ? context.finalFrame(for: controller) : context.initialFrame(for: controller)
        if isPresenting {
            view.frame = fullFrame
            container.addSubview(view)
            view.layoutIfNeeded()
            view.layoutIfNeeded()
        }
        let currentFrame = view.convert(view.bounds, to: container)
        let fullSize = view.bounds.size
        controller.finishActionTransition()
        let action = controller.transitionActionButton
        let isActionHidden = action.isHidden
        let currentActionFrame = action.convert(action.bounds, to: container)
        let originalTint = action.glassTintColor
        let sourceTint = (anchor.button as? WInteractiveGlassButton)?.glassTintColor ?? anchor.button.tintColor ?? originalTint
        let sourceRadius = source?.cornerRadius ?? 26
        let deviceRadius = controller.dismissalCornerRadius > 0
            ? controller.dismissalCornerRadius : controller.presentationCornerRadius
        let fromFrame = isPresenting ? anchor.frame : currentFrame
        let toFrame = isPresenting ? fullFrame : anchor.frame
        let velocity = controller.dismissalVelocity
        let restoreAction = controller.liftTransitionAction(into: container)
        action.isHidden = false
        action.setGlassMaterialized(isPresenting || !isActionHidden)
        let flight = UIView(frame: fromFrame)
        flight.isUserInteractionEnabled = false
        flight.clipsToBounds = true
        flight.layer.cornerCurve = .continuous
        Self.setCornerRadius(isPresenting ? sourceRadius : deviceRadius, on: flight)
        container.insertSubview(flight, belowSubview: action)
        view.removeFromSuperview()
        Self.setSnapshotSize(fromFrame.size, on: background)
        flight.addSubview(background)
        flight.addSubview(view)
        controller.resetDismissalGeometry()
        view.bounds = CGRect(origin: .zero, size: fullSize)
        view.center = CGPoint(x: currentFrame.midX - fromFrame.minX, y: currentFrame.midY - fromFrame.minY)
        view.alpha = isPresenting ? 0 : 1
        card.autoresizingMask = []
        Self.setSnapshotSize(anchor.frame.size, on: card)
        card.center = CGPoint(x: anchor.frame.midX - fromFrame.minX, y: anchor.frame.midY - fromFrame.minY)
        card.alpha = isPresenting ? 1 : 0
        flight.addSubview(card)
        action.frame = isPresenting ? anchor.buttonFrame : currentActionFrame
        action.setGlassTintColor(isPresenting ? sourceTint : originalTint)
        action.layoutIfNeeded()
        let sourceLabel = (anchor.button as? WInteractiveGlassButton)?.glassTitleLabel ?? anchor.button.titleLabel
        let sourceTitle = UILabel(frame: action.glassContentView.bounds)
        sourceTitle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sourceTitle.font = sourceLabel?.font
        sourceTitle.text = anchor.button.title(for: .normal)
        sourceTitle.textColor = sourceLabel?.textColor ?? .white
        sourceTitle.textAlignment = .center
        sourceTitle.alpha = isPresenting ? 1 : 0
        action.glassContentView.addSubview(sourceTitle)
        let destinationTitle = UILabel(frame: action.glassContentView.bounds)
        destinationTitle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        destinationTitle.font = action.glassTitleLabel.font
        destinationTitle.attributedText = action.glassTitleLabel.attributedText
        destinationTitle.textColor = action.glassTitleLabel.textColor
        destinationTitle.textAlignment = .center
        destinationTitle.alpha = isPresenting ? 0 : 1
        action.glassContentView.addSubview(destinationTitle)
        action.glassTitleLabel.alpha = 0
        source?.hide(anchor)
        let deltaY = toFrame.midY - fromFrame.midY
        let normalizedVelocity = !isPresenting && abs(deltaY) > 1 ? velocity / deltaY : -0.12
        let timing = UISpringTimingParameters(dampingRatio: isPresenting ? 0.82 : 0.9,
            initialVelocity: CGVector(dx: 0, dy: max(-3, min(3, normalizedVelocity))))
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), timingParameters: timing)
        animator.addAnimations {
            flight.frame = toFrame
            Self.setCornerRadius(self.isPresenting ? deviceRadius : sourceRadius, on: flight)
            view.center = CGPoint(x: currentFrame.midX - toFrame.minX, y: currentFrame.midY - toFrame.minY)
            view.alpha = self.isPresenting ? 1 : 0
            Self.setSnapshotSize(toFrame.size, on: background)
            card.center = CGPoint(x: anchor.frame.midX - toFrame.minX, y: anchor.frame.midY - toFrame.minY)
            card.alpha = self.isPresenting ? 0 : 1
            action.frame = self.isPresenting ? currentActionFrame : anchor.buttonFrame
            action.setGlassTintColor(self.isPresenting ? originalTint : sourceTint)
            action.setGlassMaterialized(!self.isPresenting || !isActionHidden)
            destinationTitle.alpha = self.isPresenting ? 1 : 0
            sourceTitle.alpha = self.isPresenting ? 0 : 1
            action.layoutIfNeeded()
        }
        animator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            UIView.performWithoutAnimation {
                view.removeFromSuperview()
                container.addSubview(view)
                controller.resetDismissalGeometry()
                view.frame = fullFrame
                view.alpha = 1
                action.setGlassTintColor(originalTint)
                sourceTitle.removeFromSuperview()
                destinationTitle.removeFromSuperview()
                restoreAction()
                action.isHidden = isActionHidden
                action.setGlassMaterialized(!isActionHidden)
                action.glassTitleLabel.alpha = 1
                flight.removeFromSuperview()
                if self.isPresenting ? !completed : completed { source?.restore() }
                view.layoutIfNeeded()
            }
            if !self.isPresenting && completed { view.removeFromSuperview() }
            context.completeTransition(completed)
            if !self.isPresenting && !completed { controller.resumeAfterCancelledDismissal() }
            self.animator = nil
        }
        self.animator = animator
        return animator
    }

    private func fallback(context: any UIViewControllerContextTransitioning,
                          controller: StoriesViewController) -> UIViewPropertyAnimator {
        let view = controller.view!
        let source = controller.presentationSource
        if let anchor = source?.resolve(in: context.containerView) { source?.hide(anchor) }
        if isPresenting {
            view.frame = context.finalFrame(for: controller)
            context.containerView.addSubview(view)
            view.alpha = 0
        }
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), curve: .easeOut) {
            view.alpha = self.isPresenting ? 1 : 0
            if !self.isPresenting, TradeMotion.enabled {
                view.transform = CGAffineTransform(translationX: 0, y: context.containerView.bounds.height)
            }
        }
        animator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            controller.resetDismissalGeometry()
            view.alpha = 1
            if self.isPresenting ? !completed : completed { source?.restore() }
            context.completeTransition(completed)
            if !self.isPresenting && !completed { controller.resumeAfterCancelledDismissal() }
            self.animator = nil
        }
        self.animator = animator
        return animator
    }

    static func deviceCornerRadius(for view: UIView) -> CGFloat {
        guard #available(iOS 26, *) else { return 0 }
        let previous = view.cornerConfiguration
        view.cornerConfiguration = .uniformCorners(radius: .containerConcentric())
        let radius = view.effectiveRadius(corner: .allCorners)
        view.cornerConfiguration = previous
        return radius
    }

    static func setSnapshotSize(_ size: CGSize, on snapshot: UIView) {
        guard !snapshot.bounds.isEmpty else { return }
        snapshot.center = CGPoint(x: size.width / 2, y: size.height / 2)
        snapshot.transform = CGAffineTransform(scaleX: size.width / snapshot.bounds.width,
                                               y: size.height / snapshot.bounds.height)
    }

    private static func setCornerRadius(_ radius: CGFloat, on view: UIView) {
        if #available(iOS 26, *) { view.cornerConfiguration = .corners(radius: .fixed(radius)) }
        else { view.layer.cornerRadius = radius }
    }
}

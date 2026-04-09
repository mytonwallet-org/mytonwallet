import UIKit

@MainActor
final class ContextMenuOverlayView: UIView, ContextMenuNavigationViewDelegate {
    private static let externalSelectionActivationDistance: CGFloat = 4.0

    private enum VerticalDirection {
        case above
        case below
    }

    private struct PanelPlacement {
        let panelSize: CGSize
        let panelOrigin: CGPoint
    }

    private let configuration: ContextMenuConfiguration
    private let sourceRectInWindow: CGRect
    private weak var portalSourceView: UIView?
    private let portalMaskRectInWindow: CGRect?
    private let portalMask: ContextMenuSourcePortalMask?
    private let portalShowsBackdropCutout: Bool

    private let dimmingView = UIView()
    private var blurView: UIVisualEffectView?
    private var portalView: ContextMenuPortalView?
    private var hasAnimatedIn = false
    private var isDismissingMenu = false
    private var pendingExternalSelectionPoint: CGPoint?
    private var initialExternalSelectionPoint: CGPoint?
    private var didMoveFromInitialExternalSelectionPoint = false
    private var frozenNavigationFrame: CGRect?
    private lazy var customRowContext = ContextMenuCustomRowContext(dismissHandler: { [weak self] in
        self?.dismissMenu()
    })
    private lazy var navigationView = ContextMenuNavigationView(
        rootPage: self.configuration.rootPage,
        style: self.configuration.style,
        customRowContext: self.customRowContext
    )

    var onDidDismiss: (() -> Void)?

    init(
        configuration: ContextMenuConfiguration,
        sourceRectInWindow: CGRect,
        portalSourceView: UIView?,
        portalMaskRectInWindow: CGRect?,
        portalMask: ContextMenuSourcePortalMask?,
        portalShowsBackdropCutout: Bool
    ) {
        self.configuration = configuration
        self.sourceRectInWindow = sourceRectInWindow
        self.portalSourceView = portalSourceView
        self.portalMaskRectInWindow = portalMaskRectInWindow
        self.portalMask = portalMask
        self.portalShowsBackdropCutout = portalShowsBackdropCutout

        super.init(frame: .zero)

        self.navigationView.delegate = self
        self.navigationView.requestLayout = { [weak self] in
            self?.layoutMenu()
        }

        self.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.backgroundColor = .clear

        switch self.configuration.backdrop {
        case .none:
            break
        case let .blurred(style, _):
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: style))
            blurView.alpha = 0.0
            blurView.frame = self.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.addSubview(blurView)
            self.blurView = blurView
        case .dimmed:
            break
        }

        self.dimmingView.backgroundColor = ContextMenuVisuals.backdropTintColor(for: self.traitCollection)
        self.dimmingView.alpha = 0.0
        self.dimmingView.frame = self.bounds
        self.dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(self.dimmingView)

        if let portalSourceView, let portalView = ContextMenuPortalView(sourceView: portalSourceView) {
            portalView.alpha = 1.0
            self.portalView = portalView
            self.addSubview(portalView)
        }

        self.navigationView.alpha = 0.0
        self.addSubview(self.navigationView)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleOutsideTap(_:)))
        tapGestureRecognizer.cancelsTouchesInView = false
        self.addGestureRecognizer(tapGestureRecognizer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateBackdropMask()
        self.layoutPortalView()
        self.layoutMenu()
    }

    func activatePresentationIfNeeded() {
        guard self.window != nil, !self.hasAnimatedIn else {
            return
        }
        self.hasAnimatedIn = true

        self.layoutMenu()
        self.animateIn()
    }

    func beginExternalSelection(at pointInWindow: CGPoint) {
        self.pendingExternalSelectionPoint = pointInWindow
        if self.initialExternalSelectionPoint == nil {
            self.initialExternalSelectionPoint = pointInWindow
        }
    }

    func updateExternalSelection(at pointInWindow: CGPoint) {
        self.pendingExternalSelectionPoint = pointInWindow
        if self.initialExternalSelectionPoint == nil {
            self.initialExternalSelectionPoint = pointInWindow
        }
        guard self.hasAnimatedIn else {
            return
        }

        guard let initialExternalSelectionPoint = self.initialExternalSelectionPoint else {
            return
        }

        if !self.didMoveFromInitialExternalSelectionPoint {
            let distance = abs(pointInWindow.y - initialExternalSelectionPoint.y)
            if distance > Self.externalSelectionActivationDistance {
                self.didMoveFromInitialExternalSelectionPoint = true
                self.navigationView.beginExternalSelection(at: pointInWindow)
            }
        } else {
            self.navigationView.updateExternalSelection(at: pointInWindow)
        }
    }

    func endExternalSelection(performAction: Bool) {
        self.pendingExternalSelectionPoint = nil
        defer {
            self.initialExternalSelectionPoint = nil
            self.didMoveFromInitialExternalSelectionPoint = false
        }
        guard self.hasAnimatedIn, self.didMoveFromInitialExternalSelectionPoint else {
            return
        }
        self.navigationView.endExternalSelection(performAction: performAction)
    }

    func navigationView(_ navigationView: ContextMenuNavigationView, didActivate action: ContextMenuActivation) {
        let handler = action.handler
        if action.dismissesMenu {
            self.dismissMenu {
                handler?()
            }
        } else {
            handler?()
        }
    }

    @objc private func handleOutsideTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if self.navigationView.frame.contains(point) {
            return
        }
        self.dismissMenu()
    }

    private func layoutMenu() {
        if self.isDismissingMenu, let frozenNavigationFrame {
            self.navigationView.frame = frozenNavigationFrame
            return
        }

        let safeFrame = self.bounds.inset(by: UIEdgeInsets(
            top: self.safeAreaInsets.top + self.configuration.style.screenInsets.top,
            left: self.configuration.style.screenInsets.left,
            bottom: self.safeAreaInsets.bottom + self.configuration.style.screenInsets.bottom,
            right: self.configuration.style.screenInsets.right
        ))

        let placement = self.panelPlacement(in: safeFrame)
        let navigationFrame = CGRect(
            x: placement.panelOrigin.x - self.configuration.style.panelInset,
            y: placement.panelOrigin.y - self.configuration.style.panelInset,
            width: placement.panelSize.width + self.configuration.style.panelInset * 2.0,
            height: placement.panelSize.height + self.configuration.style.panelInset * 2.0
        )

        self.navigationView.frame = navigationFrame
        self.frozenNavigationFrame = navigationFrame
        self.navigationView.applyPanelLayout(panelSize: placement.panelSize)
    }

    private func panelPlacement(in safeFrame: CGRect) -> PanelPlacement {
        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let maxPanelWidth = min(self.configuration.style.maxWidth, safeFrame.width)

        switch self.configuration.style.verticalPlacementBehavior {
        case .screenBalanced:
            let maxPanelSize = CGSize(
                width: maxPanelWidth,
                height: max(120.0, safeFrame.height * self.configuration.style.maximumHeightRatio)
            )
            let panelSize = self.navigationView.preferredPanelSize(constrainedTo: maxPanelSize)
            let panelOrigin = self.panelOriginScreenBalanced(for: panelSize, safeFrame: safeFrame, sourceRect: sourceRect)
            return PanelPlacement(panelSize: panelSize, panelOrigin: panelOrigin)
        case .sourceAttached:
            let idealPanelSize = self.navigationView.preferredPanelSize(
                constrainedTo: CGSize(width: maxPanelWidth, height: max(1.0, safeFrame.height))
            )
            let direction = self.preferredVerticalDirection(
                idealPanelHeight: idealPanelSize.height,
                safeFrame: safeFrame,
                sourceRect: sourceRect
            )
            let availableHeight = self.availableHeight(for: direction, safeFrame: safeFrame, sourceRect: sourceRect)
            let panelSize = self.navigationView.preferredPanelSize(
                constrainedTo: CGSize(width: maxPanelWidth, height: max(1.0, availableHeight))
            )
            let panelOrigin = self.panelOriginSourceAttached(
                for: panelSize,
                direction: direction,
                safeFrame: safeFrame,
                sourceRect: sourceRect
            )
            return PanelPlacement(panelSize: panelSize, panelOrigin: panelOrigin)
        }
    }

    private func panelOriginScreenBalanced(for panelSize: CGSize, safeFrame: CGRect, sourceRect: CGRect) -> CGPoint {
        let availableAbove = sourceRect.minY - safeFrame.minY - self.configuration.style.sourceSpacing
        let availableBelow = safeFrame.maxY - sourceRect.maxY - self.configuration.style.sourceSpacing

        let wantsBelow = availableBelow >= min(panelSize.height, 180.0) || availableBelow >= availableAbove
        let x = min(max(sourceRect.midX - panelSize.width * 0.5, safeFrame.minX), safeFrame.maxX - panelSize.width)
        let y: CGFloat
        if wantsBelow {
            y = min(sourceRect.maxY + self.configuration.style.sourceSpacing, safeFrame.maxY - panelSize.height)
        } else {
            y = max(safeFrame.minY, sourceRect.minY - self.configuration.style.sourceSpacing - panelSize.height)
        }
        return CGPoint(x: x, y: y)
    }

    private func panelOriginSourceAttached(
        for panelSize: CGSize,
        direction: VerticalDirection,
        safeFrame: CGRect,
        sourceRect: CGRect
    ) -> CGPoint {
        let x = min(max(sourceRect.midX - panelSize.width * 0.5, safeFrame.minX), safeFrame.maxX - panelSize.width)
        let y: CGFloat
        switch direction {
        case .below:
            y = sourceRect.maxY + self.configuration.style.sourceSpacing
        case .above:
            y = sourceRect.minY - self.configuration.style.sourceSpacing - panelSize.height
        }
        return CGPoint(x: x, y: y)
    }

    private func preferredVerticalDirection(
        idealPanelHeight: CGFloat,
        safeFrame: CGRect,
        sourceRect: CGRect
    ) -> VerticalDirection {
        let availableBelow = self.availableHeight(for: .below, safeFrame: safeFrame, sourceRect: sourceRect)
        let availableAbove = self.availableHeight(for: .above, safeFrame: safeFrame, sourceRect: sourceRect)

        if idealPanelHeight <= availableBelow {
            return .below
        } else if idealPanelHeight <= availableAbove {
            return .above
        } else {
            return availableBelow >= availableAbove ? .below : .above
        }
    }

    private func availableHeight(
        for direction: VerticalDirection,
        safeFrame: CGRect,
        sourceRect: CGRect
    ) -> CGFloat {
        switch direction {
        case .below:
            return max(0.0, safeFrame.maxY - sourceRect.maxY - self.configuration.style.sourceSpacing)
        case .above:
            return max(0.0, sourceRect.minY - safeFrame.minY - self.configuration.style.sourceSpacing)
        }
    }

    private func menuPositionDelta() -> CGPoint {
        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let navigationFrame = self.navigationView.frame
        return CGPoint(
            x: sourceRect.midX - navigationFrame.midX,
            y: sourceRect.midY - navigationFrame.midY
        )
    }

    private func targetBackdropAlpha() -> CGFloat {
        switch self.configuration.backdrop {
        case .none:
            return 0.0
        case let .dimmed(alpha):
            return alpha
        case let .blurred(_, dimAlpha):
            return dimAlpha
        }
    }

    private func animateIn() {
        let delta = self.menuPositionDelta()
        let targetBackdropAlpha = self.targetBackdropAlpha()

        self.navigationView.alpha = 1.0
        self.dimmingView.alpha = targetBackdropAlpha
        self.blurView?.alpha = 1.0

        self.navigationView.layer.addContextMenuAlphaAnimation(from: 0.0, to: 1.0, duration: 0.05)
        self.navigationView.layer.addContextMenuSpringAnimation(
            keyPath: "transform.scale",
            from: 0.01 as NSNumber,
            to: 1.0 as NSNumber,
            duration: ContextMenuAnimationSupport.appearDuration,
            damping: ContextMenuAnimationSupport.appearDamping,
            additive: false
        )
        self.navigationView.layer.addContextMenuSpringAnimation(
            keyPath: "position",
            from: NSValue(cgPoint: delta),
            to: NSValue(cgPoint: .zero),
            duration: ContextMenuAnimationSupport.appearDuration,
            damping: ContextMenuAnimationSupport.appearDamping,
            additive: true
        )

        self.blurView?.layer.addContextMenuAlphaAnimation(from: 0.0, to: 1.0, duration: 0.2)
        self.dimmingView.layer.addContextMenuAlphaAnimation(from: 0.0, to: targetBackdropAlpha, duration: 0.2)
    }

    private func dismissMenu(completion: (() -> Void)? = nil) {
        guard !self.isDismissingMenu else {
            return
        }

        self.isDismissingMenu = true
        self.pendingExternalSelectionPoint = nil
        self.initialExternalSelectionPoint = nil
        self.didMoveFromInitialExternalSelectionPoint = false
        self.navigationView.clearSelections()
        self.isUserInteractionEnabled = false
        self.frozenNavigationFrame = self.navigationView.frame

        let delta = self.menuPositionDelta()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else {
                return
            }
            self.removeFromPresentationHost(completion: completion)
        }

        self.navigationView.layer.addContextMenuAlphaAnimation(
            from: 1.0,
            to: 0.0,
            duration: ContextMenuAnimationSupport.disappearDuration,
            removeOnCompletion: false
        )
        self.navigationView.layer.addContextMenuBasicAnimation(
            keyPath: "transform.scale",
            from: 1.0 as NSNumber,
            to: 0.01 as NSNumber,
            duration: ContextMenuAnimationSupport.disappearDuration,
            timingFunction: .easeInEaseOut,
            removeOnCompletion: false
        )
        self.navigationView.layer.addContextMenuBasicAnimation(
            keyPath: "position",
            from: NSValue(cgPoint: .zero),
            to: NSValue(cgPoint: delta),
            duration: ContextMenuAnimationSupport.disappearDuration,
            timingFunction: .easeInEaseOut,
            additive: true,
            removeOnCompletion: false
        )

        self.blurView?.layer.addContextMenuAlphaAnimation(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        self.dimmingView.layer.addContextMenuAlphaAnimation(
            from: self.targetBackdropAlpha(),
            to: 0.0,
            duration: 0.2,
            removeOnCompletion: false
        )
        CATransaction.commit()
    }

    private func removeFromPresentationHost(completion: (() -> Void)? = nil) {
        self.removeFromSuperview()
        self.onDidDismiss?()
        completion?()
    }

    private func layoutPortalView() {
        guard let portalView, let portalSourceView else {
            return
        }

        portalView.frame = portalSourceView.convert(portalSourceView.bounds, to: self)

        if let portalMaskRectInWindow, let portalMask {
            let portalMaskRect = portalView.convert(self.convert(portalMaskRectInWindow, from: nil), from: self)
            portalView.updateMask(portalMask, rect: portalMaskRect)
        } else {
            portalView.updateMask(nil, rect: nil)
        }
    }

    private func updateBackdropMask() {
        guard let portalSourceView else {
            self.blurView?.layer.mask = nil
            self.dimmingView.layer.mask = nil
            return
        }

        if self.portalView != nil && !self.portalShowsBackdropCutout {
            self.blurView?.layer.mask = nil
            self.dimmingView.layer.mask = nil
            return
        }

        let exclusionRect: CGRect
        if let portalMaskRectInWindow {
            exclusionRect = self.convert(portalMaskRectInWindow, from: nil)
        } else {
            exclusionRect = portalSourceView.convert(portalSourceView.bounds, to: self)
        }
        guard !exclusionRect.isEmpty else {
            self.blurView?.layer.mask = nil
            self.dimmingView.layer.mask = nil
            return
        }

        let maskPath = UIBezierPath(rect: self.bounds)
        let exclusionPath = UIBezierPath(
            cgPath: ContextMenuPortalMaskShape.path(for: self.portalMask ?? .attachmentRect, in: exclusionRect)
        )
        maskPath.append(exclusionPath)

        let maskLayer = CAShapeLayer()
        maskLayer.frame = self.bounds
        maskLayer.path = maskPath.cgPath
        maskLayer.fillRule = .evenOdd

        self.blurView?.layer.mask = maskLayer
        let dimmingMaskLayer = CAShapeLayer()
        dimmingMaskLayer.frame = self.bounds
        dimmingMaskLayer.path = maskPath.cgPath
        dimmingMaskLayer.fillRule = .evenOdd
        self.dimmingView.layer.mask = dimmingMaskLayer
    }
}

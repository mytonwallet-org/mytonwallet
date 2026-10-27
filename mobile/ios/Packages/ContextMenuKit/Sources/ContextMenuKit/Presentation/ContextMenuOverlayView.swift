import UIKit

@MainActor
final class ContextMenuOverlayView: UIView, ContextMenuNavigationViewDelegate, ContextMenuPresentationSession {
    private static let externalSelectionActivationDistance: CGFloat = 4.0
    private static let panelDismissalSafetyMargin: CGFloat = 8.0

    private enum VerticalDirection {
        case above
        case below
    }

    private struct PanelPlacement {
        let panelSize: CGSize
        let panelOrigin: CGPoint
        let verticalDirection: VerticalDirection
        /// The rect whose top or bottom edge the panel attaches to: the source, or the source with its accessory
        let attachmentRect: CGRect
    }

    private let configuration: ContextMenuConfiguration
    private let sourceRectInWindow: CGRect
    private weak var appearanceSourceView: UIView?
    private weak var portalSourceView: UIView?
    private let portalMaskRectInWindow: CGRect?
    private let portalMask: ContextMenuSourcePortalMask?
    private let portalShowsBackdropCutout: Bool
    private let portalAppliesRightToLeftTransformCorrection: Bool
    private var sourceUserInterfaceStyle: UIUserInterfaceStyle
    private let sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection

    private let dimmingView = UIView()
    private var blurView: UIVisualEffectView?
    private var portalView: ContextMenuPortalView?
    private var accessoryView: ContextMenuAccessoryView?
    private(set) var accessoryFrame: CGRect?
    private var hasAnimatedIn = false
    private var isDismissingMenu = false
    private var pendingExternalSelectionPoint: CGPoint?
    private var initialExternalSelectionPoint: CGPoint?
    private var didMoveFromInitialExternalSelectionPoint = false
    private var frozenNavigationFrame: CGRect?
    private var currentPanelPlacement: PanelPlacement?
    private var presentationVerticalDirection: VerticalDirection?
    private lazy var customRowContext = ContextMenuCustomRowContext(dismissHandler: { [weak self] in
        self?.dismissMenu()
    })
    private lazy var navigationView = ContextMenuNavigationView(
        rootPage: self.configuration.rootPage,
        style: self.configuration.style,
        sourceUserInterfaceStyle: self.sourceUserInterfaceStyle,
        sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection,
        customRowContext: self.customRowContext
    )

    var onDidDismiss: (() -> Void)?

    init(
        configuration: ContextMenuConfiguration,
        sourceRectInWindow: CGRect,
        appearanceSourceView: UIView?,
        portalSourceView: UIView?,
        portalMaskRectInWindow: CGRect?,
        portalMask: ContextMenuSourcePortalMask?,
        portalShowsBackdropCutout: Bool,
        portalAppliesRightToLeftTransformCorrection: Bool,
        sourceUserInterfaceStyle: UIUserInterfaceStyle,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection
    ) {
        self.configuration = configuration
        self.sourceRectInWindow = sourceRectInWindow
        self.appearanceSourceView = appearanceSourceView
        self.portalSourceView = portalSourceView
        self.portalMaskRectInWindow = portalMaskRectInWindow
        self.portalMask = portalMask
        self.portalShowsBackdropCutout = portalShowsBackdropCutout
        self.portalAppliesRightToLeftTransformCorrection = portalAppliesRightToLeftTransformCorrection
        self.sourceUserInterfaceStyle = sourceUserInterfaceStyle
        self.sourceUserInterfaceLayoutDirection = sourceUserInterfaceLayoutDirection

        super.init(frame: .zero)

        self.overrideUserInterfaceStyle = sourceUserInterfaceStyle
        self.semanticContentAttribute = sourceUserInterfaceLayoutDirection.contextMenuSemanticContentAttribute

        self.navigationView.delegate = self
        self.navigationView.requestLayout = { [weak self] in
            self?.layoutMenu()
        }

        self.setup()
        self.registerForSourceTraitChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.backgroundColor = .clear

        switch self.configuration.backdrop {
        case .none:
            break
        case .blurred, .untintedBlur:
            let blurView: UIVisualEffectView
            if case let .untintedBlur(radius, _) = self.configuration.backdrop {
                blurView = ContextMenuUntintedBlurView(radius: radius)
            } else if case let .blurred(style, _) = self.configuration.backdrop {
                blurView = UIVisualEffectView(effect: UIBlurEffect(style: style))
            } else {
                preconditionFailure("Expected a blurred backdrop")
            }
            blurView.alpha = 0.0
            blurView.frame = self.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.addSubview(blurView)
            self.blurView = blurView
        case .dimmed:
            break
        }

        self.dimmingView.backgroundColor = self.configuration.backdropTintColor ?? ContextMenuVisuals.backdropTintColor()
        self.dimmingView.alpha = 0.0
        self.dimmingView.frame = self.bounds
        self.dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(self.dimmingView)

        if !self.configuration.preservesSourceAppearance,
           let portalSourceView,
           let portalView = ContextMenuPortalView(
               sourceView: portalSourceView,
               sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection,
               appliesRightToLeftTransformCorrection: self.portalAppliesRightToLeftTransformCorrection
           ) {
            portalView.alpha = 0.0
            self.portalView = portalView
            self.addSubview(portalView)
        }

        self.navigationView.alpha = 0.0
        self.addSubview(self.navigationView)

        if let accessory = self.configuration.accessory {
            let accessoryContext = ContextMenuAccessoryContext(dismissHandler: { [weak self] in
                self?.dismissMenu()
            })
            let accessoryView = ContextMenuAccessoryView(
                capsules: accessory.backgroundCapsules,
                contentView: accessory.makeContentView(accessoryContext),
                glassTint: self.configuration.style.glassTint,
                sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection
            )
            accessoryView.alpha = 0.0
            self.addSubview(accessoryView)
            self.accessoryView = accessoryView
        }

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleOutsideTap(_:)))
        tapGestureRecognizer.cancelsTouchesInView = false
        self.addGestureRecognizer(tapGestureRecognizer)

        // VoiceOver stays inside the open menu, as with the system context menu, and skips the source's mirror
        self.accessibilityViewIsModal = true
        self.portalView?.accessibilityElementsHidden = true
    }

    override func accessibilityPerformEscape() -> Bool {
        self.dismissMenu()
        return true
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
        UIAccessibility.post(notification: .screenChanged, argument: nil)
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

    private func registerForSourceTraitChanges() {
        guard #available(iOS 17.0, *), let appearanceSourceView else {
            return
        }

        appearanceSourceView.registerForTraitChanges(
            [UITraitUserInterfaceStyle.self],
            target: self,
            action: #selector(self.handleSourceTraitChange(_:previousTraitCollection:))
        )
    }

    @objc private func handleSourceTraitChange(_ sourceView: UIView, previousTraitCollection: UITraitCollection) {
        guard previousTraitCollection.userInterfaceStyle != sourceView.traitCollection.userInterfaceStyle else {
            return
        }
        self.updateUserInterfaceStyle(ContextMenuVisuals.resolvedUserInterfaceStyle(for: sourceView.traitCollection))
    }

    private func updateUserInterfaceStyle(_ userInterfaceStyle: UIUserInterfaceStyle) {
        guard userInterfaceStyle != self.sourceUserInterfaceStyle else {
            return
        }
        self.sourceUserInterfaceStyle = userInterfaceStyle
        self.overrideUserInterfaceStyle = userInterfaceStyle
        self.navigationView.updateUserInterfaceStyle(userInterfaceStyle)
        self.accessoryView?.setNeedsLayout()
        self.layoutMenu()
    }

    @objc private func handleOutsideTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if !self.shouldDismissMenu(at: point) {
            return
        }
        self.dismissMenu()
    }

    var panelFrame: CGRect? {
        self.currentPanelPlacement.map { CGRect(origin: $0.panelOrigin, size: $0.panelSize) }
    }

    func shouldDismissMenu(at point: CGPoint) -> Bool {
        guard let panelFrame else {
            return true
        }
        let isInsidePanel = panelFrame
            .insetBy(dx: -Self.panelDismissalSafetyMargin, dy: -Self.panelDismissalSafetyMargin)
            .contains(point)
        let isInsideAccessory = self.accessoryFrame?
            .insetBy(dx: -Self.panelDismissalSafetyMargin, dy: -Self.panelDismissalSafetyMargin)
            .contains(point) == true
        return !isInsidePanel && !isInsideAccessory
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

        let placement: PanelPlacement
        if let accessory = self.configuration.accessory, let accessoryView {
            let accessoryFrame = self.accessoryFrame(for: accessory, in: safeFrame)
            accessoryView.frame = accessoryFrame
            self.accessoryFrame = accessoryFrame
            placement = self.panelPlacement(in: safeFrame, clearOf: accessoryFrame)
        } else {
            placement = self.panelPlacement(in: safeFrame)
        }
        let navigationFrame = CGRect(
            x: placement.panelOrigin.x - self.configuration.style.panelInset,
            y: placement.panelOrigin.y - self.configuration.style.panelInset,
            width: placement.panelSize.width + self.configuration.style.panelInset * 2.0,
            height: placement.panelSize.height + self.configuration.style.panelInset * 2.0
        )

        self.navigationView.frame = navigationFrame
        self.navigationView.applyPanelLayout(panelSize: placement.panelSize)
        self.currentPanelPlacement = placement
        if !self.navigationView.isTransitioningPages {
            self.updateNavigationAnchor(for: placement)
        }
        self.frozenNavigationFrame = self.navigationView.frame
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
            let preferredDirection = self.preferredScreenBalancedVerticalDirection(
                for: panelSize,
                safeFrame: safeFrame,
                sourceRect: sourceRect
            )
            let direction = self.lockedVerticalDirection(preferred: preferredDirection)
            let panelOrigin = self.panelOriginScreenBalanced(
                for: panelSize,
                direction: direction,
                safeFrame: safeFrame,
                sourceRect: sourceRect
            )
            return PanelPlacement(
                panelSize: panelSize,
                panelOrigin: panelOrigin,
                verticalDirection: direction,
                attachmentRect: sourceRect
            )
        case .screenBottom:
            let availableHeight = max(
                1.0,
                self.bounds.maxY
                    - self.configuration.style.screenInsets.bottom
                    - safeFrame.minY
            )
            let panelSize = self.navigationView.preferredPanelSize(
                constrainedTo: CGSize(width: maxPanelWidth, height: availableHeight)
            )
            let panelOrigin = CGPoint(
                x: min(
                    max(sourceRect.midX - panelSize.width * 0.5, safeFrame.minX),
                    safeFrame.maxX - panelSize.width
                ),
                y: self.bounds.maxY
                    - self.configuration.style.screenInsets.bottom
                    - panelSize.height
            )
            return PanelPlacement(
                panelSize: panelSize,
                panelOrigin: panelOrigin,
                verticalDirection: .above,
                attachmentRect: sourceRect
            )
        case .sourceAttached:
            let idealPanelSize = self.navigationView.preferredPanelSize(
                constrainedTo: CGSize(width: maxPanelWidth, height: max(1.0, safeFrame.height))
            )
            let direction = self.lockedVerticalDirection(
                preferred: self.preferredVerticalDirection(
                    idealPanelHeight: idealPanelSize.height,
                    safeFrame: safeFrame,
                    sourceRect: sourceRect
                )
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
            return PanelPlacement(
                panelSize: panelSize,
                panelOrigin: panelOrigin,
                verticalDirection: direction,
                attachmentRect: sourceRect
            )
        }
    }

    /// Attaches the panel below the source and its accessory, or above them when only that side has room. When
    /// neither side has room, as for a source taller than the screen, the panel overlaps the source at the bottom.
    private func panelPlacement(in safeFrame: CGRect, clearOf accessoryFrame: CGRect) -> PanelPlacement {
        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let attachmentRect = sourceRect.union(accessoryFrame)
        let maxPanelWidth = min(self.configuration.style.maxWidth, safeFrame.width)
        let idealPanelSize = self.navigationView.preferredPanelSize(
            constrainedTo: CGSize(width: maxPanelWidth, height: max(1.0, safeFrame.height))
        )
        let availableBelow = self.availableHeight(for: .below, safeFrame: safeFrame, sourceRect: attachmentRect)
        let availableAbove = self.availableHeight(for: .above, safeFrame: safeFrame, sourceRect: attachmentRect)
        let fitsOnlyAbove = idealPanelSize.height > availableBelow && idealPanelSize.height <= availableAbove
        let direction = self.lockedVerticalDirection(preferred: fitsOnlyAbove ? .above : .below)
        let availableHeight = direction == .below ? availableBelow : availableAbove
        let maxPanelHeight = idealPanelSize.height <= availableHeight
            ? availableHeight
            : max(availableHeight, safeFrame.height * self.configuration.style.maximumHeightRatio)
        let panelSize = self.navigationView.preferredPanelSize(
            constrainedTo: CGSize(width: maxPanelWidth, height: max(1.0, maxPanelHeight))
        )
        let x = min(max(sourceRect.midX - panelSize.width * 0.5, safeFrame.minX), safeFrame.maxX - panelSize.width)
        let y: CGFloat
        switch direction {
        case .below:
            y = min(attachmentRect.maxY + self.configuration.style.sourceSpacing, safeFrame.maxY - panelSize.height)
        case .above:
            y = max(safeFrame.minY, attachmentRect.minY - self.configuration.style.sourceSpacing - panelSize.height)
        }
        // The panel of a source taller than the screen grows from the screen's edge
        let visibleAttachmentRect = attachmentRect.intersection(self.bounds)
        return PanelPlacement(
            panelSize: panelSize,
            panelOrigin: CGPoint(x: x, y: y),
            verticalDirection: direction,
            attachmentRect: visibleAttachmentRect.isNull ? attachmentRect : visibleAttachmentRect
        )
    }

    private func accessoryFrame(for accessory: ContextMenuAccessory, in safeFrame: CGRect) -> CGRect {
        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let allowedFrame = safeFrame.inset(by: UIEdgeInsets(
            top: 0.0,
            left: self.safeAreaInsets.left,
            bottom: 0.0,
            right: self.safeAreaInsets.right
        ))
        let size = accessory.size
        let x = self.sourceUserInterfaceLayoutDirection.contextMenuIsRightToLeft
            ? sourceRect.minX - accessory.topTrailingOffset.dx
            : sourceRect.maxX + accessory.topTrailingOffset.dx - size.width
        let y = sourceRect.minY + accessory.topTrailingOffset.dy
        return CGRect(
            x: min(max(x, allowedFrame.minX), allowedFrame.maxX - size.width),
            y: min(max(y, allowedFrame.minY), allowedFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func lockedVerticalDirection(preferred: VerticalDirection) -> VerticalDirection {
        if let presentationVerticalDirection {
            return presentationVerticalDirection
        }
        self.presentationVerticalDirection = preferred
        return preferred
    }

    private func preferredScreenBalancedVerticalDirection(
        for panelSize: CGSize,
        safeFrame: CGRect,
        sourceRect: CGRect
    ) -> VerticalDirection {
        let availableAbove = sourceRect.minY - safeFrame.minY - self.configuration.style.sourceSpacing
        let availableBelow = safeFrame.maxY - sourceRect.maxY - self.configuration.style.sourceSpacing

        let wantsBelow = availableBelow >= min(panelSize.height, 180.0) || availableBelow >= availableAbove
        return wantsBelow ? .below : .above
    }

    private func panelOriginScreenBalanced(
        for panelSize: CGSize,
        direction: VerticalDirection,
        safeFrame: CGRect,
        sourceRect: CGRect
    ) -> CGPoint {
        let x = min(max(sourceRect.midX - panelSize.width * 0.5, safeFrame.minX), safeFrame.maxX - panelSize.width)
        let y: CGFloat
        switch direction {
        case .below:
            y = min(sourceRect.maxY + self.configuration.style.sourceSpacing, safeFrame.maxY - panelSize.height)
        case .above:
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

    private func updateNavigationAnchor(for placement: PanelPlacement) {
        let navigationFrame = self.navigationView.frame
        guard !navigationFrame.isEmpty else {
            return
        }

        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let panelFrame = CGRect(origin: placement.panelOrigin, size: placement.panelSize)
        let visibleAnchorX = min(max(sourceRect.midX, panelFrame.minX), panelFrame.maxX)
        let visibleAnchorY: CGFloat
        switch placement.verticalDirection {
        case .below:
            visibleAnchorY = panelFrame.minY
        case .above:
            visibleAnchorY = panelFrame.maxY
        }
        let anchorPoint = CGPoint(
            x: min(max((visibleAnchorX - navigationFrame.minX) / navigationFrame.width, 0.0), 1.0),
            y: min(max((visibleAnchorY - navigationFrame.minY) / navigationFrame.height, 0.0), 1.0)
        )

        guard self.navigationView.layer.anchorPoint != anchorPoint else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.navigationView.layer.anchorPoint = anchorPoint
        self.navigationView.frame = navigationFrame
        CATransaction.commit()
    }

    private func menuPositionDelta() -> CGPoint {
        guard let placement = self.currentPanelPlacement else {
            let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
            let navigationFrame = self.navigationView.frame
            return CGPoint(
                x: sourceRect.midX - navigationFrame.midX,
                y: sourceRect.midY - navigationFrame.midY
            )
        }

        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let panelFrame = CGRect(origin: placement.panelOrigin, size: placement.panelSize)
        let animationSourceSpacing = self.configuration.style.animationSourceSpacing ?? self.configuration.style.sourceSpacing
        let sourcePoint = CGPoint(
            x: min(max(sourceRect.midX, panelFrame.minX), panelFrame.maxX),
            y: placement.verticalDirection == .below
                ? placement.attachmentRect.maxY + animationSourceSpacing
                : placement.attachmentRect.minY - animationSourceSpacing
        )
        let navigationFrame = self.navigationView.frame
        let anchorPoint = self.navigationView.layer.anchorPoint
        let navigationAnchorPosition = CGPoint(
            x: navigationFrame.minX + navigationFrame.width * anchorPoint.x,
            y: navigationFrame.minY + navigationFrame.height * anchorPoint.y
        )
        return CGPoint(
            x: sourcePoint.x - navigationAnchorPosition.x,
            y: sourcePoint.y - navigationAnchorPosition.y
        )
    }

    private func targetBackdropAlpha() -> CGFloat {
        switch self.configuration.backdrop {
        case .none:
            return 0.0
        case let .dimmed(alpha):
            return alpha
        case let .blurred(_, dimAlpha), let .untintedBlur(_, dimAlpha):
            return dimAlpha
        }
    }

    private func animateIn() {
        let delta = self.menuPositionDelta()
        let targetBackdropAlpha = self.targetBackdropAlpha()

        self.navigationView.alpha = 1.0
        self.dimmingView.alpha = targetBackdropAlpha
        self.blurView?.alpha = 1.0
        self.portalView?.alpha = 1.0

        self.navigationView.layer.addContextMenuAlphaAnimation(
            from: 0.0,
            to: 1.0,
            duration: ContextMenuAnimationSupport.appearAlphaDuration
        )
        self.navigationView.layer.addContextMenuSpringAnimation(
            keyPath: "transform.scale",
            from: ContextMenuAnimationSupport.collapsedScale as NSNumber,
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
        self.portalView?.layer.addContextMenuAlphaAnimation(from: 0.0, to: 1.0, duration: 0.2)

        if let accessoryView {
            accessoryView.alpha = 1.0
            accessoryView.layer.addContextMenuAlphaAnimation(
                from: 0.0,
                to: 1.0,
                duration: ContextMenuAnimationSupport.appearAlphaDuration
            )
            accessoryView.layer.addContextMenuSpringAnimation(
                keyPath: "transform.scale",
                from: ContextMenuAnimationSupport.collapsedScale as NSNumber,
                to: 1.0 as NSNumber,
                duration: ContextMenuAnimationSupport.appearDuration,
                damping: ContextMenuAnimationSupport.appearDamping,
                additive: false
            )
        }
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
            to: ContextMenuAnimationSupport.collapsedScale as NSNumber,
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

        self.accessoryView?.layer.addContextMenuAlphaAnimation(
            from: 1.0,
            to: 0.0,
            duration: ContextMenuAnimationSupport.disappearDuration,
            removeOnCompletion: false
        )
        self.accessoryView?.layer.addContextMenuBasicAnimation(
            keyPath: "transform.scale",
            from: 1.0 as NSNumber,
            to: ContextMenuAnimationSupport.collapsedScale as NSNumber,
            duration: ContextMenuAnimationSupport.disappearDuration,
            timingFunction: .easeInEaseOut,
            removeOnCompletion: false
        )
        self.blurView?.layer.addContextMenuAlphaAnimation(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        self.portalView?.layer.addContextMenuAlphaAnimation(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
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
        // VoiceOver returns to the source; a screen that the chosen action presents takes it on afterwards
        if let sourceView = self.appearanceSourceView, sourceView.window != nil,
           let focusTarget = Self.firstAccessibilityElement(in: sourceView) {
            UIAccessibility.post(notification: .screenChanged, argument: focusTarget)
        }
        self.onDidDismiss?()
        completion?()
    }

    /// The view itself when VoiceOver reads it, or the first view inside it that VoiceOver reads, such as a bubble's text
    private static func firstAccessibilityElement(in view: UIView) -> UIView? {
        guard !view.isHidden, !view.accessibilityElementsHidden else {
            return nil
        }
        if view.isAccessibilityElement {
            return view
        }
        return view.subviews.lazy.compactMap { self.firstAccessibilityElement(in: $0) }.first
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

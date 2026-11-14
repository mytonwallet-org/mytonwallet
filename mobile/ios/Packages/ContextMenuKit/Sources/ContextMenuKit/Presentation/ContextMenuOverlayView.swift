import UIKit

@MainActor
final class ContextMenuOverlayView: UIView, ContextMenuNavigationViewDelegate, ContextMenuPresentationSession, UIScrollViewDelegate {
    private static let externalSelectionActivationDistance: CGFloat = 4.0
    private static let panelDismissalSafetyMargin: CGFloat = 8.0
    private static let relocationTravelAnimationKey = "position.y.contextMenuSpring"
    private static let relocationClipDuration: CFTimeInterval = 0.2
    private static let backdropFadeDuration: CFTimeInterval = 0.2

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
    /// The accessory's frame in the overlay's coordinates, which the replica's clip view shares
    private(set) var accessoryFrame: CGRect?
    /// While the menu moves its source's replica: the accessory's frame over the replica in the scrolling content, the
    /// top limit the accessory stays under, and whether it stands there rather than over the replica
    private var relocatedAccessoryFrame: CGRect?
    private var relocationTopLimit: CGFloat = 0.0
    private(set) var isAccessoryPinned = false
    private var hasAnimatedIn = false
    private var isDismissingMenu = false
    private var pendingExternalSelectionPoint: CGPoint?
    private var initialExternalSelectionPoint: CGPoint?
    private var didMoveFromInitialExternalSelectionPoint = false
    private var frozenNavigationFrame: CGRect?
    private var currentPanelPlacement: PanelPlacement?
    private var presentationVerticalDirection: VerticalDirection?
    /// Set when the menu moves its source's replica, which then scrolls with the panel and the accessory
    private var relocation: ContextMenuSourceRelocation?
    private let relocationClipView = UIView()
    let relocationScrollView = UIScrollView()
    private let relocationContentView = UIView()
    /// How far the replica moves from the source: as the first layout places it, and further up while a taller page
    /// of the panel would go past the bottom limit, as a system menu moves its preview up for a taller submenu
    private(set) var relocationOffset: CGFloat?
    /// The offset of the first layout, which the replica comes back to as the panel's page gets shorter again
    private var openingRelocationOffset: CGFloat?
    /// The portal source's frame as the menu opens, which the replica keeps while the menu is open
    private var relocationPortalFrame: CGRect?
    /// Shows the source's parts under the bars while the source is hidden and its replica moves
    private var barsStandIn: ContextMenuSourceBarsStandIn?
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

    var onWillDismiss: (() -> Void)?
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

        if !self.configuration.preservesSourceAppearance, self.configuration.sourceRelocation != nil,
           let portalSourceView {
            self.barsStandIn = ContextMenuSourceBarsStandIn(
                source: portalSourceView,
                sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection,
                appliesRightToLeftTransformCorrection: self.portalAppliesRightToLeftTransformCorrection
            )
        }
        if !self.configuration.preservesSourceAppearance,
           let portalSourceView,
           let portalView = ContextMenuPortalView(
               sourceView: portalSourceView,
               sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection,
               appliesRightToLeftTransformCorrection: self.portalAppliesRightToLeftTransformCorrection
           ) {
            portalView.alpha = 0.0
            self.portalView = portalView
            if let sourceRelocation = self.configuration.sourceRelocation {
                // The replica hides the source while it shows it, so it can move away without leaving the source behind
                portalView.detachFromSourcePosition()
                portalView.setSourceViewHidden(true)
                self.relocation = sourceRelocation
                self.setupRelocationViews()
            }
            self.contentHostView.addSubview(portalView)
        }

        self.navigationView.alpha = 0.0
        self.contentHostView.addSubview(self.navigationView)

        if let accessory = self.configuration.accessory {
            let accessoryContext = ContextMenuAccessoryContext(
                dismissHandler: { [weak self] completion in
                    guard let self else {
                        completion?()
                        return
                    }
                    guard let completion else {
                        self.dismissMenu()
                        return
                    }
                    self.dismissMenu { completion() }
                },
                sourceFrameHandler: { [weak self] rect in
                    self?.getReplicaFrameOnScreen(of: rect)
                }
            )
            let accessoryView = ContextMenuAccessoryView(
                capsules: accessory.backgroundCapsules,
                tailCapsuleIndices: Set(accessory.tail?.capsuleIndices ?? []),
                designSize: accessory.size,
                motion: accessory.motion,
                contentView: accessory.makeContentView(accessoryContext),
                glassTint: accessory.glassTint ?? self.configuration.style.glassTint,
                shadow: accessory.shadow,
                isGlassInteractive: accessory.isGlassInteractive,
                sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection
            )
            accessoryView.alpha = 0.0
            // Over the scrolling replica rather than in it, so that over a long source it can stay in reach while the
            // replica scrolls; the replica's clip covers both as the menu opens and closes
            (self.relocation == nil ? self : self.relocationClipView).addSubview(accessoryView)
            self.accessoryView = accessoryView
        }

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleOutsideTap(_:)))
        tapGestureRecognizer.cancelsTouchesInView = false
        self.addGestureRecognizer(tapGestureRecognizer)

        // VoiceOver stays inside the open menu, as with the system context menu, and skips the source's mirror
        self.accessibilityViewIsModal = true
        self.portalView?.accessibilityElementsHidden = true
    }

    /// The view that holds the replica, the panel and the accessory: a scrolling one while the menu moves the replica
    private var contentHostView: UIView {
        self.relocation == nil ? self : self.relocationContentView
    }

    private func setupRelocationViews() {
        self.relocationClipView.frame = self.bounds
        self.relocationClipView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.relocationScrollView.frame = self.relocationClipView.bounds
        self.relocationScrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.relocationScrollView.backgroundColor = .clear
        self.relocationScrollView.showsVerticalScrollIndicator = false
        self.relocationScrollView.showsHorizontalScrollIndicator = false
        self.relocationScrollView.contentInsetAdjustmentBehavior = .never
        self.relocationScrollView.delaysContentTouches = false
        self.relocationScrollView.isScrollEnabled = false
        self.relocationScrollView.delegate = self
        if #available(iOS 26.0, *) {
            self.relocationScrollView.topEdgeEffect.isHidden = true
            self.relocationScrollView.bottomEdgeEffect.isHidden = true
        }
        self.addSubview(self.relocationClipView)
        self.relocationClipView.addSubview(self.relocationScrollView)
        self.relocationScrollView.addSubview(self.relocationContentView)
    }

    override func accessibilityPerformEscape() -> Bool {
        self.dismissMenu()
        return true
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if self.superview == nil {
            self.barsStandIn?.removeFromSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateBackdropMask()
        self.layoutMenu()
        self.layoutPortalView()
    }

    func activatePresentationIfNeeded() {
        guard self.window != nil, !self.hasAnimatedIn else {
            return
        }
        self.hasAnimatedIn = true

        self.layoutMenu()
        self.layoutPortalView()
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
        guard #available(iOS 17.0, *), self.configuration.userInterfaceStyle == nil, let appearanceSourceView else {
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
        let contentPoint = self.relocation == nil ? point : self.relocationContentView.convert(point, from: self)
        let isInsidePanel = panelFrame
            .insetBy(dx: -Self.panelDismissalSafetyMargin, dy: -Self.panelDismissalSafetyMargin)
            .contains(contentPoint)
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
        if let relocation {
            self.layoutRelocatedMenu(relocation)
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
            let accessoryPlacement = self.getAccessoryPlacement(for: accessory, in: safeFrame)
            let accessoryFrame = accessoryPlacement.frame
            accessoryView.apply(accessoryPlacement)
            accessoryView.frame = accessoryFrame
            self.accessoryFrame = accessoryFrame
            placement = self.panelPlacement(in: safeFrame, clearOf: accessoryFrame)
        } else {
            placement = self.panelPlacement(in: safeFrame)
        }
        self.applyPanelPlacement(placement)
    }

    private func applyPanelPlacement(_ placement: PanelPlacement) {
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

    /// Lays out the replica, its accessory and the panel below them in the scrolling content, whose coordinates match
    /// the overlay's while it is not scrolled. The panel keeps its usual attachment, width and alignment.
    private func layoutRelocatedMenu(_ relocation: ContextMenuSourceRelocation) {
        let style = self.configuration.style
        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        let horizontalFrame = self.bounds.inset(by: UIEdgeInsets(
            top: 0.0,
            left: style.screenInsets.left,
            bottom: 0.0,
            right: style.screenInsets.right
        ))
        let topLimit = self.safeAreaInsets.top + relocation.topInset
        let bottomLimit = self.bounds.maxY - self.safeAreaInsets.bottom - relocation.bottomInset
        let panelSize = self.navigationView.preferredPanelSize(constrainedTo: CGSize(
            width: min(style.maxWidth, horizontalFrame.width),
            height: max(1.0, bottomLimit - topLimit)
        ))
        let sourceAccessoryPlacement = self.configuration.accessory.map {
            self.getRelocatedAccessoryPlacement(for: $0, sourceRect: sourceRect)
        }
        let sourceAccessoryFrame = sourceAccessoryPlacement?.frame
        let attachmentRect = sourceAccessoryFrame.map { sourceRect.union($0) } ?? sourceRect
        let isFirstLayout = self.relocationOffset == nil
        let fittingOffset = Self.getMinimalRelocationOffset(
            attachmentRect: attachmentRect,
            panelHeight: panelSize.height,
            sourceSpacing: style.sourceSpacing,
            topLimit: topLimit,
            bottomLimit: bottomLimit
        )
        let openingOffset = self.openingRelocationOffset ?? fittingOffset
        self.openingRelocationOffset = openingOffset
        let offset = min(openingOffset, fittingOffset)
        self.relocationOffset = offset
        // The replica moves with the panel in the page transition's animation
        if !isFirstLayout, let portalView, let portalSourceView {
            self.layoutRelocatedPortalView(portalView, sourceView: portalSourceView)
        }

        let relocatedSourceRect = sourceRect.offsetBy(dx: 0.0, dy: offset)
        let relocatedAttachmentRect = attachmentRect.offsetBy(dx: 0.0, dy: offset)
        if let accessoryView, let sourceAccessoryPlacement {
            accessoryView.apply(sourceAccessoryPlacement)
            self.relocatedAccessoryFrame = sourceAccessoryPlacement.frame.offsetBy(dx: 0.0, dy: offset)
        }
        self.relocationTopLimit = topLimit
        let placement = PanelPlacement(
            panelSize: panelSize,
            panelOrigin: CGPoint(
                x: self.getPanelOriginX(for: panelSize, safeFrame: horizontalFrame, sourceRect: relocatedSourceRect),
                y: relocatedAttachmentRect.maxY + style.sourceSpacing
            ),
            verticalDirection: .below,
            attachmentRect: relocatedAttachmentRect
        )
        self.applyPanelPlacement(placement)

        let contentHeight = placement.panelOrigin.y + panelSize.height + relocation.bottomInset + self.safeAreaInsets.bottom
        let isScrollable = contentHeight > self.bounds.height + 0.5
        self.relocationClipView.frame = self.bounds
        self.relocationScrollView.frame = self.relocationClipView.bounds
        self.relocationContentView.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: self.bounds.width,
            height: max(self.bounds.height, contentHeight)
        )
        self.relocationScrollView.contentSize = self.relocationContentView.bounds.size
        self.relocationScrollView.isScrollEnabled = isScrollable
        self.relocationScrollView.alwaysBounceVertical = isScrollable
        if isFirstLayout {
            // A replica and panel taller than the screen open scrolled to the panel
            self.relocationScrollView.contentOffset = CGPoint(x: 0.0, y: max(0.0, contentHeight - self.bounds.height))
        }
        self.layoutRelocatedAccessory()
    }

    /// The accessory rides over the replica, and once the replica scrolls up past the top limit it stays at the
    /// limit, in reach, with the replica scrolling under it, as Telegram's reactions do over a long message
    private func layoutRelocatedAccessory() {
        guard let accessoryView, let relocatedAccessoryFrame else {
            return
        }
        let ridingFrame = relocatedAccessoryFrame.offsetBy(dx: 0.0, dy: -self.relocationScrollView.contentOffset.y)
        let frame = Self.getPinnedAccessoryFrame(ridingFrame, topLimit: self.relocationTopLimit)
        self.isAccessoryPinned = frame.minY > ridingFrame.minY + 0.5
        if accessoryView.frame != frame {
            accessoryView.frame = frame
        }
        self.accessoryFrame = frame
    }

    /// `ridingFrame`, the accessory's frame over the replica as it scrolls, kept from going above `topLimit`
    static func getPinnedAccessoryFrame(_ ridingFrame: CGRect, topLimit: CGFloat) -> CGRect {
        var frame = ridingFrame
        frame.origin.y = max(topLimit, ridingFrame.minY)
        return frame
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.relocationScrollView else {
            return
        }
        self.layoutRelocatedAccessory()
    }

    /// The offset that moves a source's attachment rect, and the panel `sourceSpacing` below it, between `topLimit` and
    /// `bottomLimit` as little as possible; a pair taller than that starts at `topLimit`
    static func getMinimalRelocationOffset(
        attachmentRect: CGRect,
        panelHeight: CGFloat,
        sourceSpacing: CGFloat,
        topLimit: CGFloat,
        bottomLimit: CGFloat
    ) -> CGFloat {
        var minY = max(attachmentRect.minY, topLimit)
        let combinedHeight = attachmentRect.height + sourceSpacing + panelHeight
        if minY + combinedHeight > bottomLimit {
            minY = bottomLimit - combinedHeight
        }
        minY = max(minY, topLimit)
        return minY - attachmentRect.minY
    }

    /// The accessory over the source's top trailing corner, kept inside the screen insets and the safe area horizontally;
    /// vertically it moves with the replica
    private func getRelocatedAccessoryPlacement(
        for accessory: ContextMenuAccessory,
        sourceRect: CGRect
    ) -> ContextMenuAccessoryPlacement {
        accessory.getPlacement(
            sourceRect: sourceRect,
            minX: self.safeAreaInsets.left,
            maxX: self.bounds.maxX - self.safeAreaInsets.right,
            screenInsets: self.configuration.style.screenInsets,
            isRightToLeft: self.sourceUserInterfaceLayoutDirection.contextMenuIsRightToLeft
        )
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
                x: self.getPanelOriginX(for: panelSize, safeFrame: safeFrame, sourceRect: sourceRect),
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
        let x = self.getPanelOriginX(for: panelSize, safeFrame: safeFrame, sourceRect: sourceRect)
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

    private func getAccessoryPlacement(
        for accessory: ContextMenuAccessory,
        in safeFrame: CGRect
    ) -> ContextMenuAccessoryPlacement {
        let sourceRect = self.convert(self.sourceRectInWindow, from: nil)
        var placement = self.getRelocatedAccessoryPlacement(for: accessory, sourceRect: sourceRect)
        placement.frame.origin.y = min(max(placement.frame.minY, safeFrame.minY), safeFrame.maxY - placement.frame.height)
        return placement
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

    private func getPanelOriginX(for panelSize: CGSize, safeFrame: CGRect, sourceRect: CGRect) -> CGFloat {
        let isRightToLeft = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let x: CGFloat
        switch self.configuration.style.horizontalAlignment {
        case .center:
            x = sourceRect.midX - panelSize.width * 0.5
        case .leading:
            x = isRightToLeft ? sourceRect.maxX - panelSize.width : sourceRect.minX
        case .trailing:
            x = isRightToLeft ? sourceRect.minX : sourceRect.maxX - panelSize.width
        }
        return min(max(x, safeFrame.minX), safeFrame.maxX - panelSize.width)
    }

    private func panelOriginScreenBalanced(
        for panelSize: CGSize,
        direction: VerticalDirection,
        safeFrame: CGRect,
        sourceRect: CGRect
    ) -> CGPoint {
        let x = self.getPanelOriginX(for: panelSize, safeFrame: safeFrame, sourceRect: sourceRect)
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
        let x = self.getPanelOriginX(for: panelSize, safeFrame: safeFrame, sourceRect: sourceRect)
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
        if self.relocation != nil {
            self.animateRelocationIn()
        } else {
            self.portalView?.layer.addContextMenuAlphaAnimation(from: 0.0, to: 1.0, duration: 0.2)
        }

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

        if let accessoryView {
            accessoryView.alpha = 1.0
            guard accessoryView.motion == .scale else {
                accessoryView.animateThoughtBubbleIn()
                return
            }
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

    func dismiss() {
        self.dismissMenu()
    }

    private func dismissMenu(completion: (() -> Void)? = nil) {
        guard !self.isDismissingMenu else {
            return
        }

        self.isDismissingMenu = true
        let onWillDismiss = self.onWillDismiss
        self.onWillDismiss = nil
        onWillDismiss?()
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

        if let accessoryView, accessoryView.motion == .thoughtBubble {
            accessoryView.animateThoughtBubbleOut()
        } else {
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
        }
        self.blurView?.layer.addContextMenuAlphaAnimation(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        if self.relocation != nil {
            self.animateRelocationOut()
        } else {
            self.portalView?.layer.addContextMenuAlphaAnimation(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        }
        self.dimmingView.layer.addContextMenuAlphaAnimation(
            from: self.targetBackdropAlpha(),
            to: 0.0,
            duration: 0.2,
            removeOnCompletion: false
        )
        CATransaction.commit()
    }

    /// The replica stands in for the hidden source from the first frame and travels to its place on Telegram's spring,
    /// while the clip around it grows from the source's visible area to the screen
    private func animateRelocationIn() {
        guard let relocationOffset else {
            return
        }
        let travel = relocationOffset - self.relocationScrollView.contentOffset.y
        if self.isSourceBehindBars {
            let isReplicaOnSource = abs(travel) <= 0.5
            self.showSourceUnderBars(isReplicaOnSource: isReplicaOnSource)
            if !isReplicaOnSource {
                self.barsStandIn?.followReplica(from: 0.0, to: travel) { layer, from, to in
                    layer.addContextMenuSpringAnimation(
                        keyPath: "position.y",
                        from: from as NSNumber,
                        to: to as NSNumber,
                        duration: ContextMenuAnimationSupport.appearDuration,
                        damping: ContextMenuAnimationSupport.appearDamping,
                        additive: true
                    )
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.backdropFadeDuration) { [weak self] in
                guard let self, !self.isDismissingMenu else {
                    return
                }
                self.portalView?.setSourceViewHidden(true)
                self.barsStandIn?.removeFromSuperview()
            }
        }
        if abs(travel) > 0.5 {
            // An accessory over the replica travels with it, while one kept at the top limit grows in place
            let travellingLayers = [self.relocationContentView.layer]
                + (self.isAccessoryPinned ? [] : self.accessoryView.map { [$0.layer] } ?? [])
            for layer in travellingLayers {
                layer.addContextMenuSpringAnimation(
                    keyPath: "position.y",
                    from: -travel as NSNumber,
                    to: 0.0 as NSNumber,
                    duration: ContextMenuAnimationSupport.appearDuration,
                    damping: ContextMenuAnimationSupport.appearDamping,
                    additive: true
                )
            }
        }
        if let relocationContentArea {
            self.animateRelocationClip(
                from: relocationContentArea,
                to: self.relocationClipView.bounds,
                shouldRemoveMaskOnCompletion: true
            )
        }
    }

    /// Where `rect`, in the portal source's coordinates, shows on the replica at the moment, in the window's coordinates
    private func getReplicaFrameOnScreen(of rect: CGRect) -> CGRect? {
        guard let portalView, let window = portalView.window else {
            return nil
        }
        let layer = portalView.layer.presentation() ?? portalView.layer
        let rootLayer = window.layer.presentation() ?? window.layer
        return layer.convert(rect, to: rootLayer)
    }

    /// The replica travels back from where it shows, including a scroll or an unfinished arrival, onto the source, which
    /// shows again as the overlay goes. A source that left the screen fades out instead.
    private func animateRelocationOut() {
        self.relocationScrollView.setContentOffset(self.relocationScrollView.contentOffset, animated: false)
        let contentLayer = self.relocationContentView.layer
        let currentTravel = (contentLayer.presentation()?.position.y ?? contentLayer.position.y) - contentLayer.position.y
        contentLayer.removeAnimation(forKey: Self.relocationTravelAnimationKey)
        if let portalView, let portalSourceView, portalSourceView.window != nil {
            let replicaFrame = portalView.convert(portalView.bounds, to: self)
            let sourceFrame = portalSourceView.convert(portalSourceView.bounds, to: self)
            let returnTravel = sourceFrame.minY - replicaFrame.minY
            if self.isSourceBehindBars {
                let isReplicaOnSource = abs(returnTravel - currentTravel) <= 0.5
                self.showSourceUnderBars(isReplicaOnSource: isReplicaOnSource)
                if !isReplicaOnSource {
                    self.barsStandIn?.followReplica(from: currentTravel - returnTravel, to: 0.0) { layer, from, to in
                        layer.addContextMenuBasicAnimation(
                            keyPath: "position.y",
                            from: from as NSNumber,
                            to: to as NSNumber,
                            duration: ContextMenuAnimationSupport.disappearDuration,
                            timingFunction: .easeInEaseOut,
                            additive: true,
                            removeOnCompletion: false
                        )
                    }
                }
            }
            contentLayer.addContextMenuBasicAnimation(
                keyPath: "position.y",
                from: currentTravel as NSNumber,
                to: returnTravel as NSNumber,
                duration: ContextMenuAnimationSupport.disappearDuration,
                timingFunction: .easeInEaseOut,
                additive: true,
                removeOnCompletion: false
            )
            // An accessory over the replica goes back with it, while one kept at the top limit goes in place
            if let accessoryLayer = self.accessoryView?.layer, !self.isAccessoryPinned {
                let accessoryTravel = (accessoryLayer.presentation()?.position.y ?? accessoryLayer.position.y)
                    - accessoryLayer.position.y
                accessoryLayer.removeAnimation(forKey: Self.relocationTravelAnimationKey)
                accessoryLayer.addContextMenuBasicAnimation(
                    keyPath: "position.y",
                    from: accessoryTravel as NSNumber,
                    to: returnTravel as NSNumber,
                    duration: ContextMenuAnimationSupport.disappearDuration,
                    timingFunction: .easeInEaseOut,
                    additive: true,
                    removeOnCompletion: false
                )
            }
        } else {
            self.portalView?.layer.addContextMenuAlphaAnimation(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        }
        if let relocationContentArea {
            self.animateRelocationClip(
                from: self.relocationClipView.bounds,
                to: relocationContentArea,
                shouldRemoveMaskOnCompletion: false
            )
        }
    }

    /// Keeps what the bars show of a source behind them while the menu's backdrop isn't over them. A source under a
    /// replica that stays on it shows. One whose replica moves away stays hidden, so it never shows beside the replica in
    /// the content area, and a copy of its parts outside that area stands in for it under the bars, moving with the
    /// replica.
    private func showSourceUnderBars(isReplicaOnSource: Bool) {
        if isReplicaOnSource {
            self.portalView?.setSourceViewHidden(false)
        } else if let barsStandIn, let portalSourceView, let superview = portalSourceView.superview,
                  let relocationContentArea {
            barsStandIn.show(over: portalSourceView, clearOf: superview.convert(relocationContentArea, from: self))
        }
    }

    /// The source reaches under the header or the bottom bar around the content area, where it shows through the bars'
    /// own blur. Hiding it at once would change the bars' backdrop in a blink, so the bars keep showing it until the
    /// menu's backdrop covers them, and again as the menu starts to go.
    private var isSourceBehindBars: Bool {
        guard let contentArea = self.relocationContentArea, let portalSourceView, portalSourceView.window != nil else {
            return false
        }
        let sourceFrame = portalSourceView.convert(portalSourceView.bounds, to: self)
        return !contentArea.insetBy(dx: -0.5, dy: -0.5).contains(sourceFrame)
    }

    /// `relocation.contentAreaInWindow` in the overlay's coordinates
    private var relocationContentArea: CGRect? {
        guard let contentAreaInWindow = self.relocation?.contentAreaInWindow else {
            return nil
        }
        let contentArea = self.convert(contentAreaInWindow, from: nil).intersection(self.bounds)
        return contentArea.isNull || contentArea.isEmpty ? nil : contentArea
    }

    private func animateRelocationClip(from fromRect: CGRect, to toRect: CGRect, shouldRemoveMaskOnCompletion: Bool) {
        let maskLayer = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.backgroundColor = UIColor.black.cgColor
        maskLayer.frame = toRect
        self.relocationClipView.layer.mask = maskLayer
        CATransaction.commit()

        CATransaction.begin()
        if shouldRemoveMaskOnCompletion {
            CATransaction.setCompletionBlock { [weak self, weak maskLayer] in
                guard let self, let maskLayer, self.relocationClipView.layer.mask === maskLayer else {
                    return
                }
                self.relocationClipView.layer.mask = nil
            }
        }
        maskLayer.addContextMenuBasicAnimation(
            keyPath: "bounds",
            from: NSValue(cgRect: CGRect(origin: .zero, size: fromRect.size)),
            to: NSValue(cgRect: CGRect(origin: .zero, size: toRect.size)),
            duration: Self.relocationClipDuration,
            timingFunction: .easeInEaseOut
        )
        maskLayer.addContextMenuBasicAnimation(
            keyPath: "position",
            from: NSValue(cgPoint: CGPoint(x: fromRect.midX, y: fromRect.midY)),
            to: NSValue(cgPoint: CGPoint(x: toRect.midX, y: toRect.midY)),
            duration: Self.relocationClipDuration,
            timingFunction: .easeInEaseOut
        )
        CATransaction.commit()
    }

    private func removeFromPresentationHost(completion: (() -> Void)? = nil) {
        if self.relocation != nil {
            self.portalView?.setSourceViewHidden(false)
        }
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
        if self.relocation != nil {
            self.layoutRelocatedPortalView(portalView, sourceView: portalSourceView)
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

    /// The replica keeps the source's frame from when the menu opened, moved by `relocationOffset` in the scrolling
    /// content
    private func layoutRelocatedPortalView(_ portalView: ContextMenuPortalView, sourceView: UIView) {
        guard let relocationOffset else {
            return
        }
        let sourceFrame = self.relocationPortalFrame ?? sourceView.convert(sourceView.bounds, to: self)
        self.relocationPortalFrame = sourceFrame
        portalView.frame = sourceFrame.offsetBy(dx: 0.0, dy: relocationOffset)
        if let portalMaskRectInWindow, let portalMask {
            let maskRect = self.convert(portalMaskRectInWindow, from: nil)
                .offsetBy(dx: -sourceFrame.minX, dy: -sourceFrame.minY)
            portalView.updateMask(portalMask, rect: maskRect)
        } else {
            portalView.updateMask(nil, rect: nil)
        }
    }

    private func updateBackdropMask() {
        // A moving replica leaves its source's place, so the backdrop has no cutout
        guard let portalSourceView, self.relocation == nil else {
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

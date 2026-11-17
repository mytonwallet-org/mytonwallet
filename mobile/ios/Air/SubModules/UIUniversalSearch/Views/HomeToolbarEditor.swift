import UIComponents
import UIKit
import WalletContext

@MainActor
public protocol HomeToolbarEditorHost: AnyObject {
    /// The stored configuration, which a drag changes
    var toolbarEditorConfiguration: HomeToolbarConfiguration { get }
    /// What the toolbar shows for a stored configuration, such as less the actions the account cannot use
    func getToolbarEditorDisplayedConfiguration(_ configuration: HomeToolbarConfiguration) -> HomeToolbarConfiguration
    func commitToolbarEditorConfiguration(_ configuration: HomeToolbarConfiguration)
    /// Whether the toolbar can be rearranged now
    var canEditToolbar: Bool { get }
    /// The view that dims the screen under the toolbar while it is rearranged, and the view it goes below
    var toolbarEditorDimmingAnchor: (container: UIView, sibling: UIView)? { get }
    /// The screen under the toolbar dims and brightens back. Whatever the host floats over that screen above the
    /// dimming steps aside meanwhile.
    func setToolbarEditorDimmed(_ isDimmed: Bool)
    /// The account button's place on a side of the top bar, in window coordinates, where the top bar can show it
    func getTopAccountFrame(isAtStart: Bool) -> CGRect?
    /// Hides the top bar's account button while its copy is dragged or lands
    func setTopAccountHeld(_ isHeld: Bool)
    /// While the account button is dragged the top bar keeps room for it at both ends, where it can drop
    func setTopAccountDragActive(_ isActive: Bool)
    /// Whether a hold on an account button also opens its menu. The button then lifts only once the finger moves
    /// sideways, away from the menu.
    var opensMenuOnAccountsHold: Bool { get }
    var toolbarEditorShelf: (any HomeToolbarEditorShelf)? { get }
    /// A hold on the account button that opened its menu is turning into a drag
    func toolbarEditorWillLiftAccounts()
}

/// Where the buttons the toolbar does not show are kept beside it, such as a grid of them in settings. A button
/// dragged off the toolbar drops there instead of on a Remove target, and the shelf shows the place it would take.
@MainActor
public protocol HomeToolbarEditorShelf: AnyObject {
    /// `item` is being dragged. The shelf keeps a place for it while a drop would leave it there, and closes the place
    /// while the toolbar would take it.
    func setDraggedItem(_ item: HomeToolbarItem, staysOnShelf: Bool)
    /// Where the dragged copy of `item` lands, in window coordinates. Without a place of its own to show, the item
    /// is absorbed into the frame.
    func getLandingFrame(for item: HomeToolbarItem) -> (frame: CGRect, isAbsorbed: Bool)
    /// The drag is over and the dragged copy is gone
    func endDrag()
}

public extension HomeToolbarEditorHost {
    var toolbarEditorShelf: (any HomeToolbarEditorShelf)? { nil }
    var toolbarEditorDimmingAnchor: (container: UIView, sibling: UIView)? { nil }
    func setToolbarEditorDimmed(_ isDimmed: Bool) {}
    func getTopAccountFrame(isAtStart: Bool) -> CGRect? { nil }
    func setTopAccountHeld(_ isHeld: Bool) {}
    func setTopAccountDragActive(_ isActive: Bool) {}
    var opensMenuOnAccountsHold: Bool { false }
    func toolbarEditorWillLiftAccounts() {}
}

/// Rearranges the home toolbar by dragging: a held button lifts off the toolbar as a piece of glass, the others
/// wiggle and make room where it would drop, and dropping it away from the toolbar removes it. An action lifted out
/// of the actions menu, and the account button lifted off the top bar, drop onto the toolbar the same way.
@MainActor
public final class HomeToolbarEditor: NSObject, UIGestureRecognizerDelegate {
    private enum Origin {
        case toolbar
        case topBar
        case external
    }

    private struct Session {
        var item: HomeToolbarItem
        var origin: Origin
        /// A hold that also opened a menu waits for the finger to move before it lifts the button
        var isPending: Bool
        var startPoint: CGPoint
        var touchOffset = CGPoint.zero
        /// When the dragged glass began to slide under the finger, for a drag that took it by its edge
        var touchOffsetEaseStart: CFTimeInterval?
        var isInside: Bool
        var isTopAtStart = false
        /// Over a toolbar that has no room for the item
        var isRefused = false
        /// A drop now would leave the item on the host's shelf
        var staysOnShelf = false
    }

    public weak var host: (any HomeToolbarEditorHost)?
    /// Lifts the toolbar's buttons. Add it to a view that contains the toolbar.
    public let holdRecognizer = UILongPressGestureRecognizer()
    /// Whether the field and the actions button can be dragged too. They cannot where a hold on them means something
    /// else.
    public var dragsFixedItems = false
    public var isDragging: Bool { session != nil }

    private let toolbar: UniversalSearchFieldView
    private var session: Session?
    private var overlay: HomeToolbarEditOverlayView?
    private var dimmingView: UIView?
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private static let pendingSlop: CGFloat = 10
    private static let toolbarZoneMargin: CGFloat = 40
    private static let touchOffsetEaseDuration: CFTimeInterval = 0.25

    public init(toolbar: UniversalSearchFieldView, host: any HomeToolbarEditorHost) {
        self.toolbar = toolbar
        self.host = host
        super.init()
        holdRecognizer.minimumPressDuration = 0.4
        holdRecognizer.delegate = self
        holdRecognizer.addTarget(self, action: #selector(handleHold(_:)))
        toolbar.onHomeEditInterruption = { [weak self] in self?.cancel() }
    }

    // MARK: - Starting a drag

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            guard let item = toolbar.getHomeItem(at: recognizer.location(in: toolbar)),
                  let frame = getToolbarItemFrame(item) else { return }
            // Where the account button's menu opens under the same hold, the drag waits to see where the finger goes
            let isPending = item == .accounts && host?.opensMenuOnAccountsHold == true
            session = Session(item: item, origin: .toolbar, isPending: isPending, startPoint: point, isInside: true)
            session?.touchOffset = CGPoint(x: frame.midX - point.x, y: frame.midY - point.y)
            if !isPending { lift(from: frame) }
        case .changed:
            moveDrag(to: point)
        case .ended:
            endDrag(at: point)
        default:
            cancel()
        }
    }

    /// Follows a hold on the top bar's account button. Forward every state of the hold's recognizer.
    public func handleTopAccountHold(_ recognizer: UIGestureRecognizer, isAtStart: Bool) {
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            guard session == nil, host?.canEditToolbar == true,
                  let frame = host?.getTopAccountFrame(isAtStart: isAtStart) else { return }
            let isPending = host?.opensMenuOnAccountsHold == true
            session = Session(item: .accounts, origin: .topBar, isPending: isPending, startPoint: point, isInside: false)
            session?.isTopAtStart = isAtStart
            session?.touchOffset = CGPoint(x: frame.midX - point.x, y: frame.midY - point.y)
            if !isPending { lift(from: frame) }
        case .changed:
            moveDrag(to: point)
        case .ended:
            endDrag(at: point)
        default:
            cancel()
        }
    }

    /// Takes over an item that is already being dragged elsewhere, such as an action out of the actions menu.
    /// `standIn` shows the item as it looked there, at `frame` in window coordinates; it turns into the toolbar's
    /// glass. The caller reports the finger with `moveDrag` and `endDrag`.
    @discardableResult
    public func beginExternalDrag(item: HomeToolbarItem, standIn: UIView, frame: CGRect, touch: CGPoint) -> Bool {
        guard session == nil, host?.canEditToolbar == true, let window = toolbar.window else { return false }
        session = Session(item: item, origin: .external, isPending: false, startPoint: touch, isInside: false)
        session?.touchOffset = CGPoint(x: frame.midX - touch.x, y: frame.midY - touch.y)
        let overlay = makeOverlay(in: window)
        overlay.showPlatter(content: toolbar.makeHomeItemContentCopy(item), standIn: standIn, frame: frame)
        // The finger ends up carrying the glass by its middle
        session?.touchOffsetEaseStart = CACurrentMediaTime()
        if usesShelf(for: item) {
            session?.staysOnShelf = true
            host?.toolbarEditorShelf?.setDraggedItem(item, staysOnShelf: true)
        }
        beginEdit(reservesSlot: false)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return true
    }

    private func lift(from frame: CGRect) {
        guard let session, let window = toolbar.window else { return }
        let overlay = makeOverlay(in: window)
        overlay.showPlatter(content: toolbar.makeHomeItemContentCopy(session.item), standIn: nil, frame: frame)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selectionFeedback.prepare()
        beginEdit(reservesSlot: session.origin == .toolbar)
        let topFrames = session.item == .accounts ? getTopAccountFrames() : nil
        if session.origin == .topBar || topFrames != nil {
            host?.setTopAccountHeld(true)
        }
        if let topFrames {
            host?.setTopAccountDragActive(true)
            overlay.showTopTargets(start: topFrames.start, end: topFrames.end)
            overlay.highlightTopTarget(session.isInside ? nil : session.isTopAtStart)
        } else if session.item.isHideable, session.origin == .toolbar, !usesShelf(for: session.item) {
            overlay.showRemoveTarget(above: toolbar.convert(toolbar.bounds, to: nil))
        }
    }

    /// Whether `item` goes to the host's shelf when it is not on the toolbar. The account button goes to the top bar.
    private func usesShelf(for item: HomeToolbarItem) -> Bool {
        host?.toolbarEditorShelf != nil && item.isHideable && item != .accounts
    }

    private func beginEdit(reservesSlot: Bool) {
        guard let session else { return }
        toolbar.setHomeEdit(
            HomeToolbarEdit(item: session.item, order: toolbar.homeConfiguration.order, reservesSlot: reservesSlot),
            animated: true
        )
        showDimming()
    }

    // MARK: - Following the finger

    public func moveDrag(to point: CGPoint) {
        guard var session else { return }
        if session.isPending {
            let dx = point.x - session.startPoint.x
            let dy = point.y - session.startPoint.y
            guard hypot(dx, dy) >= Self.pendingSlop else { return }
            // A finger that heads for the menu picks from it
            if abs(dy) > abs(dx), session.origin == .toolbar ? dy < 0 : dy > 0 {
                self.session = nil
                return
            }
            session.isPending = false
            self.session = session
            host?.toolbarEditorWillLiftAccounts()
            let frame = session.origin == .topBar
                ? host?.getTopAccountFrame(isAtStart: session.isTopAtStart)
                : getToolbarItemFrame(session.item)
            guard let frame else {
                self.session = nil
                return
            }
            lift(from: frame)
        }
        guard let overlay else { return }
        var offset = session.touchOffset
        if let start = session.touchOffsetEaseStart {
            let remaining = max(0, 1 - (CACurrentMediaTime() - start) / Self.touchOffsetEaseDuration)
            offset = CGPoint(x: offset.x * remaining, y: offset.y * remaining)
        }
        overlay.movePlatter(to: CGPoint(x: point.x + offset.x, y: point.y + offset.y))
        let center = overlay.platterCenter
        let isInside = isInsideToolbarZone(center)
        let canHold = canToolbarHold(session)
        var edit = toolbar.homeEdit ?? HomeToolbarEdit(item: session.item, order: toolbar.homeConfiguration.order, reservesSlot: false)
        if isInside, canHold {
            edit.order = toolbar.getHomeOrder(moving: session.item, toward: toolbar.convert(center, from: nil).x)
            edit.reservesSlot = true
        } else {
            // The field and the actions button have nowhere else to go
            edit.reservesSlot = !session.item.isHideable
        }
        let isRefused = isInside && !canHold
        if isRefused != session.isRefused {
            session.isRefused = isRefused
            overlay.setFullHintShown(isRefused, above: toolbar.convert(toolbar.bounds, to: nil))
            if isRefused { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        }
        var hasChanged = false
        if edit != toolbar.homeEdit {
            toolbar.setHomeEdit(edit, animated: true)
            hasChanged = toolbar.homeEdit == edit
        }
        let staysOnShelf = usesShelf(for: session.item) && !(isInside && canHold)
        if staysOnShelf != session.staysOnShelf {
            session.staysOnShelf = staysOnShelf
            host?.toolbarEditorShelf?.setDraggedItem(session.item, staysOnShelf: staysOnShelf)
            hasChanged = true
        }
        if overlay.hasTopTargets {
            let isAtStart = (center.x < overlay.bounds.midX) != (toolbar.effectiveUserInterfaceLayoutDirection == .rightToLeft)
            if isInside != session.isInside || isAtStart != session.isTopAtStart {
                session.isTopAtStart = isAtStart
                overlay.highlightTopTarget(isInside ? nil : isAtStart)
                hasChanged = true
            }
        } else if isInside != session.isInside {
            overlay.highlightRemoveTarget(!isInside)
            hasChanged = hasChanged || overlay.hasRemoveTarget
        }
        session.isInside = isInside
        self.session = session
        if hasChanged {
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
        }
    }

    // MARK: - Dropping

    public func endDrag(at point: CGPoint) {
        moveDrag(to: point)
        guard let session else { return }
        self.session = nil
        guard !session.isPending, let overlay, let host else {
            cancel()
            return
        }
        let center = overlay.platterCenter
        let isInside = isInsideToolbarZone(center)
        let canHold = canToolbarHold(session)
        var configuration = host.toolbarEditorConfiguration
        let topFrame = overlay.hasTopTargets && !(isInside && canHold)
            ? host.getTopAccountFrame(isAtStart: session.isTopAtStart)
            : nil
        if let topFrame {
            if isInside { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            configuration.setShown(false, .accounts)
            configuration.isAccountsAtStart = session.isTopAtStart
            finishEdit(with: configuration)
            overlay.finish(.land(topFrame)) { [weak self] in
                self?.host?.setTopAccountHeld(false)
            }
        } else if isInside, canHold {
            configuration.order = toolbar.homeEdit?.order ?? configuration.order
            configuration.setShown(true, session.item)
            finishEdit(with: configuration, landingItem: session.item)
            host.setTopAccountHeld(false)
            host.toolbarEditorShelf?.endDrag()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            land(overlay, on: session.item)
        } else if usesShelf(for: session.item), let shelf = host.toolbarEditorShelf {
            // Off the toolbar, or over one with no room, the button's place is on the shelf
            let isRemoved = configuration.isShown(session.item)
            configuration.setShown(false, session.item)
            finishEdit(with: configuration)
            if isRemoved { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
            let landing = shelf.getLandingFrame(for: session.item)
            overlay.finish(landing.isAbsorbed ? .absorb(landing.frame) : .land(landing.frame)) { [weak shelf] in
                shelf?.endDrag()
            }
        } else if isInside {
            // The toolbar has no room for another button, as the hint over it has been saying
            finishEdit(with: configuration)
            overlay.finish(.dissolve)
        } else if session.origin == .toolbar, session.item.isHideable {
            configuration.setShown(false, session.item)
            finishEdit(with: configuration)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            overlay.finish(.remove)
        } else if session.origin == .toolbar {
            finishEdit(with: configuration, landingItem: session.item)
            land(overlay, on: session.item)
        } else if session.origin == .topBar, let frame = host.getTopAccountFrame(isAtStart: session.isTopAtStart) {
            finishEdit(with: configuration)
            overlay.finish(.land(frame)) { [weak self] in
                self?.host?.setTopAccountHeld(false)
            }
        } else {
            finishEdit(with: configuration)
            overlay.finish(.dissolve)
        }
    }

    public func cancel() {
        let hadSession = session != nil
        session = nil
        guard let host else { return }
        if toolbar.homeEdit != nil {
            toolbar.endHomeEdit(
                with: host.getToolbarEditorDisplayedConfiguration(host.toolbarEditorConfiguration),
                animated: true
            )
        }
        hideDimming()
        if hadSession || overlay != nil {
            host.setTopAccountDragActive(false)
            host.setTopAccountHeld(false)
            host.toolbarEditorShelf?.endDrag()
        }
        overlay?.finish(.dissolve)
        overlay = nil
    }

    private func finishEdit(with configuration: HomeToolbarConfiguration, landingItem: HomeToolbarItem? = nil) {
        guard let host else { return }
        toolbar.endHomeEdit(
            with: host.getToolbarEditorDisplayedConfiguration(configuration),
            landingItem: landingItem,
            animated: true
        )
        hideDimming()
        overlay = nil
        if configuration != host.toolbarEditorConfiguration {
            host.commitToolbarEditorConfiguration(configuration)
        }
        // The top bar settles into what was stored
        host.setTopAccountDragActive(false)
    }

    /// The dragged glass settles onto its button, which then shows its own content
    private func land(_ overlay: HomeToolbarEditOverlayView, on item: HomeToolbarItem) {
        guard let frame = getToolbarItemFrame(item) else {
            toolbar.finishHomeItemLanding()
            overlay.finish(.dissolve)
            return
        }
        overlay.finish(.land(frame)) { [weak toolbar] in
            toolbar?.finishHomeItemLanding()
        }
    }

    // MARK: - Geometry

    private func getToolbarItemFrame(_ item: HomeToolbarItem) -> CGRect? {
        toolbar.getHomeItemFrame(item).map { frame in
            // The field lifts as the circle it is on other screens
            let frame = item == .search
                ? CGRect(x: frame.midX - frame.height / 2, y: frame.minY, width: frame.height, height: frame.height)
                : frame
            return toolbar.convert(frame, to: nil)
        }
    }

    private func getTopAccountFrames() -> (start: CGRect, end: CGRect)? {
        guard let start = host?.getTopAccountFrame(isAtStart: true),
              let end = host?.getTopAccountFrame(isAtStart: false) else { return nil }
        return (start, end)
    }

    private func isInsideToolbarZone(_ point: CGPoint) -> Bool {
        let frame = toolbar.convert(toolbar.bounds, to: nil)
        return point.y >= frame.minY - Self.toolbarZoneMargin && point.y <= frame.maxY + Self.toolbarZoneMargin
    }

    /// Counts every stored button, shown for this account or not, so the toolbar never holds more than it can show
    private func canToolbarHold(_ session: Session) -> Bool {
        session.origin == .toolbar || toolbar.canHoldHomeItem(session.item, in: host?.toolbarEditorConfiguration)
    }

    // MARK: - Chrome

    private func makeOverlay(in window: UIWindow) -> HomeToolbarEditOverlayView {
        overlay?.finish(.dissolve)
        let overlay = HomeToolbarEditOverlayView(frame: window.bounds)
        overlay.overrideUserInterfaceStyle = toolbar.traitCollection.userInterfaceStyle
        window.addSubview(overlay)
        self.overlay = overlay
        return overlay
    }

    private func showDimming() {
        guard dimmingView == nil, let anchor = host?.toolbarEditorDimmingAnchor else { return }
        let view = UIView(frame: anchor.container.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = UIColor { traits in
            UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.45 : 0.2)
        }
        view.alpha = 0
        // Taps wait for the drag to end
        view.isUserInteractionEnabled = true
        anchor.container.insertSubview(view, belowSubview: anchor.sibling)
        dimmingView = view
        host?.setToolbarEditorDimmed(true)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            view.alpha = 1
        }
    }

    private func hideDimming() {
        guard let view = dimmingView else { return }
        dimmingView = nil
        host?.setToolbarEditorDimmed(false)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            view.alpha = 0
        } completion: { _ in
            view.removeFromSuperview()
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard session == nil, host?.canEditToolbar == true,
              let item = toolbar.getHomeItem(at: gestureRecognizer.location(in: toolbar)) else { return false }
        return item.isHideable || dragsFixedItems
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard host?.canEditToolbar == true,
              let item = toolbar.getHomeItem(at: touch.location(in: toolbar)) else { return false }
        return item.isHideable || dragsFixedItems
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        !(otherGestureRecognizer is UIPanGestureRecognizer)
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // A finger resting on a button is not paging or scrolling what is around the toolbar
        otherGestureRecognizer is UIPanGestureRecognizer
    }
}

// MARK: - Overlay

/// What floats over the screen during a drag: the dragged glass, and the places away from the toolbar where it can
/// drop
@MainActor
final class HomeToolbarEditOverlayView: UIView {
    enum Ending {
        /// Settles onto a frame in window coordinates
        case land(CGRect)
        /// Shrinks into the remove target
        case remove
        /// Shrinks away into a frame in window coordinates
        case absorb(CGRect)
        /// Fades where it is
        case dissolve
    }

    private static let liftScale: CGFloat = 1.18
    private static let size = HomeToolbarLayout.buttonSize

    private let platter = UIView()
    private let platterShadow = UIView()
    private let platterGlass = HomeToolbarEditGlassView()
    private var standIn: UIView?
    private let removeTarget = HomeToolbarEditGlassView()
    /// The target's red filling with its white content, which fades in over the red content as one piece: glass
    /// changes its tint on its own clock, behind the text
    private let removeFill = UIView()
    private let removeContent = HomeToolbarRemoveContentView(color: .systemRed)
    private let removeHighlightedContent = HomeToolbarRemoveContentView(color: .white)
    private let topTargets = [HomeToolbarEditGlassView(), HomeToolbarEditGlassView()]
    private var isRemoveHighlighted = false
    private let fullHint = HomeToolbarEditGlassView()
    private let fullHintTitleLabel = UILabel()
    private let fullHintSubtitleLabel = UILabel()

    private(set) var hasRemoveTarget = false
    private(set) var hasTopTargets = false
    var platterCenter: CGPoint { platter.center }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        removeFill.backgroundColor = .systemRed
        removeFill.layer.cornerRadius = Self.size / 2
        removeFill.layer.cornerCurve = .continuous
        removeFill.alpha = 0
        for view in [removeContent, removeFill] {
            view.frame = removeTarget.contentView.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            removeTarget.contentView.addSubview(view)
        }
        removeHighlightedContent.frame = removeFill.bounds
        removeHighlightedContent.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        removeFill.addSubview(removeHighlightedContent)
        removeTarget.alpha = 0
        addSubview(removeTarget)
        fullHintTitleLabel.text = lang("$toolbar_full_title")
        fullHintTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        fullHintTitleLabel.textColor = .label
        fullHintSubtitleLabel.text = lang("$toolbar_full_hint")
        fullHintSubtitleLabel.font = .systemFont(ofSize: 13)
        fullHintSubtitleLabel.textColor = .secondaryLabel
        for label in [fullHintTitleLabel, fullHintSubtitleLabel] {
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            fullHint.contentView.addSubview(label)
        }
        fullHint.alpha = 0
        addSubview(fullHint)
        for target in topTargets {
            target.alpha = 0
            target.layer.borderColor = UIColor.tintColor.cgColor
            addSubview(target)
        }

        platter.bounds.size = CGSize(width: Self.size, height: Self.size)
        platterShadow.frame = platter.bounds
        platterShadow.layer.shadowColor = UIColor.black.cgColor
        platterShadow.layer.shadowOpacity = 0
        platterShadow.layer.shadowRadius = 14
        platterShadow.layer.shadowOffset = CGSize(width: 0, height: 8)
        platterShadow.layer.shadowPath = UIBezierPath(ovalIn: platter.bounds).cgPath
        // The glass is see-through: the shadow shows around it only
        let shadowMask = CAShapeLayer()
        let shadowArea = UIBezierPath(rect: platter.bounds.insetBy(dx: -60, dy: -60))
        shadowArea.append(UIBezierPath(ovalIn: platter.bounds))
        shadowMask.path = shadowArea.cgPath
        shadowMask.fillRule = .evenOdd
        platterShadow.layer.mask = shadowMask
        platter.addSubview(platterShadow)
        platterGlass.frame = platter.bounds
        platter.addSubview(platterGlass)
        addSubview(platter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Platter

    /// Lifts the item at `frame`, in window coordinates. `standIn` shows what the item was where it came from and
    /// gives way to the glass with `content` on it.
    func showPlatter(content: UIView, standIn: UIView?, frame: CGRect) {
        platter.center = convert(CGPoint(x: frame.midX, y: frame.midY), from: nil)
        // The copy may lay itself out with constraints, which would leave a frame set here where it started
        let contentSize = content.bounds.size
        content.translatesAutoresizingMaskIntoConstraints = false
        platterGlass.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: platterGlass.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: platterGlass.centerYAnchor),
            content.widthAnchor.constraint(equalToConstant: contentSize.width),
            content.heightAnchor.constraint(equalToConstant: contentSize.height),
        ])
        let startScale = frame.width / Self.size
        platter.transform = CGAffineTransform(scaleX: startScale, y: startScale)
        if let standIn {
            self.standIn = standIn
            standIn.transform = .identity
            standIn.bounds.size = frame.size
            standIn.center = CGPoint(x: Self.size / 2, y: Self.size / 2)
            standIn.transform = CGAffineTransform(scaleX: 1 / startScale, y: 1 / startScale)
            platter.addSubview(standIn)
            platterGlass.setMaterialized(false)
            content.alpha = 0
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.platter.transform = CGAffineTransform(scaleX: Self.liftScale, y: Self.liftScale)
            self.platterShadow.layer.shadowOpacity = 0.2
        }
        if let standIn {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                standIn.alpha = 0
                content.alpha = 1
                self.platterGlass.setMaterialized(true)
            } completion: { _ in
                standIn.removeFromSuperview()
            }
        }
    }

    func movePlatter(to point: CGPoint) {
        platter.center = convert(point, from: nil)
    }

    // MARK: Remove target

    func showRemoveTarget(above toolbarFrame: CGRect) {
        hasRemoveTarget = true
        let frame = convert(toolbarFrame, from: nil)
        removeTarget.bounds.size = CGSize(width: removeContent.preferredWidth, height: Self.size)
        removeTarget.center = CGPoint(x: bounds.midX, y: frame.minY - 72 - Self.size / 2)
        removeTarget.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.removeTarget.alpha = 1
            self.removeTarget.transform = .identity
        }
    }

    func highlightRemoveTarget(_ isHighlighted: Bool) {
        guard hasRemoveTarget, isHighlighted != isRemoveHighlighted else { return }
        isRemoveHighlighted = isHighlighted
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.removeFill.alpha = isHighlighted ? 1 : 0
            self.removeContent.alpha = isHighlighted ? 0 : 1
            self.removeTarget.transform = isHighlighted ? CGAffineTransform(scaleX: 1.12, y: 1.12) : .identity
        }
    }

    // MARK: Full hint

    /// Says that the toolbar under the dragged item cannot take it
    func setFullHintShown(_ isShown: Bool, above toolbarFrame: CGRect) {
        if isShown {
            let frame = convert(toolbarFrame, from: nil)
            let maxWidth = bounds.width - 64
            let titleSize = fullHintTitleLabel.intrinsicContentSize
            let subtitleSize = fullHintSubtitleLabel.intrinsicContentSize
            let textWidth = min(maxWidth - 44, ceil(max(titleSize.width, subtitleSize.width)))
            let size = CGSize(width: textWidth + 44, height: ceil(titleSize.height + subtitleSize.height) + 2 + 22)
            fullHint.bounds.size = size
            fullHint.center = CGPoint(x: bounds.midX, y: frame.minY - 72 - size.height / 2)
            fullHintTitleLabel.frame = CGRect(x: 22, y: 11, width: textWidth, height: ceil(titleSize.height))
            fullHintSubtitleLabel.frame = CGRect(
                x: 22, y: fullHintTitleLabel.frame.maxY + 2, width: textWidth, height: ceil(subtitleSize.height)
            )
            if fullHint.alpha == 0 { fullHint.transform = CGAffineTransform(scaleX: 0.8, y: 0.8) }
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.fullHint.alpha = isShown ? 1 : 0
            self.fullHint.transform = isShown ? .identity : CGAffineTransform(scaleX: 0.8, y: 0.8)
        }
    }

    // MARK: Top targets

    func showTopTargets(start: CGRect, end: CGRect) {
        hasTopTargets = true
        for (target, frame) in zip(topTargets, [start, end]) {
            target.frame = convert(frame, from: nil)
            target.layer.cornerRadius = frame.height / 2
            target.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            for target in self.topTargets {
                target.alpha = 1
                target.transform = .identity
            }
        }
    }

    /// `nil` highlights neither
    func highlightTopTarget(_ isAtStart: Bool?) {
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            for (index, target) in self.topTargets.enumerated() {
                let isHighlighted = isAtStart != nil && (index == 0) == isAtStart
                target.layer.borderWidth = isHighlighted ? 2 : 0
                target.transform = isHighlighted ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
            }
        }
    }

    // MARK: Ending

    func finish(_ ending: Ending, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            if case .remove = ending {} else { self.removeTarget.alpha = 0 }
            self.topTargets.forEach { $0.alpha = 0 }
            self.fullHint.alpha = 0
        }
        let remove = { [weak self] (_: Bool) in
            completion?()
            self?.removeFromSuperview()
        }
        guard UIView.areAnimationsEnabled, window != nil else {
            remove(true)
            return
        }
        switch ending {
        case .land(let frame):
            let scale = frame.width / Self.size
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState], animations: {
                self.platter.center = self.convert(CGPoint(x: frame.midX, y: frame.midY), from: nil)
                self.platter.transform = CGAffineTransform(scaleX: scale, y: scale)
                self.platterShadow.layer.shadowOpacity = 0
            }, completion: remove)
        case .remove:
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
                self.platter.center = self.removeTarget.center
                self.platter.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                self.platter.alpha = 0
                self.removeTarget.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }, completion: { _ in
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
                    self.removeTarget.alpha = 0
                    self.removeTarget.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                }, completion: remove)
            })
        case .absorb(let frame):
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
                self.platter.center = self.convert(CGPoint(x: frame.midX, y: frame.midY), from: nil)
                self.platter.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                self.platter.alpha = 0
            }, completion: remove)
        case .dissolve:
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
                self.platter.transform = self.platter.transform.scaledBy(x: 0.5, y: 0.5)
                self.platter.alpha = 0
            }, completion: remove)
        }
    }
}

/// The Remove target's icon and title in one colour
@MainActor
private final class HomeToolbarRemoveContentView: UIView {
    private let stack: UIStackView

    var preferredWidth: CGFloat {
        ceil(stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width) + 38
    }

    init(color: UIColor) {
        let icon = UIImageView(image: UIImage(
            systemName: "trash",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        ))
        icon.tintColor = color
        let label = UILabel()
        label.text = lang("Remove")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = color
        stack = UIStackView(arrangedSubviews: [icon, label])
        super.init(frame: .zero)
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A capsule of glass, or of blur material before iOS 26
@MainActor
private final class HomeToolbarEditGlassView: UIView {
    var contentView: UIView { effectView.contentView }
    private let effectView = UIVisualEffectView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        effectView.frame = bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            effectView.cornerConfiguration = .capsule()
        } else {
            effectView.clipsToBounds = true
            effectView.layer.cornerCurve = .continuous
        }
        effectView.effect = makeEffect()
        addSubview(effectView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !IOS_26_MODE_ENABLED {
            effectView.layer.cornerRadius = bounds.height / 2
        }
    }

    /// Inside an animation the glass materializes with it
    func setMaterialized(_ isMaterialized: Bool) {
        effectView.effect = isMaterialized ? makeEffect() : nil
    }

    private func makeEffect() -> UIVisualEffect {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            return UIGlassEffect(style: .regular)
        }
        return UIBlurEffect(style: .systemMaterial)
    }
}

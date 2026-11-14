import UIKit
import UIComponents
import WalletContext
import UIAgent

/// The header's glass capsules through a push or pop between the Agent list and a chat, moved as Telegram and
/// SwiftUI's toolbar glass move them. The capsules stay above the content the whole time:
/// - a capsule on both bars is one piece of glass that changes its width and place on a spring with a slight bounce,
///   its content shrinking away and the other bar's growing in: the list's tabs and the chat's title pill, the wallet
///   avatar and the chat's more button;
/// - the chat's threads button grows out of the tabs' capsule, and collapses back into it, and so does the chat's more
///   button when the list's header has no avatar for it to turn into;
/// - every capsule that moves swells as it starts, its height a little ahead of its width, and shrinks back with a
///   bounce, a little under its size, as it lands;
/// - any other capsule on one bar only materializes or dematerializes in place.
///
/// The springs and the swell are measured from Telegram's own header: the capsules move on `GlassMotion.transition`
/// and swell by `GlassPulseCurve`, up to a fifth of a capsule's height about 0.11 s in, 2.5% under it about 0.33 s in.
///
/// The capsules don't follow the transition's progress: they start moving when a push or a tapped pop starts, and a
/// swipe back holds them on the chat's bar until the finger lifts, then moves them to the bar that wins.
@MainActor
final class AgentHeaderPlatterTransition {
    /// A capsule on one bar: its real view, hidden while the transition draws the capsule, and a copy of its content
    struct Capsule {
        let view: UIView
        let makeItem: @MainActor () -> UIView?
        /// The drawn content gives way to the real one at once, for content with see-through parts, such as the tabs'
        /// grey titles: over the real content its copy would darken them. Content whose colors come from the glass
        /// behind it lingers over the real one that takes over and fades.
        var shouldSwapOnHandOff = false
        /// The content only blurs and fades as it swaps, for content spread across a wide capsule, such as the tabs:
        /// scaled about the capsule's middle, its items would slide sideways. Other content shrinks away and grows in.
        var shouldKeepContentScale = false
        /// The view hidden while the transition draws the capsule, when it isn't the capsule itself: glass inside a
        /// glass container, hidden on its own, leaves the container drawing it a moment longer as it merges away
        var hidingView: UIView?
    }

    /// The capsules of one bar, matched with the other bar's by place
    struct Bar {
        /// The capsule at the leading edge: the chat's threads button
        var leading: Capsule?
        /// The wide capsule: the list's tabs, the chat's title pill
        var pill: Capsule?
        /// The capsule at the trailing edge: the wallet avatar, the chat's more button
        var trailing: Capsule?
        /// With no capsule at the trailing edge, the other bar's capsule there grows out of the pill and collapses back
        /// into it, as the threads button does, rather than materializing in place
        var isTrailingGrowingFromPill = false

        subscript(role: Role) -> Capsule? {
            switch role {
            case .leading: leading
            case .pill: pill
            case .trailing: trailing
            }
        }

        var capsules: [Capsule] { [leading, pill, trailing].compactMap { $0 } }
    }

    enum Role: CaseIterable {
        case leading, pill, trailing
    }

    /// Content shown in a capsule: blurred as it shrinks away or before it grows in
    @MainActor
    private final class Item {
        let view = WBlurredContentView()
        var appearance: GlassSpringCurve
        /// The scale at an appearance of 1
        var hiddenScale: CGFloat
        var isLeaving = false
        /// Where the content stays, in the overlay, while its capsule changes shape around it: the place it left, or the
        /// place it lands on. Content without one moves with its capsule.
        var anchor: Anchor?

        enum Anchor {
            case point(CGPoint)
            /// Wherever the capsule is heading, which may change while it moves
            case capsuleTarget
        }

        init(content: UIView, appearance: GlassSpringCurve, hiddenScale: CGFloat) {
            self.appearance = appearance
            self.hiddenScale = hiddenScale
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = true
            view.bounds = CGRect(origin: .zero, size: content.bounds.size)
            content.translatesAutoresizingMaskIntoConstraints = true
            content.transform = .identity
            content.alpha = 1
            content.frame = view.bounds
            view.addSubview(content)
        }
    }

    @MainActor
    private final class Platter {
        let glass: UIVisualEffectView
        var x: GlassSpringCurve
        var y: GlassSpringCurve
        var width: GlassSpringCurve
        var height: GlassSpringCurve
        var items: [Item] = []
        /// The swell over the moving frame, if the capsule moves with one
        var pulse: GlassPulseCurve?
        /// How far a capsule growing out of the pill or collapsing into it has merged into the pill: from 0, its own
        /// shape, to 1, where its glass is drawn at `GlassMotion.matchScale` of its frame, as SwiftUI's matched glass is.
        /// The frame springs between the capsule's and the pill's, and the scale keeps the glass within the pill.
        var merge: GlassSpringCurve?
        /// Materializing or dematerializing in place, by UIKit's own glass animation
        var isInPlace = false

        init(frame: CGRect) {
            let glass = UIVisualEffectView(effect: nil)
            // Set outside any animation, the glass is there at once rather than materializing over the real capsule
            // it replaces
            UIView.performWithoutAnimation {
                if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
                    glass.effect = UIGlassEffect(style: .regular)
                    glass.cornerConfiguration = .capsule()
                } else {
                    glass.effect = UIBlurEffect(style: .systemMaterial)
                    glass.clipsToBounds = true
                    // A capsule, also while it stays in place, where `render` doesn't shape it
                    glass.layer.cornerRadius = frame.height / 2
                }
            }
            glass.isUserInteractionEnabled = false
            glass.frame = frame
            self.glass = glass
            x = .constant(frame.midX)
            y = .constant(frame.midY)
            width = .constant(frame.width)
            height = .constant(frame.height)
        }

        func getFrame(at time: CFTimeInterval) -> CGRect {
            let size = CGSize(width: max(0, width.getValue(at: time)), height: max(0, height.getValue(at: time)))
            return CGRect(x: x.getValue(at: time) - size.width / 2, y: y.getValue(at: time) - size.height / 2, width: size.width, height: size.height)
        }

        /// The glass as drawn: the moving frame scaled about its middle as the capsule merges, with its swell about the
        /// pulse's anchor
        func getSwollenFrame(at time: CFTimeInterval) -> CGRect {
            var moving = getFrame(at: time)
            if let merge {
                let scale = 1 + merge.getValue(at: time) * (GlassMotion.matchScale - 1)
                moving = moving.insetBy(dx: moving.width * (1 - scale) / 2, dy: moving.height * (1 - scale) / 2)
            }
            guard let pulse else { return moving }
            let scale = pulse.getScale(at: time)
            let size = CGSize(width: moving.width * scale.width, height: moving.height * scale.height)
            return CGRect(
                x: moving.minX + pulse.anchor.x * (moving.width - size.width),
                y: moving.minY + pulse.anchor.y * (moving.height - size.height),
                width: size.width,
                height: size.height
            )
        }

        func animateFrame(from source: CGRect, to target: CGRect, at time: CFTimeInterval, spring: GlassSpring) {
            x = GlassSpringCurve(startTime: time, from: source.midX, target: target.midX, spring: spring)
            y = GlassSpringCurve(startTime: time, from: source.midY, target: target.midY, spring: spring)
            width = GlassSpringCurve(startTime: time, from: source.width, target: target.width, spring: spring)
            height = GlassSpringCurve(startTime: time, from: source.height, target: target.height, spring: spring)
        }

        var restTime: CFTimeInterval {
            max(
                x.restTime, y.restTime, width.restTime, height.restTime, pulse?.restTime ?? 0, merge?.restTime ?? 0,
                items.map(\.appearance.restTime).max() ?? 0
            )
        }

        /// Close enough to rest that the real capsule can take over without a visible step: the springs' long
        /// tails would otherwise keep the real, tappable buttons hidden for a second or more
        func isVisuallySettled(at time: CFTimeInterval) -> Bool {
            let positionTolerance: CGFloat = 0.3
            for curve in [x, y, width, height] where abs(curve.getValue(at: time) - curve.target) > positionTolerance {
                return false
            }
            if let pulse {
                let scale = pulse.getScale(at: time)
                if abs(width.target * (scale.width - 1)) > positionTolerance
                    || abs(height.target * (scale.height - 1)) > positionTolerance {
                    return false
                }
            }
            if let merge,
               abs(width.target * (merge.getValue(at: time) - merge.target) * (GlassMotion.matchScale - 1)) > positionTolerance {
                return false
            }
            return items.allSatisfy { item in
                let appearance = item.appearance.getValue(at: time)
                return item.isLeaving ? appearance >= 0.97 : appearance <= 0.03
            }
        }
    }

    /// UIKit's own glass materialization runs about this long
    private static let inPlaceDuration: CFTimeInterval = 0.5

    private let outgoing: @MainActor () -> Bar
    private let incoming: @MainActor () -> Bar
    private let pillSwellStrength: CGSize
    private let overlayView = UIView()
    private let containerView: UIVisualEffectView
    private var platters: [Role: Platter] = [:]
    /// The incoming bar's capsules the drawn ones land on, which they keep following until they take over
    private var incomingViews: [Role: UIView] = [:]
    /// Roles whose target is where the capsule rests, known before the bar gets there; they aren't followed
    private var restingRoles: Set<Role> = []
    /// Moving between screens on a navigation transition, whose bar lays its buttons out only as it ends
    private var isNavigation = false
    private var isTracked = false
    private var hiddenViews: [UIView] = []
    /// The outgoing bar's roles whose content only blurs and fades as it leaves
    private var outgoingUnscaledRoles: Set<Role> = []
    private lazy var clock = GlassMotionClock { [weak self] time in self?.render(at: time) }
    private var switchTime: CFTimeInterval?
    /// The switch waits for the incoming capsules; after this many frames it goes ahead with the ones that are there
    private static let maximumSwitchDelayFrames = 12
    private var switchAttempts = 0
    private var isSwitchPending = false
    private var isTransitionComplete = false
    private var isFinished = false
    /// The outgoing bar won: a swipe back that was cancelled
    private var isOutgoingKept = false
    private var isTrailingGrowingFromPill = false

    /// `outgoing` is the bar on screen as the transition starts; `incoming` the one it brings, read once it is laid out.
    /// `pillSwellStrength` scales the wide capsule's swell as it moves, per axis: 1 is Telegram's full swell.
    init(
        outgoing: @escaping @MainActor () -> Bar,
        incoming: @escaping @MainActor () -> Bar,
        pillSwellStrength: CGSize = CGSize(width: 1, height: 1)
    ) {
        self.outgoing = outgoing
        self.incoming = incoming
        self.pillSwellStrength = pillSwellStrength
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            let effect = UIGlassContainerEffect()
            // How close the bar's glass shapes come before they merge: closer than the list header's 10 pt. The tabs
            // and the avatar rest that far apart, and the avatar swelling beside the tabs comes about 4 pt nearer.
            effect.spacing = 5
            containerView = UIVisualEffectView(effect: effect)
        } else {
            containerView = UIVisualEffectView(effect: nil)
        }
        overlayView.isUserInteractionEnabled = false
        containerView.isUserInteractionEnabled = false
    }

    /// Moves the capsules from one bar to the other within a screen: `change` swaps the views, and the capsules start
    /// moving at once
    func run(in window: UIWindow, change: () -> Void) {
        Self.performWithoutAnimation {
            setUpOverlay(in: window)
            captureOutgoing()
        }
        change()
        isTransitionComplete = true
        switchToIncoming()
    }

    func run(in window: UIWindow, alongside coordinator: any UIViewControllerTransitionCoordinator) {
        isNavigation = true
        Self.performWithoutAnimation {
            setUpOverlay(in: window)
            captureOutgoing()
        }
        // The capsules move along with screens that spring past the edge, clipped as the transition rounds the
        // screens, so none shows over the background they bare, not even a capsule swelling past the edge. Glass
        // takes the move from a view around its container, not from the container itself.
        NavigationOvershootFollower.follow(coordinator) { [overlayView] offset, cornerRadius in
            overlayView.transform = offset == 0 ? .identity : CGAffineTransform(translationX: offset, y: 0)
            overlayView.layer.cornerRadius = cornerRadius
            overlayView.layer.cornerCurve = .continuous
            overlayView.layer.masksToBounds = cornerRadius > 0
        }
        if coordinator.isInteractive {
            // A swipe back keeps the list's capsules away until the finger lifts
            Self.performWithoutAnimation {
                for capsule in incoming().capsules { hide(capsule) }
            }
            coordinator.notifyWhenInteractionChanges { [weak self] context in
                guard let self else { return }
                if context.isCancelled {
                    isOutgoingKept = true
                } else {
                    Self.performWithoutAnimation { self.switchToIncoming() }
                }
            }
        }
        let accepted = coordinator.animate(alongsideTransition: { [weak self] context in
            guard let self, !context.isInteractive else { return }
            Self.performWithoutAnimation { self.switchToIncoming() }
        }, completion: { [weak self] context in
            guard let self else { return }
            if context.isCancelled { isOutgoingKept = true }
            isTransitionComplete = true
            finishIfSettled()
        })
        if accepted {
            render(at: CACurrentMediaTime())
        } else {
            finish()
        }
    }

    /// Ends the transition at once, for one that another replaces
    func cancel() {
        finish()
    }

    private func setUpOverlay(in window: UIWindow) {
        Self.fadingOverlay?.removeFromSuperview()
        Self.fadingOverlay = nil
        if !isTracked {
            isTracked = true
            AgentHeaderTransitionTracker.begin()
        }
        overlayView.frame = window.bounds
        containerView.frame = overlayView.bounds
        overlayView.addSubview(containerView)
        window.addSubview(overlayView)
    }

    private func captureOutgoing() {
        let bar = outgoing()
        isTrailingGrowingFromPill = isTrailingGrowingFromPill || bar.isTrailingGrowingFromPill
        for role in Role.allCases {
            guard let capsule = bar[role], let frame = Self.getFrame(of: capsule.view, in: overlayView) else { continue }
            let platter = Platter(frame: frame)
            if capsule.shouldKeepContentScale {
                outgoingUnscaledRoles.insert(role)
            }
            if let content = capsule.makeItem() {
                add(Item(content: content, appearance: .constant(0), hiddenScale: GlassMotion.matchScale), to: platter)
            }
            containerView.contentView.addSubview(platter.glass)
            platters[role] = platter
            hide(capsule)
            if isNavigation, role != .pill {
                Self.rememberRestingFrame(frame, of: role, in: overlayView)
            }
        }
    }

    private func hide(_ capsule: Capsule) {
        hide(capsule.hidingView ?? capsule.view)
    }

    private func hide(_ view: UIView) {
        guard !hiddenViews.contains(where: { $0 === view }) else { return }
        hiddenViews.append(view)
        view.isHidden = true
    }

    private func add(_ item: Item, to platter: Platter) {
        platter.items.append(item)
        platter.glass.contentView.addSubview(item.view)
    }

    // MARK: - Motion

    /// Moves the capsules to the incoming bar once its capsules are laid out in the window. The bar the navigation bar
    /// brings in can take a frame or two to get there; meanwhile the outgoing capsules hold still.
    private func switchToIncoming() {
        guard switchTime == nil, !isFinished else { return }
        let bar = incoming()
        isTrailingGrowingFromPill = isTrailingGrowingFromPill || bar.isTrailingGrowingFromPill
        for capsule in bar.capsules {
            capsule.view.superview?.layoutIfNeeded()
        }
        let missing = bar.capsules.filter { Self.getFrame(of: $0.view, in: overlayView) == nil }
        guard missing.isEmpty || switchAttempts >= Self.maximumSwitchDelayFrames else {
            switchAttempts += 1
            for capsule in bar.capsules { hide(capsule) }
            isSwitchPending = true
            clock.start()
            return
        }
        isSwitchPending = false
        let now = CACurrentMediaTime()
        switchTime = now
        let isReduced = UIAccessibility.isReduceMotionEnabled
        let spring = isReduced ? GlassMotion.materialize : GlassMotion.transition
        // The tabs and the threads button swell away from the capsule at the trailing edge, so they never reach for
        // it; that capsule, a circle, swells about its middle
        let awayFromTrailing: CGFloat = overlayView.effectiveUserInterfaceLayoutDirection == .rightToLeft ? 0 : 1
        func swell(_ platter: Platter, role: Role, size: CGSize, from start: CFTimeInterval) {
            guard !isReduced else { return }
            let anchor = CGPoint(x: role == .trailing ? 0.5 : awayFromTrailing, y: 0.5)
            platter.pulse = GlassPulseCurve(size: size, startTime: start, anchor: anchor, strength: role == .pill ? pillSwellStrength : CGSize(width: 1, height: 1))
        }
        var targets: [Role: CGRect] = [:]
        var contents: [Role: UIView] = [:]
        for role in Role.allCases {
            guard let capsule = bar[role] else { continue }
            capsule.view.superview?.layoutIfNeeded()
            targets[role] = Self.getFrame(of: capsule.view, in: overlayView)
            contents[role] = capsule.makeItem()
            incomingViews[role] = capsule.view
            hide(capsule)
        }
        if isNavigation {
            applyRestingSideTargets(to: &targets)
        }
        // The pill goes first, so a threads button growing out of it or collapsing into it starts from its shape
        for role in [Role.pill, .trailing, .leading] {
            let existing = platters[role]
            if let target = targets[role] {
                if let platter = existing, role == .leading {
                    // The threads button is on both bars: the same glyph in the same place, kept as it is
                    platter.animateFrame(from: platter.getFrame(at: now), to: target, at: now, spring: spring)
                } else if let platter = existing {
                    // On both bars: one shape morphing to the new frame while its content changes in place
                    let source = platter.getFrame(at: now)
                    platter.animateFrame(from: source, to: target, at: now, spring: spring)
                    swell(platter, role: role, size: target.size, from: now)
                    swapContent(
                        of: platter,
                        to: contents[role],
                        from: source,
                        leavingScale: outgoingUnscaledRoles.contains(role) ? 1 : GlassMotion.matchScale,
                        incomingScale: bar[role]?.shouldKeepContentScale == true ? 1 : GlassMotion.matchScale,
                        at: now,
                        spring: spring
                    )
                } else if isGrowingFromPill(role), let partner = platters[.pill], !isReduced {
                    // Grows out of the pill: it starts as the pill's shape and leaves it
                    let source = partner.getFrame(at: now)
                    let platter = Platter(frame: source)
                    containerView.contentView.addSubview(platter.glass)
                    platters[role] = platter
                    startMatchedMorph(platter, source: source, target: target, isAppearing: true, at: now, spring: spring)
                    swell(platter, role: role, size: target.size, from: now)
                    if let content = contents[role] {
                        let appearance = GlassSpringCurve(startTime: now, from: 1, target: 0, spring: spring)
                        let item = Item(content: content, appearance: appearance, hiddenScale: GlassMotion.matchScale)
                        // The glyph grows in where the button lands, not riding the glass out across the pill's content
                        item.anchor = .capsuleTarget
                        add(item, to: platter)
                    }
                } else {
                    let platter = Platter(frame: target)
                    containerView.contentView.addSubview(platter.glass)
                    platters[role] = platter
                    if let content = contents[role] {
                        add(Item(content: content, appearance: .constant(0), hiddenScale: 1), to: platter)
                    }
                    materialize(platter, frame: target)
                }
            } else if let platter = existing {
                if isGrowingFromPill(role), let partnerTarget = targets[.pill], platters[.pill] != nil, !isReduced {
                    // Collapses into the pill after a moment, its content leaving as it goes
                    let own = platter.getFrame(at: now)
                    let start = startMatchedMorph(platter, source: own, target: partnerTarget, isAppearing: false, at: now, spring: spring)
                    swell(platter, role: role, size: own.size, from: start)
                    for item in platter.items {
                        item.isLeaving = true
                        item.appearance = GlassSpringCurve(startTime: start, from: item.appearance.getValue(at: now), target: 1, spring: spring)
                        // The glyph shrinks away where the button was, not riding the glass into the pill's content
                        if item.anchor == nil {
                            item.anchor = .point(CGPoint(x: own.midX, y: own.midY))
                        }
                    }
                } else {
                    dematerialize(platter)
                }
            }
        }
        render(at: now)
        clock.start()
    }

    private func isGrowingFromPill(_ role: Role) -> Bool {
        role == .leading || (role == .trailing && isTrailingGrowingFromPill)
    }

    /// The old content shrinks to `leavingScale` where it was, blurring and fading, as the new grows from
    /// `incomingScale` where it lands: the capsule changes its shape around them, so neither slides across it
    private func swapContent(
        of platter: Platter,
        to content: UIView?,
        from source: CGRect,
        leavingScale: CGFloat,
        incomingScale: CGFloat,
        at time: CFTimeInterval,
        spring: GlassSpring
    ) {
        for item in platter.items where !item.isLeaving {
            item.isLeaving = true
            item.hiddenScale = leavingScale
            item.appearance = GlassSpringCurve(startTime: time, from: item.appearance.getValue(at: time), target: 1, spring: spring)
            if item.anchor == nil {
                item.anchor = .point(CGPoint(x: source.midX, y: source.midY))
            }
        }
        if let content {
            let appearance = GlassSpringCurve(startTime: time, from: 1, target: 0, spring: spring)
            let item = Item(content: content, appearance: appearance, hiddenScale: incomingScale)
            item.anchor = .capsuleTarget
            add(item, to: platter)
        }
    }

    /// SwiftUI's matched insertion or removal: after the delay (only for a removal) the shape springs from `source` to
    /// `target`, its glass growing out of the partner's from `GlassMotion.matchScale` or shrinking into it, and merging
    /// with it meanwhile. Returns when it starts moving.
    @discardableResult
    private func startMatchedMorph(
        _ platter: Platter,
        source: CGRect,
        target: CGRect,
        isAppearing: Bool,
        at time: CFTimeInterval,
        spring: GlassSpring
    ) -> CFTimeInterval {
        let start = time + (isAppearing ? 0 : GlassMotion.matchedRemovalDelay)
        platter.animateFrame(from: source, to: target, at: start, spring: spring)
        platter.merge = GlassSpringCurve(
            startTime: start,
            from: isAppearing ? 1 : platter.merge?.getValue(at: time) ?? 0,
            target: isAppearing ? 0 : 1,
            spring: spring
        )
        return start
    }


    /// A capsule the incoming bar doesn't have dissolves where it is, swelling slightly, as UIKit's glass does
    private func dematerialize(_ platter: Platter) {
        platter.isInPlace = true
        let size = platter.glass.bounds.size
        let scale = UIAccessibility.isReduceMotionEnabled ? CGSize(width: 1, height: 1) : GlassMotion.getMaterializeScale(size: size)
        Self.animateGlass {
            platter.glass.transform = CGAffineTransform(scaleX: scale.width, y: scale.height)
            platter.glass.effect = nil
            platter.glass.contentView.alpha = 0
        }
    }

    private func materialize(_ platter: Platter, frame: CGRect) {
        platter.isInPlace = true
        let scale = UIAccessibility.isReduceMotionEnabled ? CGSize(width: 1, height: 1) : GlassMotion.getMaterializeScale(size: frame.size)
        let effect = platter.glass.effect
        UIView.performWithoutAnimation {
            platter.glass.frame = frame
            if !IOS_26_MODE_ENABLED {
                platter.glass.layer.cornerRadius = frame.height / 2
            }
            platter.glass.transform = CGAffineTransform(scaleX: scale.width, y: scale.height)
            platter.glass.effect = nil
            platter.glass.contentView.alpha = 0
        }
        Self.animateGlass {
            platter.glass.transform = .identity
            platter.glass.effect = effect
            platter.glass.contentView.alpha = 1
        }
    }

    /// The glass transition spring for UIKit animations. It starts on the next turn of the run loop, outside the
    /// animation-free block the switch to the incoming bar runs in.
    private static func animateGlass(_ animations: @escaping () -> Void) {
        DispatchQueue.main.async { runGlassAnimation(animations) }
    }

    private static func runGlassAnimation(_ animations: @escaping () -> Void) {
        if #available(iOS 17.0, *) {
            UIView.animate(springDuration: 0.416, bounce: 0.25, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction], animations: animations)
        } else {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: animations)
        }
    }

    private func render(at time: CFTimeInterval) {
        if isSwitchPending {
            Self.performWithoutAnimation { switchToIncoming() }
            if isSwitchPending { return }
        }
        followIncoming(at: time)
        for platter in platters.values {
            if !platter.isInPlace {
                let frame = platter.getSwollenFrame(at: time)
                platter.glass.bounds = CGRect(origin: .zero, size: frame.size)
                platter.glass.center = CGPoint(x: frame.midX, y: frame.midY)
                if !IOS_26_MODE_ENABLED {
                    platter.glass.layer.cornerRadius = frame.height / 2
                }
            }
            let center = CGPoint(x: platter.glass.bounds.midX, y: platter.glass.bounds.midY)
            for item in platter.items {
                let a = min(1, max(0, item.appearance.getValue(at: time)))
                let scale = 1 + a * (item.hiddenScale - 1)
                item.view.center = getItemCenter(item, in: platter, glassCenter: center)
                item.view.transform = CGAffineTransform(scaleX: scale, y: scale)
                item.view.alpha = 1 - a
                item.view.blurRadius = GlassMotion.blurRadius * a
            }
        }
        guard let switchTime else { return }
        let restTime = platters.values.map(\.restTime).max() ?? 0
        let inPlaceEnd = platters.values.contains { $0.isInPlace } ? switchTime + Self.inPlaceDuration : 0
        // The real capsules take over as soon as the drawn ones are as good as at rest, so they are tappable at once
        let isSettledEnough = isTransitionComplete && time >= inPlaceEnd
            && platters.values.allSatisfy { $0.isInPlace || $0.isVisuallySettled(at: time) }
        if time >= max(restTime, inPlaceEnd) || isSettledEnough {
            clock.stop()
            finishIfSettled()
        }
    }

    /// Where an item's content shows in its capsule's glass: at its anchor in the overlay, or in the middle of the glass
    private func getItemCenter(_ item: Item, in platter: Platter, glassCenter: CGPoint) -> CGPoint {
        guard !platter.isInPlace, let anchor = item.anchor else { return glassCenter }
        let point: CGPoint
        switch anchor {
        case .point(let value): point = value
        case .capsuleTarget: point = CGPoint(x: platter.x.target, y: platter.y.target)
        }
        let glass = platter.glass
        let origin = CGPoint(x: glass.center.x - glass.bounds.width / 2, y: glass.center.y - glass.bounds.height / 2)
        return CGPoint(
            x: point.x - origin.x + glass.bounds.minX,
            y: point.y - origin.y + glass.bounds.minY
        )
    }

    /// A capsule the bar lays out again while the drawn one moves, such as once the navigation transition ends, gets
    /// a new target: the drawn one carries on toward it from where and how fast it moves, so it lands exactly on the
    /// real capsule rather than stepping to it when that takes over
    private func followIncoming(at time: CFTimeInterval) {
        guard switchTime != nil, !isOutgoingKept else { return }
        let spring = UIAccessibility.isReduceMotionEnabled ? GlassMotion.materialize : GlassMotion.transition
        // Once the navigation transition ends, its bar has laid the buttons out where they stay, so every capsule follows
        // its real one, also those that headed for a resting place seen before
        for (role, view) in incomingViews where isTransitionComplete || !restingRoles.contains(role) {
            guard let platter = platters[role], !platter.isInPlace,
                  let frame = Self.getFrame(of: view, in: overlayView) else { continue }
            let tolerance: CGFloat = 0.25
            if abs(platter.x.target - frame.midX) > tolerance {
                platter.x = platter.x.makeRetargeted(at: time, to: frame.midX, spring: spring)
            }
            if abs(platter.y.target - frame.midY) > tolerance {
                platter.y = platter.y.makeRetargeted(at: time, to: frame.midY, spring: spring)
            }
            if abs(platter.width.target - frame.width) > tolerance {
                platter.width = platter.width.makeRetargeted(at: time, to: frame.width, spring: spring)
            }
            if abs(platter.height.target - frame.height) > tolerance {
                platter.height = platter.height.makeRetargeted(at: time, to: frame.height, spring: spring)
            }
        }
    }

    private func finishIfSettled() {
        guard isTransitionComplete, !isFinished else { return }
        if isOutgoingKept || switchTime == nil || !clock.isRunning {
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        clock.stop()
        if isNavigation, isTransitionComplete {
            rememberRestingSideFrames()
        }
        // The real capsules take over exactly where the drawn ones rest, without animating in. The drawn content of
        // most stays over them a moment and fades: a copy can't take on every color the real content takes from the
        // glass behind it, and would otherwise change them in one frame.
        let fadingContent = takeSettledContent()
        Self.performWithoutAnimation {
            for view in hiddenViews {
                view.isHidden = false
            }
            containerView.removeFromSuperview()
            for view in fadingContent {
                overlayView.addSubview(view)
            }
            if fadingContent.isEmpty {
                overlayView.removeFromSuperview()
            }
        }
        if !fadingContent.isEmpty {
            let overlay = overlayView
            Self.fadingOverlay = overlay
            UIView.animate(
                withDuration: Self.handOffFadeDuration,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                overlay.alpha = 0
            } completion: { _ in
                overlay.removeFromSuperview()
            }
        }
        if isTracked {
            isTracked = false
            AgentHeaderTransitionTracker.end()
        }
    }

    private static let handOffFadeDuration: TimeInterval = 0.15
    /// The overlay of a transition that ended and is fading out; the next transition removes it at once
    private static weak var fadingOverlay: UIView?

    /// The content the drawn capsules show at rest, moved out of their glass into the overlay where it shows
    private func takeSettledContent() -> [UIView] {
        guard !hiddenViews.isEmpty else { return [] }
        let bar = isOutgoingKept ? outgoing() : incoming()
        var views: [UIView] = []
        for (role, platter) in platters where !platter.isInPlace && bar[role]?.shouldSwapOnHandOff != true {
            for item in platter.items where !item.isLeaving && item.view.alpha > 0.01 {
                let center = platter.glass.contentView.convert(item.view.center, to: overlayView)
                item.view.removeFromSuperview()
                item.view.center = center
                views.append(item.view)
            }
        }
        return views
    }

    // MARK: - Resting places

    /// Where the side capsules rest, by role and bar width. A navigation bar lays the buttons it brings in out at their
    /// place only as the transition ends, and before that elsewhere and at another size, so the drawn capsules head for
    /// where the buttons were seen resting before: every Agent bar puts its side buttons in the same places.
    private static var restingFrames: [String: CGRect] = [:]

    private static func makeRestingKey(_ role: Role, in overlay: UIView) -> String {
        "\(role)-\(Int(overlay.bounds.width.rounded()))"
    }

    private static func rememberRestingFrame(_ frame: CGRect, of role: Role, in overlay: UIView) {
        restingFrames[makeRestingKey(role, in: overlay)] = frame
    }

    private func rememberRestingSideFrames() {
        let bar = isOutgoingKept ? outgoing() : incoming()
        for role in [Role.leading, .trailing] {
            guard let capsule = bar[role], let frame = Self.getFrame(of: capsule.view, in: overlayView) else { continue }
            Self.rememberRestingFrame(frame, of: role, in: overlayView)
        }
    }

    /// Replaces the measured side targets with where the side capsules rest: one seen before, or the other side's
    /// mirrored across the bar, whose side buttons sit the same distance from its edges
    private func applyRestingSideTargets(to targets: inout [Role: CGRect]) {
        for role in [Role.trailing, .leading] where targets[role] != nil {
            if let frame = Self.restingFrames[Self.makeRestingKey(role, in: overlayView)] {
                targets[role] = frame
                restingRoles.insert(role)
            }
        }
        let other: [Role: Role] = [.leading: .trailing, .trailing: .leading]
        for role in [Role.leading, .trailing] where targets[role] != nil && !restingRoles.contains(role) {
            guard let partner = other[role], restingRoles.contains(partner), let partnerFrame = targets[partner],
                  let view = incomingViews[role], let bar = Self.findNavigationBar(containing: view),
                  let barFrame = Self.getFrame(of: bar, in: overlayView) else { continue }
            targets[role] = CGRect(
                x: 2 * barFrame.midX - partnerFrame.maxX,
                y: partnerFrame.minY,
                width: partnerFrame.width,
                height: partnerFrame.height
            )
            restingRoles.insert(role)
        }
    }

    private static func findNavigationBar(containing view: UIView) -> UINavigationBar? {
        sequence(first: view, next: { $0.superview }).first { $0 is UINavigationBar } as? UINavigationBar
    }

    private static func performWithoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(body)
        CATransaction.commit()
    }

    /// Where `view` rests in `overlay`, leaving out transforms: the navigation bar scales its items in and out
    /// through a push or a pop, which the capsules would otherwise keep as their size
    private static func getFrame(of view: UIView, in overlay: UIView) -> CGRect? {
        guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let origin = getUntransformedPoint(view.bounds.origin, of: view)
        let overlayOrigin = getUntransformedPoint(overlay.bounds.origin, of: overlay)
        return CGRect(
            x: origin.x - overlayOrigin.x + overlay.bounds.minX,
            y: origin.y - overlayOrigin.y + overlay.bounds.minY,
            width: view.bounds.width,
            height: view.bounds.height
        )
    }

    /// `point` of `view`'s coordinate space in its window's, as if no view on the way were transformed
    private static func getUntransformedPoint(_ point: CGPoint, of view: UIView) -> CGPoint {
        var point = point
        var current = view
        while let superview = current.superview {
            let anchor = current.layer.anchorPoint
            point.x += current.center.x - current.bounds.width * anchor.x - current.bounds.minX
            point.y += current.center.y - current.bounds.height * anchor.y - current.bounds.minY
            current = superview
        }
        return point
    }
}

extension AgentHeaderPlatterTransition.Bar {
    /// A chat's or the News feed's bar: the threads button, the title's pill or the feed's switch, and the more button
    @MainActor
    static func chat(_ chat: (any AgentChatNavigationHandoff)?) -> Self {
        Self(
            leading: chat?.navigationHandoffLeadingView.map { AgentHeaderPlatterTransition.Capsule.button($0) },
            pill: chat?.navigationHandoffTitlePill.map { pill in
                if let tabs = pill as? WSegmentedControl {
                    return AgentHeaderPlatterTransition.Capsule.tabs(tabs)
                }
                return AgentHeaderPlatterTransition.Capsule.snapshot(pill, content: chat?.navigationHandoffTitleContent ?? pill)
            },
            trailing: chat?.navigationHandoffTrailingView.map { AgentHeaderPlatterTransition.Capsule.button($0) }
        )
    }
}

extension AgentHeaderPlatterTransition {
    private static var betweenChats: AgentHeaderPlatterTransition?

    /// Lets Agent screens morph their header's capsules into each other's through a push or a pop between them
    static func installBetweenChats() {
        guard AgentChatHeaderMorph.runner == nil else { return }
        AgentChatHeaderMorph.runner = { outgoing, incoming, coordinator in
            betweenChats?.cancel()
            betweenChats = nil
            guard let window = coordinator.containerView.window else { return }
            let transition = AgentHeaderPlatterTransition(
                outgoing: { [weak outgoing] in Bar.chat(outgoing) },
                incoming: { [weak incoming] in Bar.chat(incoming) }
            )
            betweenChats = transition
            transition.run(in: window, alongside: coordinator)
        }
    }
}

extension AgentHeaderPlatterTransition.Capsule {
    /// A glass button's capsule: its glyph, as the button draws it, becomes the content
    @MainActor
    static func button(_ button: UIView) -> Self {
        Self(view: button) { [weak button] in
            guard let button = (button as? AgentGlassCircleButton)?.button ?? button as? UIButton else { return nil }
            button.layoutIfNeeded()
            // The button's own image view draws a symbol at the size its configuration resolves, which the symbol
            // image alone doesn't carry
            if let imageView = button.imageView, let image = imageView.image,
               imageView.bounds.width > 0, imageView.bounds.height > 0 {
                let view = UIImageView(image: image)
                view.preferredSymbolConfiguration = imageView.preferredSymbolConfiguration
                view.contentMode = imageView.contentMode
                view.tintColor = imageView.tintColor
                view.bounds = CGRect(origin: .zero, size: imageView.bounds.size)
                return view
            }
            guard let image = button.configuration?.image ?? button.currentImage else { return nil }
            let view = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
            view.tintColor = button.configuration?.baseForegroundColor ?? .label
            view.contentMode = .center
            view.sizeToFit()
            return view
        }
    }

    /// A capsule whose content is `content`, such as a title inside its glass pill. A chat title's pill gives a copy
    /// of its title, which takes its colors where the transition shows it, as the title does: a title under a header
    /// that hasn't shown yet resolves its colors for the wrong backdrop. Other content is a picture drawn from the
    /// layer tree, so taking it never redraws the screen.
    @MainActor
    static func snapshot(_ view: UIView, content: UIView) -> Self {
        Self(view: view) { [weak view, weak content] in
            guard let content, content.bounds.width > 0, content.bounds.height > 0 else { return nil }
            content.layoutIfNeeded()
            if let pill = view as? AgentChatTitlePill, let copy = pill.makeContentCopy() {
                return copy
            }
            let image = content.makeLayerImage(scale: content.window?.screen.scale ?? content.traitCollection.displayScale)
            let picture = UIImageView(image: image)
            picture.frame = CGRect(origin: .zero, size: content.bounds.size)
            return picture
        }
    }

    /// Header tabs in a bar's title place, such as the News feed's switch, handed over as the list's tabs are
    @MainActor
    static func tabs(_ tabs: WSegmentedControl) -> Self {
        Self(
            view: tabs,
            makeItem: { [weak tabs] in tabs?.makeContentSnapshot() },
            shouldSwapOnHandOff: true,
            shouldKeepContentScale: true
        )
    }
}

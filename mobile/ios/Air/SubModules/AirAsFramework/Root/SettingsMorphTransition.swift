//
//  SettingsMorphTransition.swift
//  AirAsFramework
//
//  Push / pop between the top-tabs root and Settings as one morph of the top bar:
//  the avatar's glass capsule stretches into the QR + "more" capsule, the Wallet / Market /
//  Explore capsule shrinks right-to-left into the back button, and the avatar flies along a
//  curve to the large Settings avatar. Pop plays it backwards.
//
//  The real navigation bar is hidden while stand-in glass shapes, icons and an avatar snapshot
//  animate above everything; the real screens take over when it ends.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass
import UIComponents
import UISettings
import WalletCore

/// Tweakable motion values. Springs use SwiftUI meaning: response ≈ how long it takes,
/// damping 1 = no bounce, lower = more overshoot.
enum SettingsMorphTiming {
    /// Screens slide (incoming from the right edge, outgoing drifts left) and the avatar flies on
    /// this same spring, so the avatar lands exactly together with the name under it. Every spring
    /// starts at full speed and brakes (measured on Telegram: peak speed in the first frames,
    /// most of the way done in ~0.25 s).
    static let response: Double = 0.37
    /// Starting speed, as a share of the spring's natural speed: 1 = pure ease-out.
    static let launchVelocity: Double = 1
    static let slideDamping: Double = 1
    static let parallax: CGFloat = 0.3
    /// Glass shapes: edges move on a nearly calm spring (Telegram's glass barely overshoots in
    /// width); the liquid feel comes from the swelling below.
    static let glassDamping: Double = 0.82
    /// Liquid inertia, as on Telegram: the capsule pumps up like a droplet as soon as it moves
    /// (taller and wider, so rounder), then deflates with a soft wobble. The tapped capsule starts
    /// from its press lift. Drive strength as a share of the capsule's height.
    static let glassSwell: CGFloat = 0.5
    static let swellResponse: Double = 0.25
    static let swellDamping: Double = 0.42
    /// Closest the two capsules may come while overshooting, so they never fuse into one blob.
    static let glassMinGap: CGFloat = 10
    /// Glass shapes closer than this merge into one, like the system bar's glass.
    static let glassMergeSpacing: CGFloat = 10
    /// Avatar flight, measured on Telegram: the avatar always travels through the bar row, so
    /// the path curves by itself from two springs. Opening: it slides along the bar on the screens'
    /// spring, while dropping and growing lag behind (start from rest) and land with a small
    /// overshoot. Closing: it rises into the bar first, then slides into the corner.
    static let dropSpring = (response: 0.42, damping: 0.72, launch: 0.0)
    static let growSpring = (response: 0.4, damping: 0.85, launch: 0.5)
    static let riseSpring = (response: 0.22, damping: 1.0, launch: 0.7)
    static let shrinkSpring = (response: 0.28, damping: 1.0, launch: 0.6)

    /// Cross-fades, seconds from the start: (delay, duration).
    static let labelsOut: (delay: Double, duration: Double) = (0, 0.1)
    static let labelsIn: (delay: Double, duration: Double) = (0.07, 0.16)
    static let iconsIn: (delay: Double, duration: Double) = (0.1, 0.18)
    static let iconsOut: (delay: Double, duration: Double) = (0, 0.06)
    static let iconsStartScale: CGFloat = 0.6
    /// Items blur out and in focus as they swap, like Telegram's header buttons.
    static let blurRadius: CGFloat = 6
    /// Small → large avatar cross-fade during the flight (and back for pop).
    static let avatarSwap: (delay: Double, duration: Double) = (0.02, 0.16)
    static let avatarSwapBack: (delay: Double, duration: Double) = (0.08, 0.16)

    /// The tap's glow on the avatar and its glass (measured at full lift: ~35% white on the avatar,
    /// the glass nearly white) carries over into the morph and fades, instead of vanishing in one
    /// frame. Scaled by how far the glass is lifted.
    static let pressGlow: (avatar: CGFloat, glass: CGFloat, duration: Double) = (0.35, 0.6, 0.22)

    static let keyframeCount = 90
}

/// Top-bar geometry of the top-tabs root, in the navigation controller's view coordinates.
struct SettingsMorphSource {
    var segmentedFrame: CGRect
    var segmentedSnapshot: UIView?
    var avatarGlassFrame: CGRect
    var avatarFrame: CGRect
    /// Scale of the tapped interactive glass (the avatar's on push, the back button's on pop),
    /// lifted by the tap: the morph starts from this swollen state instead of snapping to rest.
    var pressLift: CGFloat = 1
}

@available(iOS 26, *)
@MainActor
final class SettingsMorphTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPush: Bool
    private let source: SettingsMorphSource
    private weak var navigationController: UINavigationController?

    init(isPush: Bool, source: SettingsMorphSource, navigationController: UINavigationController) {
        self.isPush = isPush
        self.source = source
        self.navigationController = navigationController
    }

    /// Also the duration of animations UIKit runs alongside, such as the bottom search toolbar.
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        MorphSpring(response: SettingsMorphTiming.response, damping: SettingsMorphTiming.slideDamping, launch: SettingsMorphTiming.launchVelocity).settlingDuration
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let navigationController,
              let fromVC = context.viewController(forKey: .from),
              let toVC = context.viewController(forKey: .to),
              let fromView = context.view(forKey: .from),
              let toView = context.view(forKey: .to),
              let settings = (isPush ? toVC : fromVC) as? SettingsVC else {
            context.completeTransition(!context.transitionWasCancelled)
            return
        }
        let container = context.containerView
        toView.frame = context.finalFrame(for: toVC)
        if isPush {
            container.addSubview(toView)
        } else {
            container.insertSubview(toView, belowSubview: fromView)
        }
        toView.layoutIfNeeded()

        let navView: UIView = navigationController.view
        let overlay = UIView(frame: navView.bounds)
        overlay.isUserInteractionEnabled = false
        navView.addSubview(overlay)
        let bar = navigationController.navigationBar
        // Hide the bar's contents, not the bar: a transparent bar counts as hidden and shifts
        // the screens' safe area, which then jumps back when it reappears.
        let barContents = bar.subviews
        barContents.forEach { $0.alpha = 0 }

        // MARK: Geometry

        // Bar items sit on the 44 pt content row at the top of the bar, not on the bar's middle;
        // the avatar capsule on Home lives on that same row.
        let barMidY = source.avatarGlassFrame.midY
        let width = navView.bounds.width
        let margin = bar.layoutMargins.left > 0 ? bar.layoutMargins.left : 16
        // iOS 26 bar metrics, measured: 44 pt back circle, 100 pt two-item capsule.
        let backFrame = CGRect(x: margin, y: barMidY - 22, width: 44, height: 44)
        let trailingFrame = CGRect(x: width - margin - 100, y: barMidY - 22, width: 100, height: 44)
        let largeAvatar = settings.morphAvatarView
        // Pushed Settings has not followed the bar yet, so its avatar is not in place: use the
        // resting frame. When popping, it is on screen and laid out.
        let largeAvatarFrame = isPush
            ? settings.view.convert(
                settings.morphAvatarRestingFrame(navigationBarMidY: navView.convert(CGPoint(x: 0, y: barMidY), to: settings.view).y),
                to: navView)
            : largeAvatar.convert(largeAvatar.bounds, to: navView)

        // MARK: Stand-ins

        // Both shapes share one glass container, as on the real bar: they flow into each other
        // when close instead of overlapping as two separate panes.
        let glassEffect = UIGlassContainerEffect()
        glassEffect.spacing = SettingsMorphTiming.glassMergeSpacing
        let glassContainer = UIVisualEffectView(effect: glassEffect)
        glassContainer.frame = overlay.bounds
        overlay.addSubview(glassContainer)
        let leftGlass = makeGlass()
        let rightGlass = makeGlass()
        glassContainer.contentView.addSubview(leftGlass)
        glassContainer.contentView.addSubview(rightGlass)

        // The Wallet / Market / Explore labels ride above the glass, unclipped, anchored at the
        // left edge: they fold away towards the back button instead of being cut by the capsule.
        let labels = source.segmentedSnapshot
        if let labels {
            // The snapshot is reused by the pop: reset what the push left on it before sizing.
            labels.transform = .identity
            labels.layer.filters = nil
            labels.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
            labels.frame = source.segmentedFrame
            overlay.addSubview(labels)
        }
        // Same symbol metrics as the bar's own items (measured), so nothing resizes at hand-over.
        let barSymbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold, scale: .large)
        let chevron = makeIcon(UIImage(systemName: "chevron.backward", withConfiguration: barSymbol))
        let qr = makeIcon(UIImage.airBundle("QRIcon").withRenderingMode(.alwaysTemplate))
        let more = makeIcon(UIImage(systemName: "ellipsis", withConfiguration: barSymbol))
        // Icons live inside their glass but hold still on screen at their bar positions: the
        // capsule reveals them as it grows (and covers them as it shrinks), like the system's own
        // bar buttons, and its swelling never pushes them around.
        leftGlass.contentView.addSubview(chevron)
        rightGlass.contentView.addSubview(qr)
        rightGlass.contentView.addSubview(more)
        let iconSpots: [(icon: UIView, glass: UIView, center: CGPoint)] = [
            (chevron, leftGlass, CGPoint(x: backFrame.midX, y: barMidY)),
            (qr, rightGlass, CGPoint(x: trailingFrame.maxX - 77, y: barMidY)),
            (more, rightGlass, CGPoint(x: trailingFrame.maxX - 23, y: barMidY)),
        ]
        let labelsMinX = source.segmentedFrame.minX, labelsWidth = max(source.segmentedFrame.width, 1)
        let layoutContent: (CGRect, CGRect) -> Void = { leftFrame, rightFrame in
            for spot in iconSpots {
                let origin = spot.glass === leftGlass ? leftFrame.origin : rightFrame.origin
                spot.icon.center = CGPoint(x: spot.center.x - origin.x, y: spot.center.y - origin.y)
            }
            // Titles fold with their capsule, so they never stick out past its edge.
            let fold = min(max((leftFrame.maxX - labelsMinX) / labelsWidth, 0.3), 1)
            labels?.transform = CGAffineTransform(scaleX: fold, y: 1)
        }
        let icons: [UIView] = [chevron, qr, more]

        // A live avatar of the large size: crisp at every scale, unlike a snapshot. It lays
        // itself out with constraints, so it rides in a plain frame-based container.
        // Small and large avatars cross-fade on the way: the letter is drawn at different
        // proportions per size, so scaling one into the other would change it at once.
        let avatar = IconView(size: largeAvatarFrame.width)
        avatar.config(with: AccountStore.account)
        let smallAvatar = IconView(size: source.avatarFrame.width)
        smallAvatar.config(with: AccountStore.account)
        let flyer = UIView(frame: CGRect(origin: .zero, size: largeAvatarFrame.size))
        flyer.addSubview(avatar)
        flyer.addSubview(smallAvatar)
        NSLayoutConstraint.activate([
            avatar.centerXAnchor.constraint(equalTo: flyer.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: flyer.centerYAnchor),
            smallAvatar.centerXAnchor.constraint(equalTo: flyer.centerXAnchor),
            smallAvatar.centerYAnchor.constraint(equalTo: flyer.centerYAnchor),
        ])
        flyer.layoutIfNeeded()
        let upscale = largeAvatarFrame.width / max(source.avatarFrame.width, 1)
        smallAvatar.transform = CGAffineTransform(scaleX: upscale, y: upscale)
        overlay.addSubview(flyer)
        let lift = source.pressLift
        if lift > 1.01 {
            let T = SettingsMorphTiming.self
            let glow = min((lift - 1) / 0.3, 1)
            var glows: [UIView] = []
            if isPush {
                let avatarGlow = UIView(frame: flyer.bounds)
                avatarGlow.backgroundColor = .white
                avatarGlow.layer.cornerRadius = flyer.bounds.width / 2
                avatarGlow.alpha = T.pressGlow.avatar * glow
                flyer.addSubview(avatarGlow)
                glows.append(avatarGlow)
            }
            // The tapped button's glass: the avatar's on push, the back button's on pop.
            let pressedGlass = isPush ? rightGlass : leftGlass
            let glassGlow = UIView(frame: pressedGlass.contentView.bounds)
            glassGlow.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            glassGlow.backgroundColor = .white
            glassGlow.alpha = T.pressGlow.glass * glow
            pressedGlass.contentView.insertSubview(glassGlow, at: 0)
            glows.append(glassGlow)
            UIView.animate(withDuration: T.pressGlow.duration, delay: 0, options: [.curveEaseOut]) {
                glows.forEach { $0.alpha = 0 }
            }
        }
        // isHidden: the header drives the avatar's alpha itself.
        largeAvatar.isHidden = true

        // Start / end states, in push order; pop swaps them.
        let barStart = (left: source.segmentedFrame, right: source.avatarGlassFrame)
        let barEnd = (left: backFrame, right: trailingFrame)
        let smallScale = source.avatarFrame.width / max(largeAvatarFrame.width, 1)
        let small = CGPoint(x: source.avatarFrame.midX, y: source.avatarFrame.midY)
        let large = CGPoint(x: largeAvatarFrame.midX, y: largeAvatarFrame.midY)

        let from = isPush ? barStart : barEnd
        let to = isPush ? barEnd : barStart
        setIcons(icons, visible: !isPush)
        labels?.alpha = isPush ? 1 : 0

        let screenWidth = container.bounds.width
        let behind = CGAffineTransform(translationX: -screenWidth * SettingsMorphTiming.parallax, y: 0)
        let offscreen = CGAffineTransform(translationX: screenWidth, y: 0)

        // MARK: Animations

        let T = SettingsMorphTiming.self
        let slide = MorphSpring(response: T.response, damping: T.slideDamping, launch: T.launchVelocity)
        let glass = MorphSpring(response: T.response, damping: T.glassDamping, launch: T.launchVelocity)

        // The transition completes when the screens have landed; stand-ins are removed when every
        // piece has. Both come from animation completions, never timers, so a busy first frame
        // (the device builds Settings then) cannot cut anything short.
        var pendingPieces = 4
        let pieceDone = {
            pendingPieces -= 1
            guard pendingPieces == 0 else { return }
            overlay.removeFromSuperview()
            barContents.forEach { $0.alpha = 1 }
            largeAvatar.isHidden = false
        }

        animateLiquid(leftGlass, rightGlass, from: from, to: to, spring: glass,
                      lifts: isPush ? (0, lift - 1) : (lift - 1, 0), layout: layoutContent, completion: {
            pieceDone()
            pieceDone()
        })

        // The large avatar stays opaque underneath and only the small one on top fades, so the
        // circle never turns pale mid-way (two half-transparent copies would).
        smallAvatar.alpha = isPush ? 1 : 0
        fade(isPush ? T.avatarSwap : T.avatarSwapBack) {
            smallAvatar.alpha = self.isPush ? 0 : 1
        }
        let blur = T.blurRadius
        if isPush {
            fade(T.labelsOut) { labels?.alpha = 0 }
            labels.map { MorphBlur.animate($0, from: 0, to: blur, T.labelsOut) }
            fade(T.iconsIn) { self.setIcons(icons, visible: true) }
            icons.forEach { MorphBlur.animate($0, from: blur, to: 0, T.iconsIn) }
        } else {
            fade(T.iconsOut) { self.setIcons(icons, visible: false) }
            icons.forEach { MorphBlur.animate($0, from: 0, to: blur, T.iconsOut) }
            fade(T.labelsIn) { labels?.alpha = 1 }
            labels.map { MorphBlur.animate($0, from: blur, to: 0, T.labelsIn) }
        }

        // Screens: incoming from the right edge, outgoing drifts behind (reversed for pop).
        let incomingStart = isPush ? offscreen : behind
        let outgoingEnd = isPush ? behind : offscreen
        animateSpring(slide, { p in
            toView.transform = Self.lerp(incomingStart, .identity, p)
            fromView.transform = Self.lerp(.identity, outgoingEnd, p)
        }, completion: {
            fromView.transform = .identity
            toView.transform = .identity
            let finished = !context.transitionWasCancelled
            if !finished { toView.removeFromSuperview() }
            context.completeTransition(finished)
            pieceDone()
        })

        // Avatar: screen space, on the slide's spring so it reaches the header with it.
        CATransaction.begin()
        CATransaction.setCompletionBlock(pieceDone)
        animateFlight(
            of: flyer,
            from: isPush ? small : large, to: isPush ? large : small,
            fromScale: isPush ? smallScale * lift : 1, toScale: isPush ? 1 : smallScale
        )
        CATransaction.commit()
    }

    // MARK: Pieces

    private func makeGlass() -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        return view
    }

    /// Frame and corner radius together, so the capsule stays round in every keyframe
    /// (a capsule corner configuration does not follow keyframed frame changes).
    private static func setCapsule(_ view: UIView, _ frame: CGRect) {
        view.frame = frame
        view.layer.cornerRadius = frame.height / 2
    }

    private func makeIcon(_ image: UIImage?) -> UIImageView {
        let view = UIImageView(image: image)
        view.tintColor = .label
        view.contentMode = .center
        view.sizeToFit()
        // Room around the glyph, so its blur is not cut at the view's edge.
        view.frame = view.frame.insetBy(dx: -8, dy: -8)
        return view
    }

    private func setIcons(_ icons: [UIView], visible: Bool) {
        for icon in icons {
            icon.alpha = visible ? 1 : 0
            let s = visible ? 1 : SettingsMorphTiming.iconsStartScale
            icon.transform = CGAffineTransform(scaleX: s, y: s)
        }
    }

    /// Runs `apply(progress)` along an exact spring, sampled into keyframes on the render server
    /// so it stays smooth while the main thread is busy.
    private func animateSpring(_ spring: MorphSpring, _ apply: @escaping (CGFloat) -> Void,
                               completion: @escaping () -> Void) {
        let duration = spring.settlingDuration
        let n = SettingsMorphTiming.keyframeCount
        let times = (0...n).map { Double($0) / Double(n) }
        apply(0)
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: [.calculationModeLinear]) {
            for index in 1...n {
                let p = CGFloat(spring.value(at: times[index] * duration))
                UIView.addKeyframe(withRelativeStartTime: times[index - 1], relativeDuration: times[index] - times[index - 1]) {
                    apply(index == n ? 1 : p)
                }
            }
        } completion: { _ in completion() }
    }

    /// Both capsules on one spring with liquid inertia: they swell while moving, lagging behind
    /// the motion, and settle with a soft wobble; a gap stays open so they never fuse.
    private func animateLiquid(_ left: UIView, _ right: UIView,
                               from: (left: CGRect, right: CGRect), to: (left: CGRect, right: CGRect),
                               spring: MorphSpring, lifts: (left: CGFloat, right: CGFloat),
                               layout: @escaping (CGRect, CGRect) -> Void,
                               completion: @escaping () -> Void) {
        let leftSwell = Self.swellCurve(of: spring, from: lifts.left)
        let rightSwell = Self.swellCurve(of: spring, from: lifts.right)
        let duration = max(leftSwell.duration, rightSwell.duration)
        let start = (Self.swollen(from.left, leftSwell.value(0)), Self.swollen(from.right, rightSwell.value(0)))
        // A lifted glass may start closer than the minimum gap (UIKit lets it touch its neighbour):
        // the gap opens up over the first moments instead of jumping open.
        let startGap = start.1.minX - start.0.maxX
        func requiredGap(_ t: Double) -> CGFloat {
            let minGap = SettingsMorphTiming.glassMinGap
            guard startGap < minGap else { return minGap }
            let ramp = CGFloat(min(t / 0.12, 1))
            return startGap + (minGap - startGap) * ramp * ramp * (3 - 2 * ramp)
        }
        let n = SettingsMorphTiming.keyframeCount
        let times = (0...n).map { Double($0) / Double(n) }
        func frames(at i: Int) -> (CGRect, CGRect) {
            let t = times[i] * duration
            let p = CGFloat(spring.value(at: min(t, spring.settlingDuration)))
            var l = Self.swollen(Self.capsule(from: from.left, to: to.left, p), leftSwell.value(t))
            var r = Self.swollen(Self.capsule(from: from.right, to: to.right, p), rightSwell.value(t))
            // Keep the gap open: the shrinking left capsule yields first, then the right one.
            var missing = requiredGap(t) - (r.minX - l.maxX)
            if missing > 0 {
                let fromLeft = min(missing, max(l.width - l.height, 0))
                l.size.width -= fromLeft
                missing -= fromLeft
                r.origin.x += missing
                r.size.width = max(r.width - missing, r.height)
            }
            return i == n ? (to.left, to.right) : (l, r)
        }
        Self.setCapsule(left, start.0)
        Self.setCapsule(right, start.1)
        layout(start.0, start.1)
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: [.calculationModeLinear]) {
            for i in 1...n {
                let f = frames(at: i)
                UIView.addKeyframe(withRelativeStartTime: times[i - 1], relativeDuration: times[i] - times[i - 1]) {
                    Self.setCapsule(left, f.0)
                    Self.setCapsule(right, f.1)
                    layout(f.0, f.1)
                }
            }
        } completion: { _ in completion() }
    }

    /// Grown around its center by `grow` (share of its height) on every side, so it stays a capsule.
    private static func swollen(_ frame: CGRect, _ grow: CGFloat) -> CGRect {
        let d = frame.height * grow / 2
        return frame.insetBy(dx: -d, dy: -d)
    }

    /// Swelling over time, as a share of the capsule's height: a damped oscillator pulled by the
    /// capsules' speed (which peaks right at the start), so it pumps up at once and deflates with a
    /// wobble through a slight squash. `initial` is where it starts (the tapped glass's press lift).
    /// Returns the curve and how long the glass needs until motion and wobble are both still.
    private static func swellCurve(of spring: MorphSpring, from initial: CGFloat) -> (value: (Double) -> CGFloat, duration: Double) {
        let T = SettingsMorphTiming.self
        let dt = 1.0 / 600
        let steps = Int(2.0 / dt)
        let speed = (0...steps).map { i -> Double in
            let t = Double(i) * dt
            return abs(spring.value(at: t + dt) - spring.value(at: max(t - dt, 0))) / (2 * dt)
        }
        let topSpeed = max(speed.max() ?? 1, 0.001)
        let omega = 2 * .pi / T.swellResponse
        let drive = Double(T.glassSwell)
        var x = Double(initial), v = 0.0
        var samples = [x]
        var lastActive = 0
        for i in 1...steps {
            v += (omega * omega * (drive * speed[i] / topSpeed - x) - 2 * T.swellDamping * omega * v) * dt
            x += v * dt
            samples.append(x)
            if abs(x) > 0.002 { lastActive = i }
        }
        let duration = max(spring.settlingDuration, Double(lastActive + 1) * dt)
        // Fades to exactly zero at the end, so the hand-over to the real bar cannot pop.
        let value: (Double) -> CGFloat = { t in
            let i = min(max(Int(t / dt), 0), steps)
            let tail = min(max((duration - t) / 0.06, 0), 1)
            return CGFloat(samples[i] * tail)
        }
        return (value, duration)
    }

    /// Capsule between two frames at spring progress `p`. Edges move independently, so overshoot
    /// only stretches the moving edge; an edge that doesn't move between the frames stays put,
    /// and the capsule never gets narrower than a circle.
    private static func capsule(from start: CGRect, to end: CGRect, _ p: CGFloat) -> CGRect {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let height = lerp(start.height, end.height)
        var minX = lerp(start.minX, end.minX), maxX = lerp(start.maxX, end.maxX)
        if maxX - minX < height {
            if abs(start.minX - end.minX) < 0.5 { maxX = minX + height }
            else if abs(start.maxX - end.maxX) < 0.5 { minX = maxX - height }
            else { let mid = (minX + maxX) / 2; minX = mid - height / 2; maxX = mid + height / 2 }
        }
        return CGRect(x: minX, y: lerp(start.midY, end.midY) - height / 2, width: maxX - minX, height: height)
    }

    private static func lerp(_ a: CGAffineTransform, _ b: CGAffineTransform, _ p: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: a.tx + (b.tx - a.tx) * p, y: a.ty + (b.ty - a.ty) * p)
    }

    private func fade(_ timing: (delay: Double, duration: Double), _ animations: @escaping () -> Void) {
        UIView.animate(
            withDuration: timing.duration,
            delay: timing.delay,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: animations
        )
    }

    /// Flies `view` with its own spring per axis: horizontal on the screens' spring (so it stays
    /// above the name sliding in under it), vertical and size per `SettingsMorphTiming`.
    private func animateFlight(of view: UIView, from start: CGPoint, to end: CGPoint, fromScale: CGFloat, toScale: CGFloat) {
        let T = SettingsMorphTiming.self
        func spring(_ c: (response: Double, damping: Double, launch: Double)) -> MorphSpring {
            MorphSpring(response: c.response, damping: c.damping, launch: c.launch)
        }
        let across = MorphSpring(response: T.response, damping: T.slideDamping, launch: T.launchVelocity)
        let vertical = spring(isPush ? T.dropSpring : T.riseSpring)
        let scale = spring(isPush ? T.growSpring : T.shrinkSpring)
        let duration = [across, vertical, scale].map(\.settlingDuration).max() ?? across.settlingDuration

        let n = T.keyframeCount
        let times = (0...n).map { Double($0) / Double(n) }
        func at(_ s: MorphSpring, _ t: Double) -> CGFloat { CGFloat(s.value(at: t * duration)) }
        var positions: [Any] = times.map { t in
            NSValue(cgPoint: CGPoint(
                x: start.x + (end.x - start.x) * at(across, t),
                y: start.y + (end.y - start.y) * at(vertical, t)))
        }
        var scales: [Any] = times.map { t in
            NSNumber(value: Double(fromScale + (toScale - fromScale) * at(scale, t)))
        }
        // Exact end values, so nothing shifts when the real avatar takes over.
        positions[n] = NSValue(cgPoint: end)
        scales[n] = NSNumber(value: Double(toScale))
        view.center = end
        view.transform = CGAffineTransform(scaleX: toScale, y: toScale)
        let keyTimes = times.map { NSNumber(value: $0) }
        for (keyPath, values) in [("position", positions), ("transform.scale", scales)] {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = keyTimes
            animation.calculationMode = .linear
            animation.duration = duration
            view.layer.add(animation, forKey: keyPath)
        }
    }
}

/// Damped spring from 0 to 1, same parameters as SwiftUI `.spring(response:dampingFraction:)`.
struct MorphSpring {
    let response: Double
    let damping: Double
    /// Initial speed as a share of the natural frequency: 0 = starts at rest (slow ramp),
    /// 1 = starts at full speed (critically damped → pure exponential ease-out).
    var launch: Double = 0

    func value(at t: Double) -> Double {
        let omega = 2 * .pi / response
        let v0 = launch * omega
        if damping >= 1 {
            return 1 - (1 + (omega - v0) * t) * exp(-omega * t)
        }
        let damped = omega * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * omega * t) * (cos(damped * t) + (damping * omega - v0) / damped * sin(damped * t))
    }

    /// First time the spring reaches `share` of its target.
    func time(reaching share: Double) -> Double {
        var t = 0.0
        while value(at: t) < share, t < response * 4 { t += 0.002 }
        return t
    }

    /// Time until the spring stays within 0.1% of its target (under half a point on a phone
    /// screen, so nothing visibly snaps when the animation hands over).
    var settlingDuration: Double {
        var t = response * 4
        while t > response * 0.5, abs(1 - value(at: t - 0.01)) < 0.001 {
            t -= 0.01
        }
        return t
    }
}

/// Gaussian blur through Core Animation's filter, the way the system blurs text in and out
/// (class and selector spelled backwards, as in the segmented control's lens). No-op if missing.
@MainActor
private enum MorphBlur {
    private static let name = String("rulBnaissuag".reversed())

    static func animate(_ view: UIView, from: CGFloat, to: CGFloat, _ timing: (delay: Double, duration: Double)) {
        let make = NSSelectorFromString(String(":emaNhtiWretlif".reversed()))
        guard let cls = NSClassFromString(String("retliFAC".reversed())) as? NSObject.Type,
              cls.responds(to: make),
              let filter = cls.perform(make, with: name)?.takeUnretainedValue() as? NSObject else { return }
        filter.setValue(to, forKey: "inputRadius")
        view.layer.filters = [filter]
        let animation = CABasicAnimation(keyPath: "filters.\(name).inputRadius")
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = view.layer.convertTime(CACurrentMediaTime(), from: nil) + timing.delay
        animation.duration = timing.duration
        animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        // A filter left at radius 0 still resamples the layer: drop it once in focus.
        if to == 0 { CATransaction.setCompletionBlock { [weak view] in view?.layer.filters = nil } }
        view.layer.add(animation, forKey: "morphBlur")
        CATransaction.commit()
    }
}

/// UIKit's interactive glass lift on touch, measured (it is rendered outside the app's layers, so
/// it cannot be read back): ×1.36 at full press, ~63% of the way there after 0.05 s.
enum InteractiveGlassLift {
    static func scale(heldFor held: TimeInterval) -> CGFloat {
        1 + 0.36 * CGFloat(1 - exp(-max(held, 0) / 0.05))
    }
}

/// Watches touches on a view without taking part in them, to know how long the last press in an
/// area was held: system bar buttons don't expose their touches.
final class PressTimingRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var downTime: CFTimeInterval = 0
    private var downLocation: CGPoint = .zero
    private var upTime: CFTimeInterval = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// Lift of a press in `area` (recognizer view coordinates) released within the last moment.
    func recentLift(in area: CGRect) -> CGFloat {
        guard CACurrentMediaTime() - upTime < 0.4, upTime >= downTime, area.contains(downLocation) else { return 1 }
        return InteractiveGlassLift.scale(heldFor: upTime - downTime)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        downTime = CACurrentMediaTime()
        downLocation = touches.first?.location(in: view) ?? .zero
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        upTime = CACurrentMediaTime()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        upTime = CACurrentMediaTime()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

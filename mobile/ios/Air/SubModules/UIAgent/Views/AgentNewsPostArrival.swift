import UIKit
import UIComponents
import WalletCore

/// A card of the News feed that flies into its discussion's post: a news item's or a digest's
@MainActor
protocol AgentNewsFlightSource: AnyObject {
    /// A picture of the card and its frame in the window. The picture leaves out the card's tail, which the post shows
    /// as the card lands on it.
    func makeFlightSnapshot() -> (view: UIView, frame: CGRect)?
    /// Hides the card while its picture flies into the discussion, so the feed does not show it twice
    func setFlightSourceHidden(_ isHidden: Bool)
}

/// Flies a news or digest card from the feed into a new discussion's post.
///
/// As soon as the chat sliding in lays the post out, the card leaves the place it had on screen and flies onto the post,
/// turning into it on the way: it lifts toward the viewer with a shadow, leans into its flight in perspective, and drops
/// onto the post on a spring that carries it a little past and back, as a card dropped in place. The flight runs in the
/// navigation host, over both chats as one slides in over the other, follows where the post shows on every frame, and ends with
/// a stand-in configured like the post exactly over it, so the post takes over without a visible change. A post that
/// never shows lets the card fade away where it is.
///
/// The native navigation controls and live copies of the screens' header backdrops remain above the card throughout.
@MainActor
final class AgentNewsPostArrival {
    /// The chat on screen. The chat gives none until it appears, and none once it leaves the screen.
    struct Destination {
        /// The chat's view, which a navigation transition may be moving
        let hostView: UIView
        let cell: AgentNewsPostCell?
        let post: AgentNewsPostView.Content?
        /// Where the chat's header ends, in the window's coordinates
        let contentTop: CGFloat
        let contentBottom: CGFloat
        let headerBackground: UIView?
    }

    /// How far below a header's lower edge its backdrop still covers the content, as `addCustomNavigationBarBackground`
    /// extends it
    static let headerFadeHeight: CGFloat = 18

    private enum Phase {
        case waiting
        case holding
        case flying
        case finished
    }

    /// The flight's spring: it reaches the post in about half a second, a few percent past it, and settles
    private static let flight = GlassSpring(dampingRatio: 0.7, response: 0.55)
    /// How long the card is in the air, lifted and leaning, and how long the card and the post cross-fade
    private static let liftDuration: CGFloat = 0.42
    /// A chat whose post does not appear in time drops the card
    private static let holdTimeout: CFTimeInterval = 2
    /// The post's row may be gone for a moment while the chat reloads it, such as once a new discussion's thread is
    /// made; the card keeps flying to where the post was for this long
    private static let missingPostTolerance: CFTimeInterval = 0.5
    /// At the top of the flight the card is this much larger, leans this far into its flight and casts its shadow
    private static let lift: CGFloat = 0.08
    private static let maximumPitch: CGFloat = 16 * .pi / 180
    private static let maximumYaw: CGFloat = 8 * .pi / 180
    private static let perspectiveDistance: CGFloat = 900
    private static let shadowOpacity: Float = 0.22
    private static let dissolveDuration: TimeInterval = 0.25

    var onFinish: (() -> Void)?

    private let card: UIView
    /// The card's frame in the window
    private let cardFrame: CGRect
    private let destinationProvider: () -> Destination?
    /// Holds the card from takeoff to landing, shown only below the headers
    let flightView = UIView()
    private let headerMask = CAGradientLayer()
    /// Where the headers end, in the window's coordinates: the flight shows only below it
    private(set) var contentTop: CGFloat
    private var contentBottom: CGFloat = .greatestFiniteMagnitude
    /// Holds the card and the stand-in over the flying frame, so they lean and lift together
    private let flightContainer = UIView()
    private var flightCurve = GlassSpringCurve.constant(0)
    private var phase = Phase.waiting
    private var phaseStartedAt: CFTimeInterval = 0
    private var hasSeenDestination = false
    /// Ticks the flight and keeps the arrival alive until it finishes
    private var clock: GlassMotionClock?
    private weak var window: UIWindow?
    private weak var navigationHost: UINavigationController?
    private struct HeaderBackdrop {
        weak var source: UIView?
        let wasHidden: Bool
    }
    private var headerBackdrops: [HeaderBackdrop] = []
    private var headerBackdropCopy: UIView?
    private var headerBackdropFrame = CGRect.zero
    private var headerHostSize = CGSize.zero
    private weak var hiddenCell: AgentNewsPostCell?
    private var standIn: AgentNewsPostCell?
    /// The stand-in's bubble in its own coordinates
    private var standInBubble: CGRect = .zero
    /// Where the body of the post's bubble last was in the window, and since when its row has been missing
    private var lastBodyTarget: CGRect?
    private var missingPostSince: CFTimeInterval?

    init(card: UIView, frame: CGRect, contentTop: CGFloat, destination: @escaping () -> Destination?) {
        self.card = card
        cardFrame = frame
        self.contentTop = contentTop
        destinationProvider = destination
        card.isUserInteractionEnabled = false
        card.accessibilityElementsHidden = true
        flightView.isUserInteractionEnabled = false
        flightView.accessibilityElementsHidden = true
        flightContainer.layer.shadowColor = UIColor.black.cgColor
        flightContainer.layer.shadowOpacity = 0
        flightContainer.layer.shadowRadius = 18
        flightContainer.layer.shadowOffset = CGSize(width: 0, height: 10)
        flightView.addSubview(flightContainer)
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        let opaque = UIColor.black.cgColor
        headerMask.colors = [clear, clear, opaque, opaque, clear, clear]
        flightView.layer.mask = headerMask
    }

    /// Keeps the post hidden until the card lands on it. The chat calls this whenever it configures the post's cell.
    func hidePost(in cell: AgentNewsPostCell) {
        guard phase != .finished else { return }
        track(cell)
    }

    /// Holds the card in the window, where the feed showed it, until the chat sliding in lays the post out
    func start(in window: UIWindow, navigationHost: UINavigationController? = nil, sourceHeaderBackground: UIView? = nil) {
        guard phase == .waiting else { return }
        phase = .holding
        phaseStartedAt = CACurrentMediaTime()
        self.window = window
        if let navigationHost, navigationHost.view.window === window,
           let chrome = navigationChrome(in: navigationHost) {
            self.navigationHost = navigationHost
            flightView.frame = navigationHost.view.bounds
            navigationHost.view.insertSubview(flightView, belowSubview: chrome)
        }
        if flightView.superview == nil {
            flightView.frame = window.bounds
            window.addSubview(flightView)
        }
        trackHeaderBackground(sourceHeaderBackground)
        updateHeaderMask()
        card.frame = window.convert(cardFrame, to: flightView)
        flightView.insertSubview(card, belowSubview: flightContainer)
        let clock = GlassMotionClock(frameRateRange: nil) { _ in self.tick() }
        self.clock = clock
        clock.start()
        tick()
    }

    func cancel() {
        finish()
    }

    private func tick() {
        guard let destination = destinationProvider() else {
            if hasSeenDestination || CACurrentMediaTime() - phaseStartedAt > Self.holdTimeout {
                finish()
            }
            return
        }
        hasSeenDestination = true
        // The navigation host is outside both sliding screens and below the real glass navigation controls.
        if let host = navigationHost?.view ?? window { flightView.frame = host.bounds }
        trackHeaderBackground(destination.headerBackground)
        updateChromeOrder()
        updateHeaderBackgrounds()
        track(destination.cell)
        contentTop = destination.contentTop
        if destination.contentBottom > contentTop {
            contentBottom = destination.contentBottom
        }
        updateHeaderMask()
        switch phase {
        case .holding:
            // The card takes off as soon as the post is laid out, while the chat still slides in
            if let cell = destination.cell, let post = destination.post,
               cell.window != nil, cell.postView.bounds.height > AgentBubbleBackgroundView.tailBottomOverflow {
                beginFlight(in: destination, cell: cell, post: post)
            } else if CACurrentMediaTime() - phaseStartedAt > Self.holdTimeout {
                dissolve()
            }
        case .flying:
            updateFlight(in: destination)
        case .waiting, .finished:
            break
        }
    }

    private func navigationChrome(in navigation: UINavigationController) -> UIView? {
        var chrome: UIView = navigation.navigationBar
        while let parent = chrome.superview, parent !== navigation.view { chrome = parent }
        return chrome.superview === navigation.view ? chrome : nil
    }

    private func updateChromeOrder() {
        guard let navigationHost, let host = navigationHost.view,
              let chrome = navigationChrome(in: navigationHost) else { return }
        if let copy = headerBackdropCopy,
           let chromeIndex = host.subviews.firstIndex(of: chrome),
           host.subviews.firstIndex(of: copy) != chromeIndex - 1 {
            host.insertSubview(copy, belowSubview: chrome)
        }
        let upperView = headerBackdropCopy ?? chrome
        if let upperIndex = host.subviews.firstIndex(of: upperView),
           host.subviews.firstIndex(of: flightView) != upperIndex - 1 {
            host.insertSubview(flightView, belowSubview: upperView)
        }
    }

    private func beginFlight(in destination: Destination, cell: AgentNewsPostCell, post: AgentNewsPostView.Content) {
        guard window != nil else {
            finish()
            return
        }

        // A cell as wide as the post, with the chat's traits and as tall as its own bubble needs, lays the bubble out
        // like the post, whose row may not have its final height yet while the chat slides in
        let width = cell.bounds.width
        let standIn = AgentNewsPostCell(frame: CGRect(origin: .zero, size: CGSize(width: width, height: cell.postView.bounds.height)))
        standIn.isUserInteractionEnabled = false
        standIn.accessibilityElementsHidden = true
        standIn.alpha = 0
        flightContainer.addSubview(standIn)
        standIn.configure(with: post)
        standIn.matchTail(of: cell)
        standIn.layoutIfNeeded()
        let fittingHeight = standIn.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        if fittingHeight > AgentBubbleBackgroundView.tailBottomOverflow {
            standIn.bounds.size.height = fittingHeight
            standIn.layoutIfNeeded()
        }
        standInBubble = standIn.postView.convert(standIn.postView.bounds, to: standIn)
        self.standIn = standIn

        card.removeFromSuperview()
        card.transform = .identity
        card.bounds = CGRect(origin: .zero, size: cardFrame.size)
        flightContainer.insertSubview(card, at: 0)

        phase = .flying
        phaseStartedAt = CACurrentMediaTime()
        flightCurve = GlassSpringCurve(startTime: phaseStartedAt, from: 0, target: 1, spring: Self.flight)
        updateFlight(in: destination)
    }

    private func updateFlight(in destination: Destination) {
        guard let window, let standIn, standInBubble.height > AgentBubbleBackgroundView.tailBottomOverflow else {
            finish()
            return
        }
        let now = CACurrentMediaTime()
        let cell = destination.cell
        let bodyTarget: CGRect
        if let cell {
            let postView = cell.postView
            let bubble = postView.convert(postView.bounds, to: destination.hostView)
            let bubbleTarget = destination.hostView.convertAsShown(bubble, to: flightView)
            // The post's tail, while it has one, hangs below the body the card lands on
            bodyTarget = CGRect(
                x: bubbleTarget.minX,
                y: bubbleTarget.minY,
                width: bubbleTarget.width,
                height: max(1, bubbleTarget.height - cell.postTailOverflow)
            )
            lastBodyTarget = bodyTarget
            missingPostSince = nil
        } else if let lastBodyTarget, now - (missingPostSince ?? now) < Self.missingPostTolerance {
            // The post's row is being reloaded: fly on to where the post was
            missingPostSince = missingPostSince ?? now
            bodyTarget = lastBodyTarget
        } else {
            // The post left the screen; there is nothing to land on
            finish()
            return
        }
        let sourceFrame = window.convert(cardFrame, to: flightView)
        let elapsed = CGFloat(now - phaseStartedAt)
        let progress = flightCurve.getValue(at: now)
        // Past the post the spring carries only the frame, a few percent, while the card is already down
        let time = min(1, elapsed / Self.liftDuration)
        let height = sin(.pi * time)
        let center = CGPoint(
            x: Self.interpolate(sourceFrame.midX, bodyTarget.midX, progress),
            y: Self.interpolate(sourceFrame.midY, bodyTarget.midY, progress)
        )
        let body = CGSize(
            width: max(1, Self.interpolate(sourceFrame.width, bodyTarget.width, progress)),
            height: max(1, Self.interpolate(sourceFrame.height, bodyTarget.height, progress))
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flightContainer.bounds = CGRect(origin: .zero, size: body)
        flightContainer.center = center
        flightContainer.layer.transform = makeFlightTransform(height: height, from: sourceFrame, to: bodyTarget)
        flightContainer.layer.shadowOpacity = Self.shadowOpacity * Float(height)
        flightContainer.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: body),
            cornerRadius: 20
        ).cgPath
        card.center = CGPoint(x: body.width / 2, y: body.height / 2)
        card.transform = CGAffineTransform(
            scaleX: body.width / max(1, cardFrame.width),
            y: body.height / max(1, cardFrame.height)
        )
        // The stand-in's bubble body covers the flying frame and its tail, if any, hangs below it, as on the post
        let scaleX = body.width / max(1, standInBubble.width)
        let scaleY = body.height / max(1, standInBubble.height - standIn.postTailOverflow)
        standIn.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        standIn.center = CGPoint(
            x: -scaleX * (standInBubble.minX - standIn.bounds.midX),
            y: -scaleY * (standInBubble.minY - standIn.bounds.midY)
        )
        standIn.alpha = Self.smoothstep(from: 0.05, to: 0.4, time)
        card.alpha = 1 - Self.smoothstep(from: 0.3, to: 0.7, time)
        CATransaction.commit()

        if now >= flightCurve.restTime, elapsed >= Self.liftDuration, let cell {
            land(on: cell)
        }
    }

    /// Hides what of the flight is above `contentTop` and fades it in over the header's backdrop below it
    private func updateHeaderMask() {
        let height = max(1, flightView.bounds.height)
        let topY = window.map { flightView.convert(CGPoint(x: 0, y: contentTop), from: $0).y } ?? contentTop
        let bottomY = window.map { flightView.convert(CGPoint(x: 0, y: contentBottom), from: $0).y } ?? contentBottom
        let top = min(max(0, topY), height)
        let headerEnd = min(top + Self.headerFadeHeight, height)
        let bottom = max(headerEnd, min(bottomY, height))
        let footerStart = max(headerEnd, bottom - AgentVCLayout.bottomEdgeFadeHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headerMask.frame = flightView.bounds
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        let opaque = UIColor.black.cgColor
        headerMask.colors = navigationHost != nil
            ? [opaque, opaque, opaque, opaque, clear, clear]
            : [clear, clear, opaque, opaque, clear, clear]
        headerMask.locations = [0, top / height, headerEnd / height, footerStart / height, bottom / height, 1]
            .map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }

    private func trackHeaderBackground(_ background: UIView?) {
        guard let host = navigationHost?.view, let background,
              !headerBackdrops.contains(where: { $0.source === background }) else { return }
        if headerBackdropCopy == nil {
            guard let copy = WViewController.makeCustomNavigationBarBackgroundCopy(of: background) else { return }
            copy.accessibilityIdentifier = "AgentFlightHeaderBackdrop"
            // A visual-effect backdrop must remain outside the flight's masked render group.
            host.insertSubview(copy, aboveSubview: flightView)
            headerBackdropCopy = copy
        }
        headerBackdrops.append(HeaderBackdrop(source: background, wasHidden: background.isHidden))
        updateHeaderBackgrounds()
    }

    private func updateHeaderBackgrounds() {
        guard let copy = headerBackdropCopy, let host = copy.superview else { return }
        if headerHostSize != host.bounds.size {
            headerHostSize = host.bounds.size
            headerBackdropFrame = .zero
        }
        for source in headerBackdrops.compactMap(\.source) where source.window != nil && source.bounds.height > 0 {
            let frame = source.convertAsShown(to: host)
            if headerBackdropFrame.isEmpty {
                headerBackdropFrame = frame
            } else {
                headerBackdropFrame = headerBackdropFrame.union(frame)
            }
        }
        guard !headerBackdropFrame.isEmpty else { return }
        if let navigationHost {
            let barBottom = navigationHost.navigationBar.convertAsShown(to: host).maxY
            headerBackdropFrame.size.height = max(headerBackdropFrame.height,
                                                 barBottom + Self.headerFadeHeight - headerBackdropFrame.minY)
        }
        // The incoming screen may not yet have its navigation safe area. Keep the fully laid-out header's extent.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        copy.frame = CGRect(x: 0, y: headerBackdropFrame.minY, width: host.bounds.width, height: headerBackdropFrame.height)
        copy.layoutIfNeeded()
        for backdrop in headerBackdrops { backdrop.source?.isHidden = true }
        CATransaction.commit()
    }

    private func removeFlightView() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for backdrop in headerBackdrops {
            backdrop.source?.isHidden = backdrop.wasHidden
        }
        headerBackdrops.removeAll()
        headerBackdropCopy?.removeFromSuperview()
        headerBackdropCopy = nil
        headerBackdropFrame = .zero
        headerHostSize = .zero
        flightView.removeFromSuperview()
        CATransaction.commit()
    }

    /// Lifted toward the viewer by `height`, from 0 on the ground to 1 at the top of the flight, and leaning into the
    /// flight from `source` to `target`: its leading edge dips away in the direction it flies
    private func makeFlightTransform(height: CGFloat, from source: CGRect, to target: CGRect) -> CATransform3D {
        let vertical = target.midY - source.midY
        let horizontal = target.midX - source.midX
        let pitch = Self.maximumPitch * height * (vertical < 0 ? 1 : -1) * min(1, abs(vertical) / 120)
        let yaw = Self.maximumYaw * height * max(-1, min(1, horizontal / 160))
        let scale = 1 + Self.lift * height
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / Self.perspectiveDistance
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(pitch, 1, 0, 0))
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(yaw, 0, 1, 0))
        return CATransform3DConcat(transform, perspective)
    }

    private func land(on cell: AgentNewsPostCell) {
        // The suggestions under the post, hidden with it so far, appear as the post takes over from the card
        cell.revealFollowups()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        show(cell)
        card.removeFromSuperview()
        removeFlightView()
        CATransaction.commit()
        stop()
    }

    /// Lets the card fade away where it is, for a post that never shows
    private func dissolve() {
        guard phase != .finished else { return }
        let card = card
        if let hiddenCell {
            show(hiddenCell)
        }
        stop()
        guard card.superview != nil else {
            removeFlightView()
            return
        }
        UIView.animate(
            withDuration: Self.dissolveDuration,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            card.alpha = 0
            card.transform = card.transform.scaledBy(x: 0.92, y: 0.92)
        } completion: { [self] _ in
            card.removeFromSuperview()
            removeFlightView()
        }
    }

    private func finish() {
        card.removeFromSuperview()
        removeFlightView()
        if let hiddenCell {
            show(hiddenCell)
        }
        stop()
    }

    private func stop() {
        guard phase != .finished else { return }
        phase = .finished
        clock?.stop()
        clock = nil
        standIn?.removeFromSuperview()
        standIn = nil
        onFinish?()
        onFinish = nil
    }

    /// Hides whichever cell shows the post now and shows a cell it no longer shows. While the post's row is being
    /// reloaded there is none, and the hidden cell stays hidden.
    private func track(_ cell: AgentNewsPostCell?) {
        guard let cell, cell !== hiddenCell else { return }
        if let hiddenCell {
            show(hiddenCell)
        }
        cell.contentView.alpha = 0
        hiddenCell = cell
    }

    private func show(_ cell: AgentNewsPostCell) {
        cell.contentView.alpha = 1
        if hiddenCell === cell {
            hiddenCell = nil
        }
    }

    private static func interpolate(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private static func smoothstep(from start: CGFloat, to end: CGFloat, _ value: CGFloat) -> CGFloat {
        let fraction = min(1, max(0, (value - start) / (end - start)))
        return fraction * fraction * (3 - 2 * fraction)
    }
}

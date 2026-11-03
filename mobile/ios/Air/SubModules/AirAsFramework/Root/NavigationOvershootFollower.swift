import UIKit
import UIComponents

/// Follows the screens of a navigation transition past their resting place. A fast swipe back springs the screen
/// underneath a little past the leading edge, baring the window's background beside it; chrome that floats over the
/// screens moves along with them, so none of it shows over the background.
@MainActor
final class NavigationOvershootFollower {
    /// How far the screens have sprung past the container's edges along x, positive toward the trailing side of the
    /// screen, 0 while they cover the container; and the corner radius the transition draws the screens with, for
    /// chrome to be clipped as they are, 0 once it ends
    typealias Handler = @MainActor (_ offset: CGFloat, _ cornerRadius: CGFloat) -> Void

    private static var running: [ObjectIdentifier: NavigationOvershootFollower] = [:]
    /// Longer than any navigation spring, in case the transition never reports its end
    private static let timeLimit: CFTimeInterval = 3

    private weak var containerView: UIView?
    private let pages: [WeakPage]
    private let handler: Handler
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.step() }
    private var startTime = CACurrentMediaTime()
    private var isTransitionComplete = false
    private var offset: CGFloat = 0
    private var cornerRadius: CGFloat = 0

    /// Calls `handler` on the frames of the transition that change the screens' overshoot or rounding, and with 0
    /// for both once the transition ends and the screens settle
    static func follow(_ coordinator: any UIViewControllerTransitionCoordinator, handler: @escaping Handler) {
        let pages = [UITransitionContextViewControllerKey.from, .to].compactMap { coordinator.viewController(forKey: $0)?.view }
        let follower = NavigationOvershootFollower(containerView: coordinator.containerView, pages: pages, handler: handler)
        let key = ObjectIdentifier(follower)
        running[key] = follower
        follower.clock.start()
        let accepted = coordinator.animate(alongsideTransition: nil) { _ in
            follower.isTransitionComplete = true
            follower.step()
        }
        if !accepted {
            follower.stop()
        }
    }

    private init(containerView: UIView, pages: [UIView], handler: @escaping Handler) {
        self.containerView = containerView
        self.pages = pages.map { WeakPage($0) }
        self.handler = handler
    }

    private func step() {
        let (offset, cornerRadius) = measure()
        if offset != self.offset || cornerRadius != self.cornerRadius {
            self.offset = offset
            self.cornerRadius = cornerRadius
            handler(offset, cornerRadius)
        }
        if (isTransitionComplete && offset == 0) || CACurrentMediaTime() - startTime > Self.timeLimit {
            stop()
        }
    }

    private func stop() {
        clock.stop()
        if offset != 0 || cornerRadius != 0 {
            offset = 0
            cornerRadius = 0
            handler(0, 0)
        }
        Self.running[ObjectIdentifier(self)] = nil
    }

    /// The screens' overshoot past the container's edges, as they are drawn on this frame
    private func measure() -> (offset: CGFloat, cornerRadius: CGFloat) {
        guard let containerView, let containerLayer = containerView.layer.presentation() else { return (0, 0) }
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var cornerRadius: CGFloat = 0
        for page in pages.compactMap(\.value) where page.window != nil {
            guard let layer = page.layer.presentation() else { continue }
            let frame = layer.convert(layer.bounds, to: containerLayer)
            minX = min(minX, frame.minX)
            maxX = max(maxX, frame.maxX)
            cornerRadius = max(cornerRadius, Self.getCornerRadius(around: page, in: containerView))
        }
        guard minX.isFinite, maxX.isFinite else { return (0, 0) }
        // Screens that fill the window are rounded as the display is, by a clip outside their own views
        if cornerRadius == 0, let window = containerView.window,
           containerView.convert(containerView.bounds, to: window).size == window.bounds.size {
            cornerRadius = AgentDisplayCornerRadius.getRadius(for: window)
        }
        let leadingGap = minX
        let trailingGap = containerLayer.bounds.width - maxX
        if leadingGap > 0.5 {
            return (leadingGap, cornerRadius)
        }
        if trailingGap > 0.5 {
            return (-trailingGap, cornerRadius)
        }
        return (0, cornerRadius)
    }

    /// The rounding the transition clips a screen with: its own, or that of a view around it in the container
    private static func getCornerRadius(around page: UIView, in containerView: UIView) -> CGFloat {
        var view: UIView? = page
        while let current = view, current !== containerView {
            let radius = current.layer.presentation()?.cornerRadius ?? current.layer.cornerRadius
            if radius > 0, current.layer.masksToBounds || current.clipsToBounds {
                return radius
            }
            view = current.superview
        }
        return 0
    }
}

private struct WeakPage {
    weak var value: UIView?

    init(_ value: UIView) {
        self.value = value
    }
}

import UIKit

/// Observes orthogonal collection-view scrolling without replacing UIKit's private delegate.
@MainActor
public final class ScrollActivityMonitor: NSObject {
    public var onActivityChanged: (Bool) -> Void
    public private(set) var isScrolling = false
    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var displayLink: CADisplayLink?
    private var lastMovement: CFTimeInterval = 0
    private var lastOffset = CGPoint.zero

    public init(onActivityChanged: @escaping (Bool) -> Void) {
        self.onActivityChanged = onActivityChanged
    }

    public func attach(to scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        self.scrollView = scrollView
        lastOffset = scrollView.contentOffset
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
        observation = scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                guard let self, self.lastOffset != scrollView.contentOffset else { return }
                self.lastOffset = scrollView.contentOffset
                self.beginScrolling()
            }
        }
    }

    public func detach() {
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
        observation = nil
        scrollView = nil
        finishScrolling()
    }

    /// Call before starting an animated programmatic scroll, so balance updates are suspended immediately.
    public func beginScrolling() {
        lastMovement = CACurrentMediaTime()
        if !isScrolling {
            isScrolling = true
            onActivityChanged(true)
        }
        if displayLink == nil {
            let target = ScrollDisplayLinkTarget { [weak self] in self?.tick() }
            let link = CADisplayLink(target: target, selector: #selector(ScrollDisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func panChanged() {
        beginScrolling()
    }

    private func tick() {
        guard let scrollView, scrollView.window != nil else {
            finishScrolling()
            return
        }
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            lastMovement = CACurrentMediaTime()
            return
        }
        // Also covers programmatic animations and the handoff from dragging to deceleration.
        if CACurrentMediaTime() - lastMovement >= 0.08 { finishScrolling() }
    }

    private func finishScrolling() {
        displayLink?.invalidate()
        displayLink = nil
        if isScrolling {
            isScrolling = false
            onActivityChanged(false)
        }
    }

    deinit { displayLink?.invalidate() }
}

private final class ScrollDisplayLinkTarget: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}

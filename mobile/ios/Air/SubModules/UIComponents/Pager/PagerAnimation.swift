import UIKit

/// One clock for page geometry and the logical offset shown by its tab control.
@MainActor
final class PagerAnimation {
    private var displayLink: CADisplayLink?
    private var generation = 0
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 0
    private var update: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?

    var isRunning: Bool { displayLink != nil }

    func start(duration: TimeInterval, update: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        cancel()
        self.duration = duration
        self.update = update
        self.completion = completion
        startTime = CACurrentMediaTime()
        let target = DisplayLinkTarget { [weak self] in self?.tick() }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
        displayLink = link
        link.add(to: .main, forMode: .common)
        update(0)
    }

    func cancel() {
        generation += 1
        displayLink?.invalidate()
        displayLink = nil
        update = nil
        completion = nil
    }

    private func tick() {
        let generation = generation
        let elapsed = min(1, (CACurrentMediaTime() - startTime) / duration)
        update?(1 - pow(1 - elapsed, 3))
        guard self.generation == generation, elapsed >= 1 else { return }
        let completion = completion
        cancel()
        completion?()
    }

    deinit { displayLink?.invalidate() }

    @MainActor private final class DisplayLinkTarget: NSObject {
        let update: () -> Void
        init(update: @escaping () -> Void) { self.update = update }
        @objc func tick() { update() }
    }
}

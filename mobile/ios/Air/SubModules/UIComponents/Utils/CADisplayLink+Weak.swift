import UIKit

extension CADisplayLink {
    /// A display link on the main run loop, in common modes, that does not keep `owner` alive. A display link retains
    /// its target, so one that targets its owner keeps it alive until invalidated. This one calls `tick` while `owner`
    /// exists and invalidates itself on the first frame after `owner` is gone. A paused link gets no frames, so an owner
    /// that pauses its link invalidates it in `deinit`.
    @MainActor
    public static func makeWeak<Owner: AnyObject>(
        owner: Owner,
        frameRateRange: CAFrameRateRange? = nil,
        tick: @escaping (Owner, CADisplayLink) -> Void
    ) -> CADisplayLink {
        let target = WeakDisplayLinkTarget { [weak owner] link in
            guard let owner else {
                link.invalidate()
                return
            }
            tick(owner, link)
        }
        let link = CADisplayLink(target: target, selector: #selector(WeakDisplayLinkTarget.handleFrame(_:)))
        if let frameRateRange {
            link.preferredFrameRateRange = frameRateRange
        }
        link.add(to: .main, forMode: .common)
        return link
    }
}

@MainActor
private final class WeakDisplayLinkTarget: NSObject {
    private let tick: (CADisplayLink) -> Void

    init(tick: @escaping (CADisplayLink) -> Void) {
        self.tick = tick
    }

    @objc func handleFrame(_ link: CADisplayLink) {
        tick(link)
    }
}

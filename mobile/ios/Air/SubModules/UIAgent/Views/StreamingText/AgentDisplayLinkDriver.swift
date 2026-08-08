import QuartzCore
import UIKit

@MainActor
final class AgentDisplayLinkDriver {
    static let shared = AgentDisplayLinkDriver()

    private var subscribers: [UUID: () -> Void] = [:]
    private var displayLink: CADisplayLink?

    private init() {}

    @discardableResult
    func add(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        return id
    }

    func remove(_ id: UUID) {
        subscribers.removeValue(forKey: id)

        if subscribers.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @objc private func handleDisplayLink() {
        let handlers = Array(subscribers.values)
        for handler in handlers {
            handler()
        }
    }
}

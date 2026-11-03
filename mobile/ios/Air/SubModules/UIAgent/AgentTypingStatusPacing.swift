import Foundation
import QuartzCore

@MainActor
final class AgentTypingStatusPacing {
    private let minimumDuration: TimeInterval
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private let onUpdate: () -> Void
    private var shownTypingStatusText: String?
    private var typingStatusShownAt: TimeInterval = 0
    private var pendingTypingStatusUpdate: DispatchWorkItem?

    init(
        minimumDuration: TimeInterval,
        now: @escaping () -> TimeInterval = CACurrentMediaTime,
        schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, update in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: update)
        },
        onUpdate: @escaping () -> Void
    ) {
        self.minimumDuration = minimumDuration
        self.now = now
        self.schedule = schedule
        self.onUpdate = onUpdate
    }

    func typingStatusText(_ statusText: String?) -> String? {
        guard statusText != shownTypingStatusText else { return statusText }
        let remainingDuration = minimumDuration - (now() - typingStatusShownAt)
        if shownTypingStatusText != nil, remainingDuration > 0 {
            scheduleTypingStatusUpdate(after: remainingDuration)
            return shownTypingStatusText
        }
        shownTypingStatusText = statusText
        typingStatusShownAt = now()
        return statusText
    }

    private func scheduleTypingStatusUpdate(after delay: TimeInterval) {
        guard pendingTypingStatusUpdate == nil else { return }
        let update = DispatchWorkItem { [weak self] in
            self?.pendingTypingStatusUpdate = nil
            self?.onUpdate()
        }
        pendingTypingStatusUpdate = update
        schedule(delay, update)
    }
}

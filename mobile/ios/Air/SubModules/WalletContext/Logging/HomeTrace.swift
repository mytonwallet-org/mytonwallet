import Foundation
import QuartzCore

/// Enable with HOME_TRACE=1 or the launch arguments -HomeTrace YES.
public enum HomeTrace {
    public static let isEnabled = ProcessInfo.processInfo.environment["HOME_TRACE"] == "1"
        || UserDefaults.standard.bool(forKey: "HomeTrace")

    @TaskLocal public static var cause: UInt64?

    private static let log = Log("HomeTrace")
    private static let sequence = UnfairLock(initialState: UInt64(0))
    private static let origin = CACurrentMediaTime()

    public static var now: TimeInterval { CACurrentMediaTime() }

    public static func milliseconds(since start: TimeInterval) -> String {
        String(format: "%.2f", (now - start) * 1_000)
    }

    @discardableResult
    public static func record(
        _ event: String,
        _ details: @autoclosure () -> String = "",
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) -> UInt64? {
        guard isEnabled else { return nil }
        let id = sequence.withLock { value in
            value += 1
            return value
        }
        let elapsed = milliseconds(since: origin)
        let parent = cause.map(String.init) ?? "-"
        log.info(
            "[HomeTrace] #\(id) t_ms=\(elapsed, .public) cause=\(parent, .public) \(event, .public) \(details(), .public)",
            fileID: fileID,
            function: function,
            line: line
        )
        return id
    }
}

#if DEBUG || HOME_FRAME_PROBE
/// Opt-in simulator frame-pacing evidence; this does not measure GPU presentation deadlines.
@MainActor
public final class HomeFrameProbe: NSObject {
    public static let shared = HomeFrameProbe()
    private let enabled = UserDefaults.standard.bool(forKey: "HomeFrameProbe")
    private var displayLink: CADisplayLink?
    private var previousTimestamp: TimeInterval = 0
    private var finishAt: TimeInterval = 0
    private var frames: [[Double]] = []
    private var startedAt: TimeInterval = 0
    private var commits: [Double] = []
    private var events: [[String: Any]] = []
    private var sequence = 0

    public func begin() {
        guard enabled else { return }
        finishAt = CACurrentMediaTime() + 2
        guard displayLink == nil else { return }
        startedAt = CACurrentMediaTime()
        previousTimestamp = 0
        frames.removeAll(keepingCapacity: true)
        commits.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func commit() {
        guard enabled, displayLink != nil else { return }
        commits.append((CACurrentMediaTime() - startedAt) * 1_000)
    }

    public func event(_ name: String) {
        guard enabled, displayLink != nil else { return }
        events.append(["name": name, "at_ms": (CACurrentMediaTime() - startedAt) * 1_000])
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if previousTimestamp != 0 {
            frames.append([(link.timestamp - startedAt) * 1_000,
                           (link.timestamp - previousTimestamp) * 1_000,
                           (link.targetTimestamp - link.timestamp) * 1_000,
                           (now - link.targetTimestamp) * 1_000])
        }
        previousTimestamp = link.timestamp
        guard now >= finishAt else { return }
        link.invalidate()
        displayLink = nil
        sequence += 1
        let result: [String: Any] = ["sequence": sequence, "commits_ms": commits,
                                     "frames": frames, "events": events,
                                     "columns": ["elapsed_ms", "interval_ms", "budget_ms", "callback_lateness_ms"]]
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("home-frames-\(ProcessInfo.processInfo.processIdentifier)-\(sequence).json")
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif

import Foundation
import os

public enum StartupTrace {
    private struct State: Sendable {
        var sequence = 0
        var flow = "process-launch"
        var origin = appStart
        var lastMark = appStart
        var seenSteps = Set<String>()
        var activeIntervals = [String: OSSignpostIntervalState]()
    }

    private static let log = Log("Startup")
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "org.mytonwallet.app",
        category: "Startup"
    )
    private static let state = UnfairLock(initialState: State())

    public static func reset(flow: String, origin: Date = .now, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        let sequence = state.withLock { state in
            state.sequence += 1
            state.flow = flow
            state.origin = origin
            state.lastMark = origin
            state.seenSteps.removeAll(keepingCapacity: true)
            state.activeIntervals.removeAll(keepingCapacity: true)
            return state.sequence
        }

        log.info(
            "startup[\(sequence, .public):\(flow, .public)] reset",
            fileID: fileID,
            function: function,
            line: line
        )
        signposter.emitEvent("StartupReset", "startup[\(sequence):\(flow)] reset")
    }

    public static func mark(_ step: String, details: String? = nil, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        record(step: step, details: details, once: false, fileID: fileID, function: function, line: line)
    }

    public static func markOnce(_ step: String, details: String? = nil, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        record(step: step, details: details, once: true, fileID: fileID, function: function, line: line)
    }

    private static func record(step: String, details: String?, once: Bool, fileID: String, function: String, line: Int) {
        let result = state.withLock { state -> (Int, String, Double, Double, Bool) in
            if once, !state.seenSteps.insert(step).inserted {
                return (state.sequence, state.flow, 0, 0, false)
            }

            let now = Date()
            let delta = now.timeIntervalSince(state.lastMark)
            let total = now.timeIntervalSince(state.origin)
            state.lastMark = now
            return (state.sequence, state.flow, delta, total, true)
        }

        guard result.4 else {
            return
        }

        let message: String
        if let details {
            message = "startup[\(result.0):\(result.1)] \(step) delta=\(format(result.2))s total=\(format(result.3))s \(details)"
        } else {
            message = "startup[\(result.0):\(result.1)] \(step) delta=\(format(result.2))s total=\(format(result.3))s"
        }

        log.info(
            "\(message, .public)",
            fileID: fileID,
            function: function,
            line: line
        )
        signposter.emitEvent("StartupStep", "\(message)")
    }

    public static func beginInterval(_ name: String, details: String? = nil) {
        let context = state.withLock { state in
            (state.sequence, state.flow)
        }
        let intervalState = signposter.beginInterval(
            "StartupPhase",
            id: signposter.makeSignpostID(),
            "\(intervalMessage(sequence: context.0, flow: context.1, name: name, details: details, action: "begin"))"
        )
        state.withLock { state in
            state.activeIntervals[name] = intervalState
        }
    }

    public static func endInterval(_ name: String, details: String? = nil) {
        let context = state.withLock { state in
            (state.sequence, state.flow, state.activeIntervals.removeValue(forKey: name))
        }
        guard let intervalState = context.2 else {
            return
        }

        signposter.endInterval(
            "StartupPhase",
            intervalState,
            "\(intervalMessage(sequence: context.0, flow: context.1, name: name, details: details, action: "end"))"
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func intervalMessage(sequence: Int, flow: String, name: String, details: String?, action: String) -> String {
        if let details {
            "startup[\(sequence):\(flow)] \(name) \(action) \(details)"
        } else {
            "startup[\(sequence):\(flow)] \(name) \(action)"
        }
    }
}

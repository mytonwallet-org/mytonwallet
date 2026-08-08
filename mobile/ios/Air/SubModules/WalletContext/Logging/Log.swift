
import Foundation
import UIKit

private let PRINT_ALL = false
private let PRINT_NOTHING = false

private let MAX_BUFFER = 1_000_000

public let appStart = Date()


public actor LogStore {
    
    public static let shared = LogStore()

    private nonisolated let buffer: UnfairLock<Data> = .init(initialState: Data())
    private nonisolated let storage = LogFileStorage.live
    
    private init() {
        _ = appStart
        try? storage.prepare()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { self?.syncronize() }
        }
    }
    
    private func append(_ entry: LogEntry) {
        if let entry = entry.composedForFile.data(using: .utf8) {
            let count = buffer.withLock { buffer in
                buffer.append(entry)
                return buffer.count
            }
            if count > MAX_BUFFER { syncronize() }
        }
    }

    fileprivate func write(_ entry: LogEntry) {
        append(entry)
    }

    fileprivate func writeCritical(_ entry: LogEntry) {
        append(entry)
        syncronize()
    }
    
    public nonisolated func syncronize() {
        do {
            try buffer.withLock { buffer in
                guard !buffer.isEmpty else { return }

                try storage.append(buffer)
                buffer.removeAll()
            }

        } catch {
        }
    }
    
    public func exportFile() throws -> URL {
        try buffer.withLock { buffer in
            if !buffer.isEmpty {
                try storage.append(buffer)
                buffer.removeAll()
            }
            return try storage.exportSnapshot()
        }
    }
}


fileprivate enum LogLevel {
    case info, error, fault
    
    var letter: String {
        switch self {
        case .info:
            "I"
        case .error:
            "E"
        case .fault:
            "F"
        }
    }
}


public enum LogPrivacy {
    case `public`
    case redacted
}


public struct LogFaultEvent: Sendable {
    public let category: String
    public let message: String
    public let fileID: String
    public let function: String
    public let line: Int
}


public typealias LogFaultReporter = @Sendable (LogFaultEvent) -> Void


private let faultReporterStorage = UnfairLock<LogFaultReporter?>(initialState: nil)


public struct Log: Sendable {
    
    public static let shared = Log("Shared")
    public static let api = Log("API")
    
    public var category: String
    
    public init(_ category: String = #fileID) {
        self.category = category
    }

    public static func setFaultReporter(_ reporter: LogFaultReporter?) {
        faultReporterStorage.withLock { $0 = reporter }
    }
    
    private func log(_ level: LogLevel, _ message: LogMessage, fileOnly: Bool, fileID: String, function: String, line: Int) {
        let entry = LogEntry(category: category, level: level, message: message, date: .now, fileID: fileID, function: function, line: line)
        #if DEBUG
        if (!fileOnly || PRINT_ALL) && !PRINT_NOTHING {
            print(entry.composedForDisplay)
        }
        #endif
        if case .fault = level {
            reportFault(entry)
        }
        Task {
            await LogStore.shared.write(entry)
        }
    }

    public func info(_ message: LogMessage, fileOnly: Bool = false, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(.info, message, fileOnly: fileOnly, fileID: fileID, function: function, line: line)
    }
    
    public func error(_ message: LogMessage, fileOnly: Bool = false, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(.error, message, fileOnly: fileOnly, fileID: fileID, function: function, line: line)
    }
    
    public func fault(_ message: LogMessage, fileOnly: Bool = false, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(.fault, message, fileOnly: fileOnly, fileID: fileID, function: function, line: line)
    }

    public func critical(_ message: LogMessage, fileOnly: Bool = false, fileID: String = #fileID, function: String = #function, line: Int = #line) async {
        let entry = LogEntry(category: category, level: .fault, message: message, date: .now, fileID: fileID, function: function, line: line)
        #if DEBUG
        if (!fileOnly || PRINT_ALL) && !PRINT_NOTHING {
            print(entry.composedForDisplay)
        }
        #endif
        reportFault(entry)
        await LogStore.shared.writeCritical(entry)
    }

    private func reportFault(_ entry: LogEntry) {
        let reporter = faultReporterStorage.withLock { $0 }
        reporter?(
            LogFaultEvent(
                category: entry.category,
                message: entry.message.composedForRemoteReporting,
                fileID: entry.fileID,
                function: entry.function,
                line: entry.line
            )
        )
    }
}


public struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    
    public struct StringInterpolation: StringInterpolationProtocol {
        
        var result: String
        var remoteReportingResult: String
        
        public init(literalCapacity: Int, interpolationCount: Int) {
            result = ""
            remoteReportingResult = ""
        }
        
        public mutating func appendLiteral(_ literal: String) {
            result += literal
            remoteReportingResult += literal
        }
        
        public mutating func appendInterpolation(_ value: Any, _ privacy: LogPrivacy? = nil) {
            switch privacy {
            case .none:
                if value is Bool || value is any Numeric {
                    let description = String(describing: value)
                    result += description
                    remoteReportingResult += description
                } else {
                    #if DEBUG
                        result += "<recated:\(String(describing: value))>"
                    #else
                        result += "<redacted>"
                    #endif
                    remoteReportingResult += "<redacted>"
                }

            case .public:
                let description = String(describing: value)
                result += description
                remoteReportingResult += description

            case .redacted: // explicitly marked redacted, will redact even numerics
                #if DEBUG
                    result += "<recated:\(String(describing: value))>"
                #else
                    result += "<redacted>"
                #endif
                remoteReportingResult += "<redacted>"
            }
        }
    }
    
    var composed: String
    var composedForRemoteReporting: String
    
    public init(stringInterpolation: StringInterpolation) {
        self.composed = stringInterpolation.result
        self.composedForRemoteReporting = stringInterpolation.remoteReportingResult
    }
    
    public init(stringLiteral value: String) {
        self.composed = value
        self.composedForRemoteReporting = value
    }
}


fileprivate struct LogEntry: Sendable {
    var category: String
    var level: LogLevel
    var message: LogMessage
    var date: Date
    var fileID: String
    var function: String
    var line: Int

    static let durationFormatStyle = Duration.TimeFormatStyle.time(pattern: .minuteSecond(padMinuteToLength: 0, fractionalSecondsLength: 3)).locale(.init(identifier: "en_US"))
    
    var composedForFile: String {
        let date = date.timeIntervalSince(appStart)
        let message = message.composed.replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: "\n", with: "\\n")
        return "\(date)\t\(level.letter)\t<\(category)>\t\(fileID):\(line)\t\(message)\n"
    }
    
    var composedForDisplay: String {
        let date = String(format: "%.6f", date.timeIntervalSince(appStart))
        let message = message.composed
        let category = "<\(category)>".padding(toLength: 15, withPad: " ", startingAt: 0)
        return "\(date) \(level.letter) \(category) \(message)"
    }
}

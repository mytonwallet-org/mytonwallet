
import Foundation
import UIKit

private let PRINT_ALL = false
private let PRINT_NOTHING = false

private let MAX_BUFFER = 1_000_000
private let MAX_LOG_FILE = 3_000_000

public var appStart = Date()


public actor LogStore {
    
    public static let shared = LogStore()

    private nonisolated let buffer: UnfairLock<Data> = .init(initialState: Data())
    private let url = URL.documentsDirectory.appending(component: "air-log.tsv")
    
    private init() {
        _ = appStart
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { self?.syncronize() }
        }
    }
    
    fileprivate func write(_ entry: LogEntry) {
        if let entry = entry.composedForFile.data(using: .utf8) {
            let count = buffer.withLock { buffer in
                buffer.append(entry)
                return buffer.count
            }
            if count > MAX_BUFFER { syncronize() }
        }
    }
    
    public nonisolated func syncronize() {
        do {
            try buffer.withLock { buffer in
                guard !buffer.isEmpty else { return }
                
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? UInt64 {
                        if fileSize > MAX_LOG_FILE {
                            let data = try Data(contentsOf: url)
                            let halfway = MAX_LOG_FILE / 2
                            let trimmedData = data.subdata(in: halfway..<data.count)
                            try trimmedData.write(to: url, options: .atomic)
                        }
                    }
                }
                
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: buffer)
                    try handle.close()
                } catch {
                    try buffer.write(to: url)
                }
                buffer.removeAll()
            }

        } catch {
        }
    }
    
    public func exportFile() throws -> URL {
        syncronize()
        let exportUrl = URL.documentsDirectory.appending(component: "air-log-\(Int(Date().timeIntervalSince1970)).tsv")
        try FileManager.default.copyItem(at: url, to: exportUrl)
        return exportUrl
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


public struct Log: Sendable {
    
    public static let shared = Log("Shared")
    public static let api = Log("API")
    
    public var category: String
    
    public init(_ category: String = #fileID) {
        self.category = category
    }
    
    private func log(_ level: LogLevel, _ message: LogMessage, fileOnly: Bool, fileID: String, function: String, line: Int) {
        let entry = LogEntry(category: category, level: level, message: message, date: .now, fileID: fileID, function: function, line: line)
        #if DEBUG
        if (!fileOnly || PRINT_ALL) && !PRINT_NOTHING {
            print(entry.composedForDisplay)
        }
        #endif
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
}


public struct LogMessage: ExpressibleByStringInterpolation {
    
    public struct StringInterpolation: StringInterpolationProtocol {
        
        var result: String
        
        public init(literalCapacity: Int, interpolationCount: Int) {
            result = ""
        }
        
        public mutating func appendLiteral(_ literal: String) {
            result += literal
        }
        
        public mutating func appendInterpolation(_ value: Any, _ privacy: LogPrivacy? = nil) {
            switch privacy {
            case .none:
                if value is Bool || value is any Numeric {
                    result += String(describing: value)
                } else {
                    #if DEBUG
                        result += "<recated:\(String(describing: value))>"
                    #else
                        result += "<redacted>"
                    #endif
                }

            case .public:
                result += String(describing: value)

            case .redacted: // explicitly marked redacted, will redact even numerics
                #if DEBUG
                    result += "<recated:\(String(describing: value))>"
                #else
                    result += "<redacted>"
                #endif
            }
        }
    }
    
    var composed: String
    
    public init(stringInterpolation: StringInterpolation) {
        self.composed = stringInterpolation.result
    }
    
    public init(stringLiteral value: String) {
        self.composed = value
    }
}


fileprivate struct LogEntry {
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

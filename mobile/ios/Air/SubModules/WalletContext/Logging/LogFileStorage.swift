import Foundation

struct LogFileStorage: @unchecked Sendable {
    static let logFilename = "air-log.tsv"
    static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    let fileManager: FileManager
    let logsDirectoryURL: URL
    let logFileURL: URL
    let legacyLogFileURL: URL?
    let exportDirectoryURL: URL
    let maximumFileSize: Int

    static var live: LogFileStorage {
        let fileManager = FileManager.default
        let logsDirectoryURL = URL.applicationSupportDirectory
            .appending(component: "Logs", directoryHint: .isDirectory)
        return LogFileStorage(
            fileManager: fileManager,
            logsDirectoryURL: logsDirectoryURL,
            legacyLogFileURL: URL.documentsDirectory.appending(component: logFilename),
            exportDirectoryURL: fileManager.temporaryDirectory,
            maximumFileSize: 3_000_000
        )
    }

    init(
        fileManager: FileManager = .default,
        logsDirectoryURL: URL,
        legacyLogFileURL: URL?,
        exportDirectoryURL: URL,
        maximumFileSize: Int
    ) {
        self.fileManager = fileManager
        self.logsDirectoryURL = logsDirectoryURL
        self.logFileURL = logsDirectoryURL.appending(component: Self.logFilename)
        self.legacyLogFileURL = legacyLogFileURL
        self.exportDirectoryURL = exportDirectoryURL
        self.maximumFileSize = maximumFileSize
    }

    func prepare() throws {
        try fileManager.createDirectory(
            at: logsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.fileProtection]
        )
        try applyFileProtection(to: logsDirectoryURL)
        try excludeLogsDirectoryFromBackup()
        try migrateLegacyLogIfNeeded()

        if fileManager.fileExists(atPath: logFileURL.path) {
            try applyFileProtection(to: logFileURL)
        }
    }

    func append(_ data: Data) throws {
        guard !data.isEmpty else { return }
        try prepare()
        try rotateIfNeeded(pendingByteCount: data.count)
        try createLogFileIfNeeded()

        let handle = try FileHandle(forWritingTo: logFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try applyFileProtection(to: logFileURL)
    }

    func exportSnapshot() throws -> URL {
        try prepare()
        try createLogFileIfNeeded()
        try fileManager.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let exportURL = exportDirectoryURL.appending(
            component: "air-log-\(timestamp)-\(UUID().uuidString).tsv"
        )
        try fileManager.copyItem(at: logFileURL, to: exportURL)
        try applyFileProtection(to: exportURL)
        return exportURL
    }

    static func lineAlignedTail(of data: Data, maximumByteCount: Int) -> Data {
        guard maximumByteCount > 0 else { return Data() }
        guard data.count > maximumByteCount else { return data }

        let candidate = data.index(data.endIndex, offsetBy: -maximumByteCount)
        let startsAtLineBoundary = candidate == data.startIndex
            || data[data.index(before: candidate)] == UInt8(ascii: "\n")
        if startsAtLineBoundary {
            return data.subdata(in: candidate..<data.endIndex)
        }

        guard let newline = data[candidate...].firstIndex(of: UInt8(ascii: "\n")) else {
            return Data()
        }
        let start = data.index(after: newline)
        return data.subdata(in: start..<data.endIndex)
    }

    private func rotateIfNeeded(pendingByteCount: Int) throws {
        guard fileManager.fileExists(atPath: logFileURL.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize + pendingByteCount > maximumFileSize else { return }

        let data = try Data(contentsOf: logFileURL)
        let retainedData = Self.lineAlignedTail(
            of: data,
            maximumByteCount: max(1, maximumFileSize / 2)
        )
        try writeProtected(retainedData, to: logFileURL)
    }

    private func migrateLegacyLogIfNeeded() throws {
        guard let legacyLogFileURL,
              legacyLogFileURL != logFileURL,
              fileManager.fileExists(atPath: legacyLogFileURL.path)
        else {
            return
        }

        if fileManager.fileExists(atPath: logFileURL.path) {
            var combinedData = try Data(contentsOf: legacyLogFileURL)
            if !combinedData.isEmpty, combinedData.last != UInt8(ascii: "\n") {
                combinedData.append(UInt8(ascii: "\n"))
            }
            combinedData.append(try Data(contentsOf: logFileURL))
            let retainedData = combinedData.count > maximumFileSize
                ? Self.lineAlignedTail(of: combinedData, maximumByteCount: max(1, maximumFileSize / 2))
                : combinedData
            try writeProtected(retainedData, to: logFileURL)
            try fileManager.removeItem(at: legacyLogFileURL)
        } else {
            try fileManager.moveItem(at: legacyLogFileURL, to: logFileURL)
            try rotateMigratedLogIfNeeded()
            try applyFileProtection(to: logFileURL)
        }
    }

    private func rotateMigratedLogIfNeeded() throws {
        let data = try Data(contentsOf: logFileURL)
        guard data.count > maximumFileSize else { return }
        let retainedData = Self.lineAlignedTail(
            of: data,
            maximumByteCount: max(1, maximumFileSize / 2)
        )
        try writeProtected(retainedData, to: logFileURL)
    }

    private func createLogFileIfNeeded() throws {
        guard !fileManager.fileExists(atPath: logFileURL.path) else { return }
        try writeProtected(Data(), to: logFileURL)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try applyFileProtection(to: url)
    }

    private func applyFileProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: Self.fileProtection],
            ofItemAtPath: url.path
        )
    }

    private func excludeLogsDirectoryFromBackup() throws {
        var url = logsDirectoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
    }
}

import Foundation
import Testing
@testable import WalletContext

@Suite("Log File Storage")
struct LogFileStorageTests {
    @Test
    func `line aligned tail drops a partial UTF-8 row`() throws {
        let data = Data("old row\nemoji 🙂 row\nnewest row\n".utf8)
        let maximumByteCount = Data("i 🙂 row\nnewest row\n".utf8).count

        let tail = LogFileStorage.lineAlignedTail(
            of: data,
            maximumByteCount: maximumByteCount
        )

        #expect(String(decoding: tail, as: UTF8.self) == "newest row\n")
    }

    @Test
    func `append rotates to complete recent rows`() throws {
        let fixture = try makeFixture(maximumFileSize: 48)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try fixture.storage.prepare()
        let existingRows = "first-row-000\nsecond-row-00\nthird-row-000\nfourth-row-00\n"
        try Data(existingRows.utf8).write(to: fixture.storage.logFileURL)

        try fixture.storage.append(Data("newest-row-00\n".utf8))

        let contents = try String(contentsOf: fixture.storage.logFileURL, encoding: .utf8)
        #expect(contents == "fourth-row-00\nnewest-row-00\n")
    }

    @Test
    func `prepare migrates the legacy Documents log`() throws {
        let fixture = try makeFixture(maximumFileSize: 1_000)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let legacyURL = try #require(fixture.storage.legacyLogFileURL)
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy row\n".utf8).write(to: legacyURL)

        try fixture.storage.prepare()

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try String(contentsOf: fixture.storage.logFileURL, encoding: .utf8) == "legacy row\n")
        let values = try fixture.storage.logsDirectoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test
    func `export snapshots are unique temporary copies`() throws {
        let fixture = try makeFixture(maximumFileSize: 1_000)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try fixture.storage.append(Data("native row\n".utf8))
        let firstURL = try fixture.storage.exportSnapshot()
        let secondURL = try fixture.storage.exportSnapshot()

        #expect(firstURL.deletingLastPathComponent() == fixture.storage.exportDirectoryURL)
        #expect(secondURL.deletingLastPathComponent() == fixture.storage.exportDirectoryURL)
        #expect(firstURL != secondURL)
        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "native row\n")

    }

    private func makeFixture(maximumFileSize: Int) throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(component: "LogFileStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let storage = LogFileStorage(
            logsDirectoryURL: rootURL.appending(path: "Application Support/Logs", directoryHint: .isDirectory),
            legacyLogFileURL: rootURL.appending(path: "Documents/air-log.tsv"),
            exportDirectoryURL: rootURL.appending(component: "tmp", directoryHint: .isDirectory),
            maximumFileSize: maximumFileSize
        )
        return Fixture(rootURL: rootURL, storage: storage)
    }
}

private struct Fixture {
    let rootURL: URL
    let storage: LogFileStorage
}

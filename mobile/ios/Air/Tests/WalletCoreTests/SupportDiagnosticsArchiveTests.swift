import Foundation
import Testing
@testable import WalletCore
import ZIPFoundation

@Suite("Support Diagnostics Archive")
struct SupportDiagnosticsArchiveTests {
    @Test @MainActor
    func `SDK log collection does not wait for an unready bridge`() async {
        let bridge = JSWebViewBridge()
        bridge.loadViewIfNeeded()

        await #expect(throws: SdkError.self) {
            try await bridge.callApiRawIfReady("getLogs")
        }
    }

    @Test
    func `archive contains native and SDK logs`() throws {
        let testDirectory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let nativeLogs = "0.100000\tI\t<Startup>\tApp.swift:1\tstarted\n"
        let nativeLogsURL = testDirectory.appending(component: "source.tsv")
        try Data(nativeLogs.utf8).write(to: nativeLogsURL)
        let sdkLogs: [[String: Any]] = [[
            "args": [#"{\"name\":\"Error\",\"message\":\"failed\"}"#],
            "level": "debugError",
            "message": "test failure",
            "time": 1_700_000_000_000,
        ]]
        let sdkLogsData = try SupportDiagnosticsArchive.encodeSDKLogs(sdkLogs)

        let archiveURL = try SupportDiagnosticsArchive.create(
            nativeLogsURL: nativeLogsURL,
            sdkLogsData: sdkLogsData,
            sdkLogsError: nil,
            destinationDirectory: testDirectory
        )
        let extractedDirectory = try extract(archiveURL, in: testDirectory)

        let files = try FileManager.default.contentsOfDirectory(atPath: extractedDirectory.path).sorted()
        #expect(files == [
            SupportDiagnosticsArchive.nativeLogsFilename,
            SupportDiagnosticsArchive.sdkLogsFilename,
        ])
        #expect(try String(
            contentsOf: extractedDirectory.appending(component: SupportDiagnosticsArchive.nativeLogsFilename),
            encoding: .utf8
        ) == nativeLogs)

        let decodedSDKLogs = try JSONSerialization.jsonObject(
            with: Data(contentsOf: extractedDirectory.appending(component: SupportDiagnosticsArchive.sdkLogsFilename))
        ) as? [[String: Any]]
        #expect(decodedSDKLogs?.first?["message"] as? String == "test failure")
        #expect(decodedSDKLogs?.first?["level"] as? String == "debugError")
    }

    @Test
    func `archive records an SDK collection failure without dropping native logs`() throws {
        let testDirectory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let nativeLogsURL = testDirectory.appending(component: "source.tsv")
        try Data("native log\n".utf8).write(to: nativeLogsURL)

        let archiveURL = try SupportDiagnosticsArchive.create(
            nativeLogsURL: nativeLogsURL,
            sdkLogsData: Data("[]\n".utf8),
            sdkLogsError: "SDK bridge is unavailable",
            destinationDirectory: testDirectory
        )
        let extractedDirectory = try extract(archiveURL, in: testDirectory)

        #expect(FileManager.default.fileExists(
            atPath: extractedDirectory.appending(component: SupportDiagnosticsArchive.nativeLogsFilename).path
        ))
        #expect(try String(
            contentsOf: extractedDirectory.appending(component: SupportDiagnosticsArchive.sdkLogsErrorFilename),
            encoding: .utf8
        ) == "SDK bridge is unavailable\n")
    }

    private func makeTestDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(component: "SupportDiagnosticsArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func extract(_ archiveURL: URL, in testDirectory: URL) throws -> URL {
        let destination = testDirectory.appending(component: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archiveURL, to: destination)
        return destination
    }
}
